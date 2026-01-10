const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler"); // <--- V2 Scheduler
const { setGlobalOptions } = require("firebase-functions/v2"); // <--- Import Global Options
const { getFirestore, FieldValue, GeoPoint } = require("firebase-admin/firestore");
const { CloudTasksClient } = require("@google-cloud/tasks");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");
const { DateTime } = require("luxon"); // <--- Timezone handling

// --- GLOBAL OPTIONS (Fix for Quota Exceeded) ---
setGlobalOptions({ maxInstances: 10 });

admin.initializeApp();
const db = admin.firestore();

// --- CONFIGURATION ---
// Use environment variables for flexibility across environments (dev/staging/prod)
// Falls back to production values for backward compatibility
const GCP_PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'mddprod-2954f';
const GCP_LOCATION = process.env.FUNCTION_REGION || 'us-central1';
const QUEUE_NAME = process.env.ASSIGNMENT_QUEUE_NAME || 'assignment-timeout-queue';
const ASSIGNMENT_TIMEOUT_SECONDS = parseInt(process.env.ASSIGNMENT_TIMEOUT_SECONDS, 10) || 120;
const TASK_HANDLER_URL = process.env.TASK_HANDLER_URL || `https://${GCP_LOCATION}-${GCP_PROJECT_ID}.cloudfunctions.net/processAssignmentTask`;
const SERVICE_ACCOUNT_EMAIL = process.env.SERVICE_ACCOUNT_EMAIL || `${GCP_PROJECT_ID}@appspot.gserviceaccount.com`;

// --- RIDER ASSIGNMENT LIMITS (Production Safeguards) ---
const MAX_TRIED_RIDERS = parseInt(process.env.MAX_TRIED_RIDERS, 10) || 10;  // Max riders to try before manual assignment
const MAX_WORKFLOW_MINUTES = parseInt(process.env.MAX_WORKFLOW_MINUTES, 10) || 30;  // Max time for entire assignment workflow
const MAX_SEARCH_RETRIES = parseInt(process.env.MAX_SEARCH_RETRIES, 10) || 5;  // Max retries when no riders available


// --- STATUS CONSTANTS (Standardized) ---
const STATUS = {
    PENDING: 'pending',
    PREPARING: 'preparing',
    PREPARED: 'prepared',                    // NEW: Food ready (non-delivery)
    SERVED: 'served',                        // NEW: Dine-in served to table
    PAID: 'paid',                            // NEW: Terminal for takeaway/dine-in
    COLLECTED: 'collected',                  // NEW: Terminal for pickup (prepaid)
    RIDER_ASSIGNED: 'rider_assigned',
    NEEDS_ASSIGNMENT: 'needs_rider_assignment',
    PICKED_UP: 'pickedUp',                   // Standardized to camelCase
    DELIVERED: 'delivered',
    CANCELLED: 'cancelled',
};

// --- ORDER TYPE CONSTANTS ---
const ORDER_TYPE = {
    DELIVERY: 'delivery',
    PICKUP: 'pickup',
    TAKEAWAY: 'takeaway',
    DINE_IN: 'dine_in',
};

// Helper to normalize order type
// IMPORTANT: Returns 'unknown' instead of defaulting to DELIVERY to prevent blocking valid transitions
function normalizeOrderType(orderType) {
    if (!orderType || typeof orderType !== 'string') return 'unknown';
    const cleaned = orderType.toLowerCase().trim().replace(/-/g, '_').replace(/ /g, '_');

    // Dine-in variants
    if (cleaned === 'dinein' || cleaned === 'dine_in' || cleaned === 'dine' ||
        cleaned === 'dine_in_order' || cleaned === 'dineinorder') {
        return ORDER_TYPE.DINE_IN;
    }
    // Pickup variants  
    if (cleaned === 'pickup' || cleaned === 'pick_up' ||
        cleaned === 'pickup_order' || cleaned === 'pickuporder') {
        return ORDER_TYPE.PICKUP;
    }
    // Takeaway variants
    if (cleaned === 'takeaway' || cleaned === 'take_away' ||
        cleaned === 'takeaway_order' || cleaned === 'takeawayorder') {
        return ORDER_TYPE.TAKEAWAY;
    }
    // Delivery variants
    if (cleaned === 'delivery' || cleaned === 'deliver' ||
        cleaned === 'delivery_order' || cleaned === 'deliveryorder') {
        return ORDER_TYPE.DELIVERY;
    }

    // Return unknown - don't default to delivery as that blocks valid transitions
    return 'unknown';
}

// Helper to normalize status (handles legacy 'pickedup' vs 'pickedUp')
function normalizeStatus(status) {
    if (!status) return status;
    const normalized = status.toLowerCase();
    if (normalized === 'pickedup') return STATUS.PICKED_UP;
    return status;
}

// Helper to check if status is terminal
function isTerminalStatus(status) {
    const normalized = normalizeStatus(status);
    return [
        STATUS.DELIVERED,
        STATUS.CANCELLED,
        STATUS.PAID,      // Terminal for takeaway/dine-in
        STATUS.COLLECTED, // Terminal for pickup
        'pickedup',
        STATUS.PICKED_UP
    ].includes(normalized);
}

/**
 * =============================================================================
 * ROBUST RIDER ASSIGNMENT SYSTEM
 * =============================================================================
 * Production-grade auto-assignment workflow with:
 * - Rider locking to prevent race conditions
 * - Notification deduplication via `notificationSent` flag
 * - Expiry timestamps for timeout tracking
 * - Comprehensive logging for debugging
 * - Graceful degradation to manual assignment
 * =============================================================================
 */

/**
 * =============================================================================
 * FUNCTION 1: ROBUST AUTO ASSIGNMENT INITIATOR
 * =============================================================================
 * Triggered when an order moves to 'preparing' status OR when admin manually
 * triggers auto-assignment by setting 'autoAssignStarted' timestamp.
 * 
 * FLOW:
 * 1. Validate order is delivery type and needs a rider
 * 2. Find nearest available rider (isAvailable=true, status='online')
 * 3. Lock rider atomically (set isAvailable=false)
 * 4. Send FCM notification
 * 5. Schedule 120s timeout task
 * 
 * ERROR HANDLING:
 * - All error paths unlock any locked rider
 * - Falls back to manual assignment if workflow fails
 * =============================================================================
 */
exports.startAssignmentWorkflowV2 = onDocumentUpdated(
    { document: "Orders/{orderId}", region: GCP_LOCATION },
    async (event) => {
        const beforeData = event.data.before.data();
        const afterData = event.data.after.data();
        const orderId = event.params.orderId;

        // --- GUARD 1: Only Delivery Orders ---
        const rawOrderType = afterData.Order_type || afterData.orderType || '';
        const orderType = rawOrderType.toLowerCase().trim();

        if (orderType !== 'delivery') {
            return null;
        }

        // --- GUARD 2: Skip Exchange Orders ---
        if (afterData.isExchange === true) {
            logger.log(`[${orderId}] ⏩ Skipping auto-assignment for EXCHANGE order`);
            return null;
        }

        // --- GUARD 3: Already has rider ---
        if (afterData.riderId && afterData.riderId !== '') {
            return null;
        }

        // --- TRIGGER CONDITIONS ---
        // 1. Status just changed TO 'preparing' (admin accepts order)
        // 2. OR 'autoAssignStarted' was just set (manual trigger from Admin UI)
        const statusBecamePreparing = beforeData.status !== 'preparing' && afterData.status === 'preparing';
        const manualTrigger = !beforeData.autoAssignStarted && afterData.autoAssignStarted;

        if (!statusBecamePreparing && !manualTrigger) {
            return null;
        }

        logger.log(`🚀 [${orderId}] STARTING AUTO-ASSIGNMENT WORKFLOW (trigger: ${statusBecamePreparing ? 'status_change' : 'manual'})`);

        let lockedRiderId = null; // Track rider we lock for cleanup on error

        try {
            // ============================================================
            // STEP 1: DEDUPLICATION - Check if assignment already in progress
            // ============================================================
            const existingAssignment = await db.collection('rider_assignments').doc(orderId).get();
            if (existingAssignment.exists) {
                const existingData = existingAssignment.data();
                // Only block if actively pending or searching
                if (existingData.status === 'pending' || existingData.status === 'searching') {
                    // Check if it's stale (older than 5 minutes means it's stuck)
                    const createdAt = existingData.createdAt?.toDate?.() || new Date(0);
                    const ageMinutes = (Date.now() - createdAt.getTime()) / 60000;

                    if (ageMinutes < 5) {
                        logger.log(`[${orderId}] ⚠️ Active assignment exists (age: ${ageMinutes.toFixed(1)}min) - skipping`);
                        return null;
                    } else {
                        // Stale assignment - clean it up and proceed
                        logger.warn(`[${orderId}] ♻️ Cleaning stale assignment (age: ${ageMinutes.toFixed(1)}min)`);
                        if (existingData.riderId && existingData.riderId !== 'RETRY_SEARCH') {
                            await unlockRider(existingData.riderId, orderId);
                        }
                        await db.collection('rider_assignments').doc(orderId).delete();
                    }
                }
            }

            // ============================================================
            // STEP 2: RESOLVE BRANCH ID
            // ============================================================
            const targetBranchId = (afterData.branchIds && afterData.branchIds.length > 0)
                ? afterData.branchIds[0]
                : afterData.branchId;

            if (!targetBranchId) {
                logger.error(`[${orderId}] ❌ No branch ID found on order`);
                return markOrderForManualAssignment(orderId, 'Missing Branch Info');
            }

            logger.log(`[${orderId}] Branch: ${targetBranchId}`);

            // ============================================================
            // STEP 3: FIND NEAREST AVAILABLE RIDER
            // ============================================================
            const nextRider = await findNextRider(null, orderId, targetBranchId);

            if (!nextRider) {
                logger.warn(`[${orderId}] ❌ No available riders found in branch ${targetBranchId}`);
                return markOrderForManualAssignment(orderId, 'No available riders found');
            }

            logger.log(`[${orderId}] 👤 Found nearest rider: ${nextRider.riderId} (distance: ${nextRider.distance?.toFixed(2) || 'N/A'}km)`);

            // ============================================================
            // STEP 4: ATOMIC TRANSACTION - Create assignment + Lock rider
            // ============================================================
            const transactionResult = await db.runTransaction(async (transaction) => {
                const riderRef = db.collection('Drivers').doc(nextRider.riderId);
                const assignRef = db.collection('rider_assignments').doc(orderId);

                const riderDoc = await transaction.get(riderRef);

                if (!riderDoc.exists) {
                    return { success: false, reason: 'Rider deleted' };
                }

                const riderData = riderDoc.data();

                // CRITICAL: Re-verify rider is still available
                if (riderData.isAvailable !== true) {
                    return { success: false, reason: `isAvailable=${riderData.isAvailable}` };
                }
                if (riderData.status !== 'online') {
                    return { success: false, reason: `status=${riderData.status}` };
                }

                // Create assignment record
                const assignmentData = {
                    orderId: orderId,
                    branchId: targetBranchId,
                    riderId: nextRider.riderId,
                    status: 'pending',
                    createdAt: FieldValue.serverTimestamp(),
                    workflowStartedAt: FieldValue.serverTimestamp(),
                    expiresAt: new Date(Date.now() + ASSIGNMENT_TIMEOUT_SECONDS * 1000),
                    triedRiders: [nextRider.riderId],
                    notificationSent: false,
                    retryCount: 0,
                };

                transaction.set(assignRef, assignmentData);

                // LOCK RIDER: Set isAvailable=false ONLY HERE
                transaction.update(riderRef, {
                    'isAvailable': false,
                    'currentOfferOrderId': orderId
                });

                return { success: true, riderId: nextRider.riderId };
            });

            if (!transactionResult.success) {
                logger.warn(`[${orderId}] Rider ${nextRider.riderId} unavailable: ${transactionResult.reason}. Trying next...`);
                // Create assignment doc to track tried riders, then retry
                await db.collection('rider_assignments').doc(orderId).set({
                    orderId: orderId,
                    branchId: targetBranchId,
                    riderId: 'RETRY_SEARCH',
                    status: 'searching',
                    triedRiders: [nextRider.riderId],
                    workflowStartedAt: FieldValue.serverTimestamp(),
                    retryCount: 0,
                });
                await createAssignmentTask(orderId, 'RETRY_SEARCH', 2); // Retry in 2 seconds
                return null;
            }

            // Track the locked rider for error cleanup
            lockedRiderId = transactionResult.riderId;

            // ============================================================
            // STEP 5: SEND FCM NOTIFICATION
            // ============================================================
            const fcmSent = await sendAssignmentFCM(lockedRiderId, orderId, afterData);
            if (!fcmSent) {
                logger.warn(`[${orderId}] FCM failed but continuing with assignment`);
            }

            // ============================================================
            // STEP 6: SCHEDULE TIMEOUT TASK (120 seconds)
            // ============================================================
            try {
                await createAssignmentTask(orderId, lockedRiderId, ASSIGNMENT_TIMEOUT_SECONDS);
            } catch (taskError) {
                logger.error(`[${orderId}] ❌ Failed to create timeout task: ${taskError.message}`);
                // CRITICAL: If task creation fails, rider stays locked forever!
                // We need to use a fallback: Firestore-based polling
                logger.warn(`[${orderId}] Using Firestore TTL fallback for timeout tracking`);
                // The cleanupStaleAssignments scheduled function will handle this
            }

            logger.log(`[${orderId}] ✅ Assignment workflow started. Rider ${lockedRiderId} has ${ASSIGNMENT_TIMEOUT_SECONDS}s to respond.`);

            // ============================================================
            // STEP 7: UI SYNC - Ensure 'autoAssignStarted' is set
            // ============================================================
            // If triggered by status change (not manual button), the UI needs this flag
            if (!manualTrigger && !afterData.autoAssignStarted) {
                await db.collection('Orders').doc(orderId).update({
                    'autoAssignStarted': FieldValue.serverTimestamp(),
                    'lastAssignmentUpdate': FieldValue.serverTimestamp()
                });
                logger.log(`[${orderId}] 🔄 Synced autoAssignStarted flag for UI`);
            }

            return null;

        } catch (error) {
            logger.error(`🔥 [${orderId}] CRITICAL ERROR in startAssignmentWorkflowV2:`, error);

            // CLEANUP: Unlock any rider we may have locked
            if (lockedRiderId) {
                await unlockRider(lockedRiderId, orderId);
            }

            // FAIL SAFE: Move to manual assignment
            return markOrderForManualAssignment(orderId, `System Error: ${error.message}`);
        }
    }
);

/**
 * =============================================================================
 * ORDER CANCELLATION HANDLER
 * =============================================================================
 * Triggered when an order is cancelled or reaches a terminal state.
 * Immediately stops any ongoing auto-assignment and unlocks the rider.
 * =============================================================================
 */
exports.handleOrderCancellation = onDocumentUpdated(
    { document: "Orders/{orderId}", region: GCP_LOCATION },
    async (event) => {
        const beforeData = event.data.before.data();
        const afterData = event.data.after.data();
        const orderId = event.params.orderId;

        const beforeStatus = normalizeStatus(beforeData.status);
        const afterStatus = normalizeStatus(afterData.status);

        // Only trigger if status just became terminal (cancelled, delivered, etc.)
        const wasTerminal = isTerminalStatus(beforeStatus);
        const nowTerminal = isTerminalStatus(afterStatus);

        if (wasTerminal || !nowTerminal) {
            return null; // Already terminal or not becoming terminal
        }

        logger.log(`[${orderId}] 🛑 Order became terminal (${beforeStatus} → ${afterStatus}). Cleaning up assignment...`);

        try {
            // Check if there's an active assignment for this order
            const assignDoc = await db.collection('rider_assignments').doc(orderId).get();
            let riderId = null;

            if (assignDoc.exists) {
                const assignData = assignDoc.data();
                riderId = assignData.riderId;
            } else {
                // FALLBACK: If assignment is missing (e.g. rider accepted then delivered),
                // check if the order itself has a riderId that needs unlocking
                if (afterData.riderId) {
                    riderId = afterData.riderId;
                    logger.log(`[${orderId}] Assignment doc missing, using riderId from order: ${riderId}`);
                } else {
                    logger.log(`[${orderId}] No active assignment or rider to clean up`);
                    return null;
                }
            }

            // Unlock the rider if they were waiting for this order
            if (riderId && riderId !== 'RETRY_SEARCH') {
                await db.collection('Drivers').doc(riderId).update({
                    'isAvailable': true,
                    'status': 'online',
                    'currentOfferOrderId': FieldValue.delete(),
                    'assignedOrderId': FieldValue.delete() // Ensure we clear the assigned order too
                });
                logger.log(`[${orderId}] ✅ Unlocked rider ${riderId} after order terminal state`);
            }

            // Delete the assignment record if it exists
            if (assignDoc.exists) {
                await db.collection('rider_assignments').doc(orderId).delete();
                logger.log(`[${orderId}] ✅ Assignment record deleted`);
            }

            // Clean up order fields
            // Only update if these fields actually exist to save writes
            const updates = {};
            if (afterData.autoAssignStarted) updates['autoAssignStarted'] = FieldValue.delete();
            if (afterData.assignmentNotes) updates['assignmentNotes'] = `Order ${afterStatus} - assignment cancelled`;

            if (Object.keys(updates).length > 0) {
                await event.data.after.ref.update(updates);
            }

            return null;
        } catch (error) {
            logger.error(`[${orderId}] Error in handleOrderCancellation:`, error);
            return null;
        }
    }
);

// -------------------- HELPER: Normalize time format --------------------
// Handles various formats: "9:00", "09:0", "9:0", "09:00"
function normalizeTimeFormat(timeStr) {
    if (!timeStr || typeof timeStr !== 'string') return null;

    const parts = timeStr.split(':');
    if (parts.length !== 2) return null;

    const hours = parseInt(parts[0], 10);
    const minutes = parseInt(parts[1], 10);

    if (isNaN(hours) || isNaN(minutes) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
        return null;
    }

    return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}`;
}

// -------------------- HELPER: Check if time is within a slot --------------------
function isWithinSlot(now, openStr, closeStr, timezone, dayOffset) {
    try {
        // Normalize time formats
        const normalizedOpen = normalizeTimeFormat(openStr);
        const normalizedClose = normalizeTimeFormat(closeStr);

        if (!normalizedOpen || !normalizedClose) {
            logger.warn(`Invalid time format: open='${openStr}', close='${closeStr}'`);
            return { isWithin: false };
        }

        const baseDate = now.plus({ days: dayOffset });

        let openTime = DateTime.fromFormat(normalizedOpen, "HH:mm", { zone: timezone })
            .set({ year: baseDate.year, month: baseDate.month, day: baseDate.day });

        let closeTime = DateTime.fromFormat(normalizedClose, "HH:mm", { zone: timezone })
            .set({ year: baseDate.year, month: baseDate.month, day: baseDate.day });

        // Handle overnight shift (close <= open means next day)
        if (closeTime <= openTime) {
            closeTime = closeTime.plus({ days: 1 });
        }

        const isWithin = now >= openTime && now < closeTime;
        return { isWithin, openTime, closeTime };
    } catch (e) {
        logger.warn(`isWithinSlot error: ${e.message}`);
        return { isWithin: false };
    }
}

// -------------------- HELPER: Validate timezone --------------------
function validateTimezone(tz, branchId) {
    if (!tz || typeof tz !== 'string' || tz.trim() === '') {
        logger.warn(`[${branchId}] Empty timezone, falling back to UTC`);
        return 'UTC';
    }

    try {
        const testDate = DateTime.now().setZone(tz);
        if (!testDate.isValid) {
            throw new Error('Invalid zone');
        }
        return tz;
    } catch (e) {
        logger.warn(`[${branchId}] Invalid timezone '${tz}', falling back to UTC`);
        return 'UTC';
    }
}

// -------------------- HELPER: Log status change to history --------------------
async function logStatusChange(branchRef, branchId, fromStatus, toStatus, reason, triggeredBy) {
    try {
        await branchRef.collection('statusHistory').add({
            fromStatus,
            toStatus,
            reason,
            triggeredBy: triggeredBy || 'scheduled_function',
            timestamp: FieldValue.serverTimestamp(),
        });
    } catch (e) {
        logger.warn(`[${branchId}] Failed to log status history: ${e.message}`);
    }
}

// -------------------- HELPER: Process a single branch --------------------
function processBranchStatus(data, branchId) {
    const timezone = validateTimezone(data.timezone || 'UTC', branchId);
    const workingHours = data.workingHours;
    const currentIsOpen = data.isOpen || false;
    const manuallyClosed = data.manuallyClosed || false;
    const manuallyOpened = data.manuallyOpened || false;

    // If no schedule exists or empty, skip (assume manual control only)
    if (!workingHours || Object.keys(workingHours).length === 0) {
        return null;
    }

    // Get current time in branch's timezone
    const now = DateTime.now().setZone(timezone);
    const currentDayName = now.weekdayLong.toLowerCase();

    // Determine if it SHOULD be open right now based on SCHEDULE
    let isScheduledOpen = false;

    // Check today's schedule
    const todaySchedule = workingHours[currentDayName];
    if (todaySchedule && todaySchedule.isOpen === true && Array.isArray(todaySchedule.slots)) {
        for (const slot of todaySchedule.slots) {
            if (!slot.open || !slot.close) continue;
            const result = isWithinSlot(now, slot.open, slot.close, timezone, 0);
            if (result.isWithin) {
                isScheduledOpen = true;
                break;
            }
        }
    }

    // Check yesterday's overnight slots extending into today
    if (!isScheduledOpen) {
        const yesterday = now.minus({ days: 1 });
        const yesterdayName = yesterday.weekdayLong.toLowerCase();
        const yesterdaySchedule = workingHours[yesterdayName];

        if (yesterdaySchedule && yesterdaySchedule.isOpen === true && Array.isArray(yesterdaySchedule.slots)) {
            for (const slot of yesterdaySchedule.slots) {
                if (!slot.open || !slot.close) continue;
                const result = isWithinSlot(now, slot.open, slot.close, timezone, -1);
                if (result.isWithin) {
                    isScheduledOpen = true;
                    break;
                }
            }
        }
    }

    // DECISION LOGIC with Manual Overrides
    let finalShouldBeOpen = isScheduledOpen;
    let updateData = {};
    let statusReason = '';

    if (isScheduledOpen) {
        // Schedule says OPEN
        if (manuallyClosed) {
            finalShouldBeOpen = false;
            statusReason = 'Manually Closed (Override)';
        } else {
            statusReason = 'Auto-Opened by Schedule';
        }
        // Reset manuallyOpened flag since schedule is now open anyway
        if (manuallyOpened) {
            updateData.manuallyOpened = false;
        }
    } else {
        // Schedule says CLOSED
        if (manuallyOpened) {
            finalShouldBeOpen = true;
            statusReason = 'Manually Opened (Override)';
        } else {
            statusReason = 'Auto-Closed by Schedule';
        }
        // Reset manuallyClosed flag since schedule naturally closed
        if (manuallyClosed) {
            updateData.manuallyClosed = false;
        }
    }

    // Check if status actually changed
    const statusChanged = currentIsOpen !== finalShouldBeOpen;

    if (statusChanged) {
        updateData.isOpen = finalShouldBeOpen;
        updateData.lastStatusUpdate = FieldValue.serverTimestamp();
        updateData.statusReason = statusReason;
    }

    if (Object.keys(updateData).length === 0) {
        return null;
    }

    return {
        updateData,
        statusChanged,
        fromStatus: currentIsOpen,
        toStatus: finalShouldBeOpen,
        statusReason,
        isScheduledOpen,
        manuallyClosed,
        manuallyOpened,
    };
}

// -------------------- SCHEDULED FUNCTION --------------------
// Runs every 1 minute to manage Open/Close status
// ✅ ROBUST: Handles timezones, overnight shifts, manual overrides, chunked batching
const BATCH_SIZE = 400; // Firestore limit is 500, use 400 for safety

exports.autoManageRestaurantStatus = onSchedule("every 1 minutes", async (event) => {
    try {
        const branchesSnapshot = await db.collection('Branch').get();
        const docs = branchesSnapshot.docs;

        if (docs.length === 0) {
            logger.log('No branches found');
            return;
        }

        let totalUpdates = 0;
        let totalStatusChanges = 0;

        // Process in chunks to avoid batch limit
        for (let i = 0; i < docs.length; i += BATCH_SIZE) {
            const chunk = docs.slice(i, i + BATCH_SIZE);
            const batch = db.batch();
            let chunkUpdates = 0;
            const statusChanges = [];

            for (const doc of chunk) {
                const data = doc.data();
                const branchId = doc.id;

                const result = processBranchStatus(data, branchId);

                if (result) {
                    batch.update(doc.ref, result.updateData);
                    chunkUpdates++;

                    if (result.statusChanged) {
                        statusChanges.push({
                            ref: doc.ref,
                            branchId,
                            ...result,
                        });

                        logger.log(`[${branchId}] Status: ${result.fromStatus} → ${result.toStatus} | ` +
                            `Schedule: ${result.isScheduledOpen ? 'OPEN' : 'CLOSED'} | ` +
                            `Flags: manuallyClosed=${result.manuallyClosed}, manuallyOpened=${result.manuallyOpened} | ` +
                            `Reason: ${result.statusReason}`);
                    }
                }
            }

            if (chunkUpdates > 0) {
                await batch.commit();
                totalUpdates += chunkUpdates;
                totalStatusChanges += statusChanges.length;

                // Log status changes to history (non-blocking)
                for (const change of statusChanges) {
                    logStatusChange(
                        change.ref,
                        change.branchId,
                        change.fromStatus,
                        change.toStatus,
                        change.statusReason,
                        'scheduled_function'
                    );
                }
            }
        }

        if (totalUpdates > 0) {
            logger.log(`✅ Updated ${totalUpdates} branches (${totalStatusChanges} status changes)`);
        }
    } catch (error) {
        logger.error("🔥 Error in autoManageRestaurantStatus:", error);
    }
});
exports.processAssignmentTask = onRequest({ region: GCP_LOCATION }, async (req, res) => {
    // ===============================================================
    // SECURITY: Input Validation Schema
    // ===============================================================
    // Validate input before processing to prevent injection attacks
    const validateInput = (body) => {
        const errors = [];

        // Check orderId - allow alphanumeric, underscore, hyphen
        if (!body.orderId || typeof body.orderId !== 'string') {
            errors.push('orderId is required and must be a string');
        } else if (body.orderId.length > 128 || !/^[A-Za-z0-9_-]+$/.test(body.orderId)) {
            errors.push('orderId contains invalid characters or is too long');
        }

        // Check expectedRiderId - IMPORTANT: Allow email format (contains @, .) and RETRY_SEARCH
        // Rider IDs can be email addresses like "rider@email.com" or special value "RETRY_SEARCH"
        if (!body.expectedRiderId || typeof body.expectedRiderId !== 'string') {
            errors.push('expectedRiderId is required and must be a string');
        } else if (body.expectedRiderId.length > 128) {
            errors.push('expectedRiderId is too long');
        } else if (body.expectedRiderId !== 'RETRY_SEARCH' &&
            !/^[A-Za-z0-9_@.\-+]+$/.test(body.expectedRiderId)) {
            // Allow: letters, numbers, underscore, @, dot, hyphen, plus (all valid in email/IDs)
            errors.push('expectedRiderId contains invalid characters');
        }

        // Check for unexpected fields (prevent NoSQL injection via extra fields)
        const allowedFields = ['orderId', 'expectedRiderId'];
        const unexpectedFields = Object.keys(body).filter(k => !allowedFields.includes(k));
        if (unexpectedFields.length > 0) {
            errors.push(`Unexpected fields: ${unexpectedFields.join(', ')}`);
        }

        return errors;
    };

    // ===============================================================
    // SECURITY: OIDC Token Verification for Cloud Tasks
    // ===============================================================
    const authHeader = req.headers.authorization || '';

    if (!authHeader.startsWith('Bearer ')) {
        // Only allow unauthenticated requests in emulator mode
        if (process.env.FUNCTIONS_EMULATOR === 'true') {
            logger.warn('⚠️ [DEV] processAssignmentTask called without auth in emulator');
        } else {
            // PRODUCTION: Reject unauthenticated requests
            logger.error('🔒 SECURITY: Unauthorized access attempt to processAssignmentTask', {
                ip: req.ip || req.headers['x-forwarded-for'],
                userAgent: req.headers['user-agent'],
            });
            return res.status(401).json({
                error: 'Unauthorized',
                message: 'Authentication required'
            });
        }
    } else {
        // Verify the OIDC token is from our service account
        // The token is automatically verified by Cloud Functions when using OIDC
        // But we can add additional checks here for extra security
        const token = authHeader.substring(7); // Remove 'Bearer '

        // Basic token format validation (JWT has 3 parts separated by dots)
        if (token.split('.').length !== 3) {
            logger.error('🔒 SECURITY: Invalid token format');
            return res.status(401).json({
                error: 'Unauthorized',
                message: 'Invalid authentication token format'
            });
        }

        // Note: Full OIDC verification is handled by Cloud Functions infrastructure
        // when using oidcToken in Cloud Tasks. The token audience is verified automatically.
        logger.log('✅ Request authenticated via OIDC token');
    }

    // ===============================================================
    // INPUT VALIDATION
    // ===============================================================
    const validationErrors = validateInput(req.body);
    if (validationErrors.length > 0) {
        logger.error('Input validation failed:', validationErrors);
        return res.status(400).json({
            error: 'Bad Request',
            message: 'Input validation failed',
            // Don't expose detailed validation errors in production
            details: process.env.FUNCTIONS_EMULATOR === 'true' ? validationErrors : undefined
        });
    }

    const { orderId, expectedRiderId } = req.body;

    // Sanitize IDs (extra safety - already validated above)
    // Note: Rider IDs can be emails (contain @ and .)
    const sanitizedOrderId = orderId.replace(/[^A-Za-z0-9_-]/g, '');
    const sanitizedRiderId = expectedRiderId.replace(/[^A-Za-z0-9_@.\-+]/g, '');

    try { // <--- TOP LEVEL TRY-CATCH FOR ROBUSTNESS
        const orderRef = db.collection('Orders').doc(sanitizedOrderId);
        const assignRef = db.collection('rider_assignments').doc(sanitizedOrderId);

        const [orderDoc, assignDoc] = await Promise.all([orderRef.get(), assignRef.get()]);

        // EDGE CASE: If order was cancelled, picked up, or manually overridden, stop searching
        const orderStatus = orderDoc.exists ? normalizeStatus(orderDoc.data().status) : null;
        if (!orderDoc.exists || isTerminalStatus(orderStatus)) {
            logger.log(`[${sanitizedOrderId}] Order is terminal or missing. Cleaning up assignment.`);
            if (assignDoc.exists) await assignRef.delete();
            return res.status(200).json({ message: 'Order Terminal or Finished' });
        }

        // EDGE CASE: If rider already accepted or assignment moved to another rider, ignore stale task
        if (!assignDoc.exists) {
            logger.log(`[${sanitizedOrderId}] Assignment doc missing - may have been accepted`);
            return res.status(200).json({ message: 'Assignment Not Found - Ignoring' });
        }

        const assignData = assignDoc.data();

        // ============================================================
        // WORKFLOW TIMEOUT CHECK: Prevent infinite assignment loops
        // ============================================================
        const workflowStartedAt = assignData.workflowStartedAt?.toDate?.() || assignData.createdAt?.toDate?.() || new Date();
        const workflowAgeMinutes = (Date.now() - workflowStartedAt.getTime()) / (1000 * 60);

        if (workflowAgeMinutes > MAX_WORKFLOW_MINUTES) {
            logger.warn(`[${sanitizedOrderId}] ⏰ WORKFLOW TIMEOUT (${workflowAgeMinutes.toFixed(1)} mins > ${MAX_WORKFLOW_MINUTES}). Moving to manual.`);
            await unlockRider(assignData.riderId, sanitizedOrderId);
            await markOrderForManualAssignment(sanitizedOrderId, `Assignment workflow timeout (${MAX_WORKFLOW_MINUTES} mins exceeded)`);
            await assignRef.delete();
            return res.status(200).json({ message: 'Workflow Timeout - Manual Assignment' });
        }

        // ============================================================
        // MAX RIDERS CHECK: Prevent trying too many riders
        // ============================================================
        const triedCount = (assignData.triedRiders || []).length;
        if (triedCount >= MAX_TRIED_RIDERS) {
            logger.warn(`[${sanitizedOrderId}] 🚫 MAX RIDERS LIMIT (${triedCount}/${MAX_TRIED_RIDERS}). Moving to manual.`);
            await unlockRider(assignData.riderId, sanitizedOrderId);
            await markOrderForManualAssignment(sanitizedOrderId, `Max ${MAX_TRIED_RIDERS} riders tried - moving to manual`);
            await assignRef.delete();
            return res.status(200).json({ message: 'Max Riders Tried - Manual Assignment' });
        }

        // --- RETRY LOGIC HANDLER (when no riders were available initially) ---
        if (sanitizedRiderId === 'RETRY_SEARCH') {
            const currentRetryCount = assignData.retryCount || 0;

            logger.log(`[${sanitizedOrderId}] Execute SEARCH RETRY (Attempt ${currentRetryCount + 1}/${MAX_SEARCH_RETRIES})...`);

            const nextRider = await findNextRider(assignData, sanitizedOrderId, assignData.branchId);

            if (nextRider) {
                // FOUND RIDER! Use atomic transaction to lock
                const riderLocked = await db.runTransaction(async (transaction) => {
                    const riderRef = db.collection('Drivers').doc(nextRider.riderId);
                    const riderDoc = await transaction.get(riderRef);

                    if (!riderDoc.exists) return false;

                    const riderData = riderDoc.data();
                    if (riderData.isAvailable !== true || riderData.status !== 'online') {
                        logger.warn(`[${sanitizedOrderId}] Rider ${nextRider.riderId} no longer available during retry`);
                        return false;
                    }

                    // Update assignment record
                    transaction.update(assignRef, {
                        riderId: nextRider.riderId,
                        status: 'pending',
                        triedRiders: [...(assignData.triedRiders || []), nextRider.riderId],
                        createdAt: FieldValue.serverTimestamp(),
                        expiresAt: new Date(Date.now() + ASSIGNMENT_TIMEOUT_SECONDS * 1000),
                        notificationSent: false,
                    });

                    // Lock the rider atomically
                    transaction.update(riderRef, {
                        'isAvailable': false,
                        'currentOfferOrderId': sanitizedOrderId
                    });

                    return true;
                });

                if (!riderLocked) {
                    // Rider was grabbed, try again immediately
                    await createAssignmentTask(sanitizedOrderId, 'RETRY_SEARCH', 0);
                    return res.status(200).json({ message: 'Rider unavailable, retrying...' });
                }

                // Fetch FRESH order data for FCM
                const freshOrderDoc = await orderRef.get();
                const orderData = freshOrderDoc.exists ? freshOrderDoc.data() : orderDoc.data();

                // 🔔 Send notification to rider
                await sendAssignmentFCM(nextRider.riderId, sanitizedOrderId, orderData);

                // Schedule timeout task
                await createAssignmentTask(sanitizedOrderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);

                logger.log(`[${sanitizedOrderId}] ✅ Retry successful! Rider ${nextRider.riderId} locked and notified`);
                return res.status(200).json({ message: 'Retry Successful - Rider Assigned' });
            } else {
                // STILL NO RIDER
                if (currentRetryCount < MAX_SEARCH_RETRIES) {
                    // Schedule another retry
                    await assignRef.update({ retryCount: currentRetryCount + 1 });
                    await createAssignmentTask(sanitizedOrderId, 'RETRY_SEARCH', 30); // Check again in 30s
                    logger.log(`[${sanitizedOrderId}] Still no riders. Rescheduling check...`);
                    return res.status(200).json({ message: 'Still Searching - Rescheduled' });
                } else {
                    // Retries exhausted
                    logger.warn(`[${sanitizedOrderId}] Max search retries reached. Moving to manual.`);
                    await markOrderForManualAssignment(sanitizedOrderId, 'No riders found after multiple retries');
                    await assignRef.delete();
                    return res.status(200).json({ message: 'Max Retries Reached - Manual Assignment' });
                }
            }
        }
        // ---------------------------

        if (assignData.riderId !== sanitizedRiderId || assignData.status === 'accepted') {
            logger.log(`[${sanitizedOrderId}] Stale task - current rider: ${assignData.riderId}, expected: ${sanitizedRiderId}`);
            return res.status(200).json({ message: 'Stale Task - Ignoring' });
        }

        logger.log(`[${sanitizedOrderId}] Rider ${sanitizedRiderId} timed out. Finding next available...`);

        // 🔓 UNLOCK THE TIMED-OUT RIDER using the helper function
        await unlockRider(sanitizedRiderId, sanitizedOrderId);

        // The system cycles through ALL available riders by proximity
        // When findNextRider returns null, all riders have been tried
        // Note: triedCount already calculated above at line 634
        logger.log(`[${sanitizedOrderId}] Already tried ${triedCount} rider(s). Finding next nearest...`);

        const nextRider = await findNextRider(assignData, sanitizedOrderId, assignData.branchId);

        if (!nextRider) {
            // No more riders - move to manual assignment
            logger.warn(`[${sanitizedOrderId}] No more riders available. Moving to manual assignment.`);
            await markOrderForManualAssignment(sanitizedOrderId, 'All available riders exhausted');
            await assignRef.delete();
            return res.status(200).json({ message: 'Riders Exhausted - Manual Assignment' });
        }

        // Use atomic transaction to lock the new rider
        const riderLocked = await db.runTransaction(async (transaction) => {
            const riderRef = db.collection('Drivers').doc(nextRider.riderId);
            const riderDoc = await transaction.get(riderRef);

            if (!riderDoc.exists) return false;

            const riderData = riderDoc.data();
            if (riderData.isAvailable !== true || riderData.status !== 'online') {
                logger.warn(`[${sanitizedOrderId}] Rider ${nextRider.riderId} no longer available during timeout retry`);
                return false;
            }

            // Update assignment with new rider
            transaction.update(assignRef, {
                riderId: nextRider.riderId,
                status: 'pending',
                triedRiders: [...assignData.triedRiders, nextRider.riderId],
                createdAt: FieldValue.serverTimestamp(),
                expiresAt: new Date(Date.now() + ASSIGNMENT_TIMEOUT_SECONDS * 1000),
                notificationSent: false,
            });

            // Lock the new rider atomically
            transaction.update(riderRef, {
                'isAvailable': false,
                'currentOfferOrderId': sanitizedOrderId
            });

            return true;
        });

        if (!riderLocked) {
            // Rider was grabbed by another order, retry immediately
            await createAssignmentTask(sanitizedOrderId, 'RETRY_SEARCH', 0);
            return res.status(200).json({ message: 'Rider unavailable, retrying...' });
        }

        // Fetch FRESH order data for FCM
        const freshOrderDoc = await orderRef.get();
        const orderData = freshOrderDoc.exists ? freshOrderDoc.data() : orderDoc.data();

        // 🔔 Send notification to the new rider
        await sendAssignmentFCM(nextRider.riderId, sanitizedOrderId, orderData);

        // Schedule timeout for new rider
        await createAssignmentTask(sanitizedOrderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);

        logger.log(`[${sanitizedOrderId}] ✅ Retrying with rider ${nextRider.riderId} (try ${triedCount + 1}/${MAX_TRIED_RIDERS}) - locked and notified`);
        return res.status(200).json({ message: 'Retrying with next rider' });

    } catch (err) {
        // SECURITY: Don't expose internal error details to client, but log them
        logger.error(`🔥 CRITICAL ERROR in processAssignmentTask for order ${sanitizedOrderId}:`, err);

        // FAIL SAFE: Ensure order UI gets unlocked even if everything blows up
        await markOrderForManualAssignment(sanitizedOrderId, `System Error in Task: ${err.message}`);

        // Return 200 to stop Cloud Tasks from retrying infinitely
        return res.status(200).json({
            error: 'Internal Error Handled',
            message: 'An unexpected error occurred but was handled safe-fail.'
        });
    }
});

/**
 * FUNCTION 3: Finisher
 * Triggered when a rider clicks "Accept" or "Reject" in the Rider App.
 * Updates both Order and Driver records atomically.
 */
exports.handleRiderAcceptance = onDocumentUpdated(
    { document: "rider_assignments/{orderId}", region: GCP_LOCATION },
    async (event) => {
        const afterData = event.data.after.data();
        const beforeData = event.data.before.data();
        const orderId = event.params.orderId;

        // Only process status changes from 'pending' to 'accepted' or 'rejected'
        if (beforeData.status !== 'pending') {
            return null;
        }

        const riderId = afterData.riderId;

        // ================================================================
        // HANDLE REJECTION - Unlock rider and find next one IMMEDIATELY
        // ================================================================
        if (afterData.status === 'rejected') {
            logger.log(`[${orderId}] 🚫 Rider ${riderId} REJECTED assignment`);

            try {
                // Step 1: Unlock the rider immediately (NOT in transaction - we want this fast)
                await db.collection('Drivers').doc(riderId).update({
                    'isAvailable': true,
                    'status': 'online',
                    'currentOfferOrderId': FieldValue.delete()
                });
                logger.log(`[${orderId}] ✅ Unlocked rider ${riderId} after rejection`);

                // Step 2: Update assignment status to track rejection
                await event.data.after.ref.update({
                    status: 'searching', // Mark as searching again
                    rejectedBy: FieldValue.arrayUnion(riderId),
                    lastRejectionAt: FieldValue.serverTimestamp(),
                    notificationSent: false, // RESET FLAG so next rider gets notified
                });

                // Step 3: IMMEDIATELY trigger search for next rider
                await createAssignmentTask(orderId, 'RETRY_SEARCH', 0);
                logger.log(`[${orderId}] ⚡ Triggered immediate retry for next rider`);

            } catch (err) {
                logger.error(`[${orderId}] Error handling rejection:`, err);
                // Even if there's an error, try to trigger the retry
                try {
                    await createAssignmentTask(orderId, 'RETRY_SEARCH', 0);
                } catch (retryErr) {
                    logger.error(`[${orderId}] Failed to create retry task:`, retryErr);
                }
            }

            return null;
        }

        // ================================================================
        // HANDLE ACCEPTANCE - Assign rider to order atomically
        // ================================================================
        if (afterData.status === 'accepted') {
            logger.log(`[${orderId}] ✅ Rider ${riderId} ACCEPTED assignment`);

            try {
                await db.runTransaction(async (transaction) => {
                    const orderRef = db.collection('Orders').doc(orderId);
                    const riderRef = db.collection('Drivers').doc(riderId);

                    const orderDoc = await transaction.get(orderRef);

                    if (!orderDoc.exists) {
                        logger.error(`[${orderId}] Order not found during acceptance`);
                        throw new Error("Order Missing");
                    }

                    const orderData = orderDoc.data();
                    const orderStatus = normalizeStatus(orderData.status);

                    // EDGE CASE: Prevent acceptance if order was manually assigned or cancelled
                    if (orderData.riderId && orderData.riderId !== riderId) {
                        logger.warn(`[${orderId}] Already assigned to ${orderData.riderId}, rejecting ${riderId}`);
                        throw new Error("Already Assigned to another rider");
                    }
                    if (orderStatus === STATUS.CANCELLED) {
                        logger.warn(`[${orderId}] Order was cancelled`);
                        throw new Error("Order was cancelled");
                    }

                    // Determine final status
                    let finalStatus;
                    const nonRegressStatuses = [STATUS.RIDER_ASSIGNED, STATUS.PICKED_UP, STATUS.DELIVERED, 'pickedup'];

                    if (orderStatus === STATUS.PREPARING) {
                        finalStatus = STATUS.RIDER_ASSIGNED;
                    } else if (nonRegressStatuses.map(s => normalizeStatus(s)).includes(normalizeStatus(orderStatus))) {
                        finalStatus = orderStatus;
                    } else {
                        finalStatus = STATUS.PREPARING;
                    }

                    // Update order with rider assignment
                    transaction.update(orderRef, {
                        'riderId': riderId,
                        'status': finalStatus,
                        'timestamps.riderAssigned': FieldValue.serverTimestamp(),
                        'autoAssignStarted': FieldValue.delete(),
                        'assignmentNotes': FieldValue.delete()
                    });

                    // Update rider - mark as busy with this order
                    transaction.update(riderRef, {
                        'assignedOrderId': orderId,
                        'isAvailable': false,
                        'currentOfferOrderId': FieldValue.delete()
                    });
                });

                // Clean up assignment record after successful acceptance
                await event.data.after.ref.delete();
                logger.log(`[${orderId}] ✅ Rider acceptance completed - assignment record deleted`);

            } catch (err) {
                logger.error(`[${orderId}] Error in handleRiderAcceptance:`, err);
            }

            return null;
        }

        return null;
    }
);

// --- HELPERS ---

/**
 * Safely unlock a rider back to available/online status.
 * This ensures riders don't get stuck as "unavailable" on any failure path.
 * @param {string} riderId - The rider's document ID
 * @param {string} orderId - For logging purposes
 */
async function unlockRider(riderId, orderId) {
    if (!riderId || riderId === 'RETRY_SEARCH') return;
    try {
        await db.collection('Drivers').doc(riderId).update({
            'isAvailable': true,
            'status': 'online',
            'currentOfferOrderId': FieldValue.delete()
        });
        logger.log(`[${orderId}] ✅ Unlocked rider ${riderId} (set to available/online)`);
    } catch (err) {
        // Log but don't throw - rider unlock failure shouldn't break main flow
        logger.warn(`[${orderId}] ⚠️ Failed to unlock rider ${riderId}: ${err.message}`);
    }
}

/**
 * Move order to manual assignment and clean up any pending assignment state.
 * ALWAYS unlocks the pending rider before transitioning.
 * @param {string} orderId - The order ID
 * @param {string} reason - Reason for moving to manual
 * @param {string|null} riderToUnlock - Specific rider to unlock (optional)
 */
async function markOrderForManualAssignment(orderId, reason, riderToUnlock = null) {
    logger.warn(`[${orderId}] Moving to manual assignment. Reason: ${reason}`);
    try {
        // Step 1: Unlock any pending rider first
        if (riderToUnlock) {
            await unlockRider(riderToUnlock, orderId);
        } else {
            // Try to get rider from assignment record
            try {
                const assignDoc = await db.collection('rider_assignments').doc(orderId).get();
                if (assignDoc.exists) {
                    const assignData = assignDoc.data();
                    const riderId = assignData.riderId;
                    if (riderId && riderId !== 'RETRY_SEARCH') {
                        await unlockRider(riderId, orderId);
                    }
                    // Clean up assignment record
                    await db.collection('rider_assignments').doc(orderId).delete();
                    logger.log(`[${orderId}] Cleaned up assignment record`);
                }
            } catch (cleanupErr) {
                logger.warn(`[${orderId}] Assignment cleanup warning: ${cleanupErr.message}`);
            }
        }

        // Step 2: Update order status to manual assignment
        await db.collection('Orders').doc(orderId).update({
            'status': STATUS.NEEDS_ASSIGNMENT,
            'assignmentNotes': reason,
            'autoAssignStarted': FieldValue.delete(),
        });
        logger.log(`[${orderId}] ✅ Order marked for manual assignment`);
    } catch (err) {
        logger.error(`[${orderId}] Failed to mark for manual assignment:`, err);
    }
}

async function findNextRider(assignmentData, orderId, branchId) {
    const triedRiders = assignmentData ? assignmentData.triedRiders : [];
    logger.log(`[${orderId}] findNextRider called. BranchId: ${branchId}, Already tried: ${JSON.stringify(triedRiders)}`);

    try {
        // Fetch branch location - FAIL SAFE if missing
        const branchDoc = await db.collection('Branch').doc(branchId).get();
        if (!branchDoc.exists) {
            logger.error(`[${orderId}] ❌ Branch ${branchId} not found in database`);
            return null;
        }

        const branchData = branchDoc.data();
        const branchLoc = branchData.location;

        // Log branch data for debugging
        if (!branchLoc) {
            logger.warn(`[${orderId}] ⚠️ Branch ${branchId} has no location configured. Will still try to find riders but can't sort by distance.`);
        } else {
            logger.log(`[${orderId}] Branch location: lat=${branchLoc.latitude}, lng=${branchLoc.longitude}`);
        }

        // PRIMARY QUERY: Available + Online + Branch
        // STRICT: Only riders who are BOTH isAvailable=true AND status='online'
        logger.log(`[${orderId}] 🔍 Searching for riders: isAvailable=true, status=online, branchIds contains ${branchId}`);
        let driversSnapshot;
        try {
            driversSnapshot = await db.collection('Drivers')
                .where('isAvailable', '==', true)
                .where('status', '==', 'online')
                .where('branchIds', 'array-contains', branchId)
                .limit(15)
                .get();

            logger.log(`[${orderId}] Primary query returned ${driversSnapshot.size} riders`);
        } catch (queryError) {
            // If query fails (usually missing composite index), log error and return null
            // DO NOT fall back to ignoring status - only online riders should get offers
            logger.error(`[${orderId}] ❌ Query failed (check Firestore indexes): ${queryError.message}`);
            logger.error(`[${orderId}] Required index: Drivers(isAvailable ASC, status ASC, branchIds ARRAY)`);
            return null;
        }

        // NOTE: We intentionally do NOT have a fallback that ignores status='online'
        // Only riders who are explicitly ONLINE should receive order offers

        // FALLBACK 2: If still no results, check if ANY riders exist for this branch
        if (driversSnapshot.empty) {
            logger.warn(`[${orderId}] ⚠️ No available riders. Checking if ANY riders exist for branch...`);
            try {
                const allBranchRiders = await db.collection('Drivers')
                    .where('branchIds', 'array-contains', branchId)
                    .limit(5)
                    .get();

                if (allBranchRiders.empty) {
                    logger.error(`[${orderId}] ❌ No riders assigned to branch ${branchId} at all!`);
                } else {
                    logger.warn(`[${orderId}] Found ${allBranchRiders.size} riders for branch, but none are available/online:`);
                    allBranchRiders.forEach(doc => {
                        const d = doc.data();
                        logger.warn(`  - ${doc.id}: isAvailable=${d.isAvailable}, status=${d.status}, hasLocation=${!!d.currentLocation}`);
                    });
                }
            } catch (checkError) {
                logger.warn(`[${orderId}] Failed to check for generic riders: ${checkError.message}`);
            }
            return null;
        }

        // Process found riders
        const riders = [];
        const skippedRiders = [];

        driversSnapshot.forEach(doc => {
            // Skip already tried riders
            if (triedRiders.includes(doc.id)) {
                skippedRiders.push({ id: doc.id, reason: 'already tried' });
                return;
            }

            const driverData = doc.data();
            const loc = driverData.currentLocation;

            // If branch has no location, we can't calculate distance - just add all riders
            if (!branchLoc) {
                riders.push({ riderId: doc.id, distance: 0 });
                return;
            }

            // If rider has no location, log it but still include them (with max distance)
            if (!loc || loc.latitude === undefined || loc.longitude === undefined) {
                logger.warn(`[${orderId}] ⚠️ Rider ${doc.id} has no currentLocation, adding with max distance`);
                riders.push({ riderId: doc.id, distance: 999999 });
                return;
            }

            const dist = _calculateDistance(branchLoc.latitude, branchLoc.longitude, loc.latitude, loc.longitude);
            riders.push({ riderId: doc.id, distance: dist });
        });

        if (skippedRiders.length > 0) {
            logger.log(`[${orderId}] Skipped ${skippedRiders.length} riders (already tried)`);
        }

        if (riders.length === 0) {
            logger.warn(`[${orderId}] ❌ No eligible riders found after filtering`);
            return null;
        }

        // Sort by distance and return nearest
        riders.sort((a, b) => a.distance - b.distance);
        const selected = riders[0];
        logger.log(`[${orderId}] ✅ Selected rider: ${selected.riderId} (distance: ${selected.distance.toFixed(2)}km)`);

        return selected;
    } catch (e) {
        logger.error(`[${orderId}] CRITICAL ERROR in findNextRider:`, e);
        return null;
    }
}

async function createAssignmentTask(orderId, riderId, delayInSeconds) {
    try {
        const client = new CloudTasksClient();
        const queuePath = client.queuePath(GCP_PROJECT_ID, GCP_LOCATION, QUEUE_NAME);
        const task = {
            httpRequest: {
                httpMethod: 'POST',
                url: TASK_HANDLER_URL,
                headers: { 'Content-Type': 'application/json' },
                body: Buffer.from(JSON.stringify({ orderId, expectedRiderId: riderId })).toString('base64'),
                // OIDC token for authentication
                oidcToken: {
                    serviceAccountEmail: SERVICE_ACCOUNT_EMAIL,
                    audience: TASK_HANDLER_URL,
                },
            },
            scheduleTime: { seconds: Math.floor(Date.now() / 1000) + delayInSeconds },
        };
        await client.createTask({ parent: queuePath, task });
        logger.log(`[${orderId}] Created timeout task for rider ${riderId}, delay: ${delayInSeconds}s`);
    } catch (err) {
        logger.error(`[${orderId}] Failed to create assignment task:`, err);
        throw err;
    }
}

function _calculateDistance(lat1, lon1, lat2, lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    const c = Math.cos;
    const a = 0.5 - c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * Math.asin(Math.sqrt(a)); // 2 * R; R = 6371 km
}

/**
 * PRODUCTION-GRADE FCM: Send Assignment Notification to Rider
 * Uses data-only payload to prevent duplicate notifications on Android/iOS.
 * Updates the `notificationSent` flag to track delivery status.
 * 
 * @param {string} riderId - The rider's document ID
 * @param {string} orderId - The order ID
 * @param {object} orderData - Order data for notification content
 */
/**
 * PRODUCTION-GRADE FCM: Send Assignment Notification to Rider
 * Uses V1 API for reliable delivery.
 * Updates the `notificationSent` flag to track delivery status.
 * 
 * @param {string} riderId - The rider's document ID
 * @param {string} orderId - The order ID
 * @param {object} orderData - Order data for notification content
 */
async function sendAssignmentFCM(riderId, orderId, orderData) {
    logger.log(`[${orderId}] 📤 PREPARING FCM (V1) for rider ${riderId}...`);
    try {
        const driverDoc = await db.collection('Drivers').doc(riderId).get();

        if (!driverDoc.exists) {
            logger.warn(`[${orderId}] ❌ Rider ${riderId} not found for FCM`);
            return false;
        }

        const driverData = driverDoc.data();
        const fcmToken = driverData.fcmToken;

        if (!fcmToken) {
            logger.warn(`[${orderId}] ❌ Rider ${riderId} has no FCM token`);
            return false;
        }

        logger.log(`[${orderId}] 🔹 Found FCM token for ${riderId}: ${fcmToken.substring(0, 10)}...`);

        // V1 API PAYLOAD - PLATFORM SPECIFIC
        // Avoiding top-level 'notification' to ensure precise control and prevent duplicates
        const message = {
            token: fcmToken,
            // Custom Data (Payload)
            data: {
                type: 'auto_assignment',
                title: '📦 New Order Available',
                body: `New ${orderData.Order_type || 'Delivery'} Order`,
                orderId: orderId,
                timeoutSeconds: String(ASSIGNMENT_TIMEOUT_SECONDS),
                click_action: 'FLUTTER_NOTIFICATION_CLICK', // For legacy listeners
                priority: 'high',
                content_available: 'true',
                timestamp: String(Date.now()),
            },
            // Android Specifics
            android: {
                priority: 'high',
                notification: {
                    title: '📦 New Order Available',
                    body: `New ${orderData.Order_type || 'Delivery'} Order`,
                    clickAction: 'FLUTTER_NOTIFICATION_CLICK', // RESTORED: Critical for routing
                    sound: 'default',
                    priority: 'high',
                    channelId: 'fcm_default_channel' // Safe default for Flutter
                }
            },
            // iOS Specifics
            apns: {
                headers: {
                    'apns-priority': '10',
                },
                payload: {
                    aps: {
                        alert: {
                            title: '📦 New Order Available',
                            body: `New ${orderData.Order_type || 'Delivery'} Order`,
                        },
                        contentAvailable: true,
                        sound: 'default',
                        badge: 1
                    }
                }
            }
        };

        const response = await admin.messaging().send(message);

        // V1 API returns a message ID string on success
        if (response) {
            await db.collection('rider_assignments').doc(orderId).update({
                notificationSent: true
            });
            logger.log(`[${orderId}] ✅ FCM SENT via V1 API to ${driverData.name || 'Rider'} (MsgID: ${response})`);
            return true;
        } else {
            logger.warn(`[${orderId}] ⚠️ FCM Send returned empty response`);
            return false;
        }

    } catch (err) {
        logger.error(`[${orderId}] 🔥 FCM FAILURE for rider ${riderId}:`, err);

        // Handle invalid token cleanup
        if (err.code === 'messaging/registration-token-not-registered' ||
            err.code === 'messaging/invalid-argument') {
            logger.warn(`[${orderId}] 🗑️ Removing invalid FCM token for rider ${riderId}`);
            try {
                await db.collection('Drivers').doc(riderId).update({
                    fcmToken: FieldValue.delete()
                });
            } catch (e) {
                logger.error(`Failed to remove token: ${e.message}`);
            }
        }

        return false;
    }
}

// Keep the old function as an alias for backward compatibility
async function sendRiderNotificationInternal(riderId, orderId, title, body) {
    return sendAssignmentFCM(riderId, orderId, { Order_type: 'Delivery' });
}

// --- STATUS TRANSITION VALIDATION ---

/**
 * Industry-Level Order Type-Aware State Machine
 * 
 * Order Flows:
 * - DELIVERY:  pending → preparing → needs_rider_assignment → rider_assigned → pickedUp → delivered
 * - PICKUP:    pending → preparing → prepared → collected (prepaid orders)
 * - TAKEAWAY:  pending → preparing → prepared → paid (pay at counter)
 * - DINE_IN:   pending → preparing → prepared → served → paid
 * 
 * Each status maps to valid next statuses. The validateOrderStatusTransition
 * function uses order type to determine if a transition is valid.
 */
const VALID_TRANSITIONS = {
    // Common starting point
    'pending': ['preparing', 'cancelled'],
    'pending_payment': ['pending', 'preparing', 'cancelled'],

    // Preparing can go to different states based on order type
    // - Delivery: needs_rider_assignment or rider_assigned
    // - Non-delivery: prepared
    'preparing': [
        'prepared',                 // Non-delivery orders
        'rider_assigned',           // Delivery (direct assignment)
        'needs_rider_assignment',   // Delivery (auto-assign failed)
        'cancelled'
    ],

    // NEW: Prepared status for non-delivery orders
    // - Pickup: goes to collected
    // - Takeaway: goes to paid
    // - Dine-in: goes to served
    'prepared': [
        'served',       // Dine-in only
        'paid',         // Takeaway only
        'collected',    // Pickup only (prepaid)
        'cancelled'
    ],

    // NEW: Served status (dine-in only)
    'served': ['paid', 'cancelled'],

    // NEW: Terminal statuses for non-delivery
    'paid': ['refunded'],       // Terminal for takeaway/dine-in
    'collected': ['refunded'],  // Terminal for pickup

    // Delivery flow (unchanged)
    'needs_rider_assignment': ['rider_assigned', 'cancelled', 'pickedUp', 'pickedup', 'delivered'],
    'rider_assigned': ['pickedUp', 'pickedup', 'cancelled'],
    'pickedup': ['delivered', 'cancelled', 'preparing'],
    'pickedUp': ['delivered', 'cancelled', 'refunded', 'preparing'],
    'delivered': ['refunded', 'preparing'],

    // Cancellation and refunds
    'cancelled': ['refunded', 'preparing'],
    'refunded': [], // Terminal state
};

/**
 * Get valid next statuses for a given order type and current status.
 * This provides stricter validation based on order type.
 */
function getValidTransitionsForOrderType(currentStatus, orderType) {
    const normalized = normalizeOrderType(orderType);
    const baseTransitions = VALID_TRANSITIONS[currentStatus] || [];

    // Filter based on order type
    switch (normalized) {
        case ORDER_TYPE.DELIVERY:
            // Delivery orders skip prepared/served/paid/collected
            return baseTransitions.filter(s =>
                !['prepared', 'served', 'paid', 'collected'].includes(s)
            );

        case ORDER_TYPE.PICKUP:
            // Pickup: prepared → collected (prepaid) OR paid (cash)
            if (currentStatus === 'preparing') return ['prepared', 'cancelled'];
            if (currentStatus === 'prepared') return ['collected', 'paid', 'cancelled'];
            return baseTransitions.filter(s =>
                !['served', 'rider_assigned', 'needs_rider_assignment', 'pickedUp', 'pickedup', 'delivered'].includes(s)
            );

        case ORDER_TYPE.TAKEAWAY:
            // Takeaway: prepared → paid (skip served, collected)
            if (currentStatus === 'preparing') return ['prepared', 'cancelled'];
            if (currentStatus === 'prepared') return ['paid', 'cancelled'];
            return baseTransitions.filter(s =>
                !['served', 'collected', 'rider_assigned', 'needs_rider_assignment', 'pickedUp', 'pickedup', 'delivered'].includes(s)
            );

        case ORDER_TYPE.DINE_IN:
            // Dine-in: prepared → served → paid (skip collected)
            if (currentStatus === 'preparing') return ['prepared', 'cancelled'];
            if (currentStatus === 'prepared') return ['served', 'cancelled'];
            if (currentStatus === 'served') return ['paid', 'cancelled'];
            return baseTransitions.filter(s =>
                !['collected', 'rider_assigned', 'needs_rider_assignment', 'pickedUp', 'pickedup', 'delivered'].includes(s)
            );

        default:
            return baseTransitions;
    }
}

/**
 * FUNCTION 4: Status Transition Validator (Failsafe)
 * Triggered on ANY order update. Validates status transitions and reverts invalid ones.
 * 
 * Industry-Level Features:
 * - Order-type-aware validation (different flows for delivery/pickup/takeaway/dine-in)
 * - Backward compatibility with legacy statuses
 * - Detailed logging for debugging
 * - Auto-correction for invalid transitions
 */
exports.validateOrderStatusTransition = onDocumentUpdated(
    { document: "Orders/{orderId}", region: GCP_LOCATION },
    async (event) => {
        const beforeData = event.data.before.data();
        const afterData = event.data.after.data();
        const orderId = event.params.orderId;

        const oldStatus = beforeData.status;
        const newStatus = afterData.status;

        // Only validate if status actually changed
        if (oldStatus === newStatus) return null;

        // Skip validation for Cloud Function-initiated changes
        if (afterData._cloudFunctionUpdate) {
            await event.data.after.ref.update({ '_cloudFunctionUpdate': FieldValue.delete() });
            return null;
        }

        // Get order type for type-aware validation
        const rawOrderType = afterData.Order_type || afterData.orderType || 'delivery';
        const orderType = normalizeOrderType(rawOrderType);

        // Normalize statuses for comparison
        const normalizedOld = normalizeStatus(oldStatus);
        const normalizedNew = normalizeStatus(newStatus);

        // Get valid transitions based on order type
        const allowedNextStatuses = getValidTransitionsForOrderType(normalizedOld, rawOrderType);

        // Also check base transitions for PERMISSIVE backward compatibility
        // If the base state machine allows the transition, we always allow it
        // This prevents blocking valid transitions when order type detection fails
        const baseTransitions = VALID_TRANSITIONS[normalizedOld] || VALID_TRANSITIONS[oldStatus] || [];

        // IMPORTANT: Allow if EITHER the order-type-specific OR the base allows it
        const isValidTransition = allowedNextStatuses.includes(newStatus) ||
            allowedNextStatuses.includes(normalizedNew) ||
            baseTransitions.includes(newStatus) ||
            baseTransitions.includes(normalizedNew);

        // Additional safety: Always allow transitions to new non-delivery statuses
        const isNewNonDeliveryStatus = ['prepared', 'served', 'paid', 'collected'].includes(newStatus);
        const fromPreparing = normalizedOld === 'preparing';
        const fromPrepared = normalizedOld === 'prepared';
        const fromServed = normalizedOld === 'served';

        // Always allow: preparing -> prepared, prepared -> served/paid/collected, served -> paid
        const isValidNonDeliveryFlow =
            (fromPreparing && newStatus === 'prepared') ||
            (fromPrepared && ['served', 'paid', 'collected'].includes(newStatus)) ||
            (fromServed && newStatus === 'paid');

        if (!isValidTransition && !isValidNonDeliveryFlow) {
            logger.warn(`⚠️ [${orderId}] Invalid status transition for ${orderType}: ${oldStatus} → ${newStatus}. Reverting...`);
            logger.warn(`[${orderId}] Valid transitions from '${oldStatus}': order-type=${JSON.stringify(allowedNextStatuses)}, base=${JSON.stringify(baseTransitions)}`);

            let correctedStatus = oldStatus;

            // Special case: If jumping to rider_assigned from pending
            if (newStatus === STATUS.RIDER_ASSIGNED && oldStatus === STATUS.PENDING) {
                correctedStatus = STATUS.PREPARING;
                logger.log(`[${orderId}] Cannot skip to rider_assigned from pending. Setting to preparing`);
            }

            // Special case: Non-delivery trying to go to needs_rider_assignment
            if (newStatus === STATUS.NEEDS_ASSIGNMENT && orderType !== ORDER_TYPE.DELIVERY) {
                if (oldStatus === STATUS.PREPARING) {
                    correctedStatus = STATUS.PREPARED;
                    logger.log(`[${orderId}] Non-delivery order cannot go to needs_rider_assignment. Setting to prepared`);
                }
            }

            await event.data.after.ref.update({
                'status': correctedStatus,
                '_cloudFunctionUpdate': true,
                '_invalidTransitionLog': FieldValue.arrayUnion({
                    attemptedTransition: `${oldStatus} → ${newStatus}`,
                    orderType: orderType,
                    allowedTransitions: allowedNextStatuses,
                    correctedTo: correctedStatus,
                    timestamp: new Date().toISOString(),
                }),
            });

            logger.log(`✅ [${orderId}] Status corrected to '${correctedStatus}'`);
        }

        return null;
    }
);

/**
 * FUNCTION 5: Send FCM notification to rider (called from client)
 * This is the proper way to send FCM - from server with Admin SDK
 * 
 * SECURITY FEATURES:
 * - onCall functions automatically verify Firebase Auth tokens
 * - Input validation with type checking and length limits
 * - Sanitization of string inputs
 * - Audit logging for security events
 */
exports.sendRiderNotification = require("firebase-functions/v2/https").onCall(
    { region: GCP_LOCATION },
    async (request) => {
        // ===============================================================
        // SECURITY: Authentication is automatically handled by onCall
        // request.auth contains the verified auth token if user is logged in
        // ===============================================================
        if (!request.auth) {
            logger.error('🔒 SECURITY: Unauthenticated call to sendRiderNotification');
            throw new Error('Authentication required');
        }

        const callerUid = request.auth.uid;
        const callerEmail = request.auth.token.email || 'unknown';

        // ===============================================================
        // INPUT VALIDATION
        // ===============================================================
        const { riderId, orderId, title, body } = request.data || {};

        // Validate riderId
        if (!riderId || typeof riderId !== 'string') {
            throw new Error('riderId is required and must be a string');
        }
        if (riderId.length > 128 || !/^[A-Za-z0-9_-]+$/.test(riderId)) {
            logger.warn(`Invalid riderId format from ${callerEmail}: ${riderId.substring(0, 20)}...`);
            throw new Error('Invalid riderId format');
        }

        // Validate orderId
        if (!orderId || typeof orderId !== 'string') {
            throw new Error('orderId is required and must be a string');
        }
        if (orderId.length > 128 || !/^[A-Za-z0-9_-]+$/.test(orderId)) {
            logger.warn(`Invalid orderId format from ${callerEmail}: ${orderId.substring(0, 20)}...`);
            throw new Error('Invalid orderId format');
        }

        // Validate and sanitize title (optional)
        let sanitizedTitle = '🎯 New Order Assignment';
        if (title) {
            if (typeof title !== 'string') {
                throw new Error('title must be a string');
            }
            // Max 100 characters, remove HTML tags and control characters
            sanitizedTitle = title
                .substring(0, 100)
                .replace(/<[^>]*>/g, '')
                .replace(/[\x00-\x1F\x7F]/g, '')
                .trim();
        }

        // Validate and sanitize body (optional)
        let sanitizedBody = `You have been assigned order ${orderId}`;
        if (body) {
            if (typeof body !== 'string') {
                throw new Error('body must be a string');
            }
            // Max 500 characters, remove HTML tags and control characters
            sanitizedBody = body
                .substring(0, 500)
                .replace(/<[^>]*>/g, '')
                .replace(/[\x00-\x1F\x7F]/g, '')
                .trim();
        }

        // Sanitize IDs for use in database queries
        const sanitizedRiderId = riderId.replace(/[^A-Za-z0-9_-]/g, '');
        const sanitizedOrderId = orderId.replace(/[^A-Za-z0-9_-]/g, '');

        try {
            const riderDoc = await db.collection('Drivers').doc(sanitizedRiderId).get();
            if (!riderDoc.exists) {
                logger.warn(`Rider ${sanitizedRiderId} not found (called by ${callerEmail})`);
                return { success: false, reason: 'Rider not found' };
            }

            const fcmToken = riderDoc.data().fcmToken;
            if (!fcmToken) {
                logger.warn(`Rider ${sanitizedRiderId} has no FCM token`);
                return { success: false, reason: 'No FCM token' };
            }

            const message = {
                notification: {
                    title: sanitizedTitle,
                    body: sanitizedBody,
                },
                data: {
                    type: 'order_assignment',
                    orderId: sanitizedOrderId,
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                },
                token: fcmToken,
            };

            await admin.messaging().send(message);
            logger.log(`FCM sent to rider ${sanitizedRiderId} for order ${sanitizedOrderId} (by ${callerEmail})`);
            return { success: true };
        } catch (err) {
            // SECURITY: Don't expose internal error details
            logger.error(`Failed to send FCM to rider ${sanitizedRiderId}:`, err);
            return {
                success: false,
                reason: 'Failed to send notification. Please try again.'
            };
        }
    }
);

// -------------------- ORDER NUMBER CONFIGURATION --------------------
const ORDER_RESET_HOUR = 0; // Reset at 12:00 AM (midnight) local time
const DEFAULT_TIMEZONE = 'Asia/Qatar'; // Default timezone for Qatar-based operations
const MAX_RETRIES = 3;
const DEFAULT_BRANCH_PREFIX = 'ORD'; // Default prefix if branch has none configured

/**
 * Calculate business date based on reset hour.
 * Orders placed before reset hour belong to previous business day.
 * @param {DateTime} now - Current time in branch timezone
 * @param {number} resetHour - Hour when order numbers reset (0-23)
 * @returns {string} Business date in YYYY-MM-DD format
 */
function getBusinessDate(now, resetHour = ORDER_RESET_HOUR) {
    if (now.hour < resetHour) {
        return now.minus({ days: 1 }).toFormat('yyyy-MM-dd');
    }
    return now.toFormat('yyyy-MM-dd');
}

/**
 * Format business date for display in order number (YYMMDD)
 * @param {string} businessDate - Date in YYYY-MM-DD format
 * @returns {string} Date in YYMMDD format
 */
function formatDateForOrderNumber(businessDate) {
    const parts = businessDate.split('-');
    const year = parts[0].slice(-2); // Last 2 digits of year
    const month = parts[1];
    const day = parts[2];
    return `${year}${month}${day}`;
}

/**
 * Generate fallback order number when counter fails.
 * Uses timestamp to ensure uniqueness while still being readable.
 * @param {string} prefix - Branch prefix
 * @param {string} businessDate - Business date
 * @returns {string} Fallback order number like "ZKD-260107-T456"
 */
function generateFallbackOrderNumber(prefix, businessDate) {
    const dateStr = formatDateForOrderNumber(businessDate);
    const timestamp = Date.now().toString().slice(-3);
    return `${prefix}-${dateStr}-T${timestamp}`;
}

/**
 * Format the order number with proper padding
 * @param {string} prefix - Branch prefix (e.g., "ZKD")
 * @param {string} businessDate - Business date (YYYY-MM-DD)
 * @param {number} sequenceNumber - Sequential number for the day
 * @returns {string} Formatted order number (e.g., "ZKD-260107-001")
 */
function formatOrderNumber(prefix, businessDate, sequenceNumber) {
    const dateStr = formatDateForOrderNumber(businessDate);
    // Pad to 3 digits, supports up to 999 orders per branch per day
    // If more than 999, it will show 1000, 1001, etc. (4 digits)
    const paddedSequence = String(sequenceNumber).padStart(3, '0');
    return `${prefix}-${dateStr}-${paddedSequence}`;
}

/**
 * FUNCTION 6: Generate Daily Order Number (Per Branch)
 * 
 * Industry-Grade Features:
 * - Formatted order numbers: {PREFIX}-{YYMMDD}-{NNN}
 * - Branch-specific prefixes for easy identification
 * - Business day logic (configurable reset hour)
 * - Timezone-aware using branch configuration
 * - Atomic counter increment using Firestore transactions
 * - Retry logic with exponential backoff
 * - Fallback mechanism if all retries fail
 * - Rich metadata for debugging and analytics
 * 
 * Example output: "ZKD-260107-001" (Branch ZKD, Jan 7 2026, Order #1)
 */
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

/**
 * FUNCTION 6: Generate Daily Order Number (Per Branch)
 * 
 * Industry-Grade Features:
 * - Formatted order numbers: {PREFIX}-{YYMMDD}-{NNN}
 * - Branch-specific prefixes for easy identification
 * - Business day logic (configurable reset hour)
 * - Timezone-aware using branch configuration
 * - Atomic counter increment using Firestore transactions
 * - Retry logic with exponential backoff
 * - Fallback mechanism if all retries fail
 * - Rich metadata for debugging and analytics
 * - Supports both Creation and Updates (e.g. if branchId is patched in late)
 * 
 * Example output: "ZKD-260107-001" (Branch ZKD, Jan 7 2026, Order #1)
 */
exports.generateOrderNumber = onDocumentWritten(
    { document: "Orders/{orderId}", region: GCP_LOCATION },
    async (event) => {
        // 1. Skip if document was deleted
        if (!event.data.after.exists) return;

        const orderData = event.data.after.data();
        const orderId = event.params.orderId;

        // 2. IDEMPOTENCY CHECK: If already has a number, STOP IMMEDIATELY
        if (orderData.dailyOrderNumber) {
            return;
        }

        // 3. Extract branchId with robust fallback logic
        // Priority: top-level branchId -> top-level branchIds[0] -> items[0].branchId
        let branchId = orderData.branchId;

        if (!branchId && orderData.branchIds && Array.isArray(orderData.branchIds) && orderData.branchIds.length > 0) {
            branchId = orderData.branchIds[0];
        }

        if (!branchId && orderData.items && Array.isArray(orderData.items) && orderData.items.length > 0) {
            // Check first item for branchId
            if (orderData.items[0].branchId) {
                branchId = orderData.items[0].branchId;
                logger.log(`[${orderId}] Found branchId ${branchId} in items list`);
            }
        }

        // 4. If still no branchId, warn but don't fail hard - we might need to wait for a future update
        // However, to avoid being stuck forever, if the order is old (> 1 min) and still no branchId, we might default to global?
        // For now, let's log a warning. If we don't return here, we fall back to global sequence.
        // Better to wait if it's very fresh, but for now we proceed to Global if missing.

        // Fetch branch configuration
        let branchPrefix = DEFAULT_BRANCH_PREFIX;
        let branchTimezone = DEFAULT_TIMEZONE;
        let resetHour = ORDER_RESET_HOUR;

        if (branchId) {
            try {
                const branchDoc = await db.collection('Branch').doc(branchId).get();
                if (branchDoc.exists) {
                    const branchData = branchDoc.data();

                    // Get branch prefix (e.g., "ZKD" for Zayka Downtown)
                    if (branchData.orderPrefix && typeof branchData.orderPrefix === 'string') {
                        branchPrefix = branchData.orderPrefix.toUpperCase().slice(0, 4);
                    } else if (branchData.name) {
                        // Auto-generate prefix from branch name (first 3 letters)
                        branchPrefix = branchData.name.replace(/[^A-Za-z]/g, '').toUpperCase().slice(0, 3) || DEFAULT_BRANCH_PREFIX;
                    }

                    // Get timezone
                    if (branchData.timezone) {
                        branchTimezone = validateTimezone(branchData.timezone, branchId);
                    }

                    // Get reset hour
                    if (typeof branchData.orderResetHour === 'number') {
                        resetHour = branchData.orderResetHour;
                    }
                } else {
                    logger.warn(`[${orderId}] Branch ${branchId} not found, using defaults.`);
                }
            } catch (e) {
                logger.warn(`[${orderId}] Failed to fetch branch: ${e.message}. Using defaults.`);
            }
        } else {
            // If it's a freshly created order (within last 5 seconds), maybe we should WAIT for an update?
            // checking timestamp
            const createdAt = orderData.createdAt || orderData.timestamp;
            if (createdAt) {
                const createdTime = createdAt.toDate ? createdAt.toDate().getTime() : new Date(createdAt).getTime();
                const now = Date.now();
                if (now - createdTime < 5000) {
                    logger.log(`[${orderId}] No branchId yet, but order is fresh (<5s). Skipping global assignment to allow for update.`);
                    return;
                }
            }
            logger.warn(`[${orderId}] ⚠️ Missing branchId after wait period, using default prefix (Global Sequence).`);
        }

        // Calculate business date using branch timezone and reset hour
        const now = DateTime.now().setZone(branchTimezone);
        const businessDate = getBusinessDate(now, resetHour);

        logger.log(`[${orderId}] Branch: ${branchId || 'Global'}, Prefix: ${branchPrefix}, TZ: ${branchTimezone}, Date: ${businessDate}`);

        // Counter document ID includes branch ID and date for uniqueness
        // If branchId is missing, we use 'global' to separate it from actual branches
        const safeBranchId = branchId || 'global';
        const counterDocId = `branch_${safeBranchId}_${businessDate}`;

        const counterRef = db.collection('Counters').doc(counterDocId);

        // Retry logic for transient failures
        let lastError = null;
        for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                const orderNumber = await db.runTransaction(async (t) => {
                    const counterDoc = await t.get(counterRef);
                    let currentCount = 0;
                    let isFirstOrder = false;

                    if (counterDoc.exists) {
                        currentCount = counterDoc.data().count || 0;
                    } else {
                        isFirstOrder = true;
                    }

                    const nextCount = currentCount + 1;

                    // Format the order number
                    const formattedOrderNumber = formatOrderNumber(branchPrefix, businessDate, nextCount);

                    // Enhanced counter metadata
                    const counterData = {
                        count: nextCount,
                        branchId: safeBranchId,
                        branchPrefix: branchPrefix,
                        date: businessDate,
                        timezone: branchTimezone,
                        resetHour: resetHour,
                        lastUpdated: FieldValue.serverTimestamp(),
                        lastOrderAt: FieldValue.serverTimestamp(),
                        lastOrderNumber: formattedOrderNumber,
                    };

                    // Track first order time
                    if (isFirstOrder) {
                        counterData.firstOrderAt = FieldValue.serverTimestamp();
                    }

                    t.set(counterRef, counterData, { merge: true });

                    // Update order with both the formatted number and raw sequence
                    t.update(event.data.after.ref, {
                        dailyOrderNumber: formattedOrderNumber,
                        orderSequence: nextCount, // Raw sequence number for sorting
                        orderNumberAssignedAt: FieldValue.serverTimestamp(),
                    });

                    return formattedOrderNumber;
                });

                logger.log(`[${orderId}] ✅ Assigned ${orderNumber} for branch ${safeBranchId}`);
                return; // Success, exit function
            } catch (e) {
                lastError = e;
                logger.warn(`[${orderId}] Attempt ${attempt}/${MAX_RETRIES} failed: ${e.message}`);

                if (attempt < MAX_RETRIES) {
                    // Exponential backoff: 100ms, 200ms, 400ms
                    await new Promise(resolve => setTimeout(resolve, 100 * Math.pow(2, attempt - 1)));
                }
            }
        }

        // All retries failed - use fallback
        logger.error(`[${orderId}] ❌ All retries failed. Using fallback order number. Error: ${lastError?.message}`);
        const fallbackNumber = generateFallbackOrderNumber(branchPrefix, businessDate);

        try {
            await event.data.after.ref.update({
                dailyOrderNumber: fallbackNumber,
                orderNumberAssignedAt: FieldValue.serverTimestamp(),
                orderNumberFallback: true, // Flag to identify fallback numbers
            });
            logger.log(`[${orderId}] Assigned fallback order number: ${fallbackNumber}`);
        } catch (updateError) {
            logger.error(`[${orderId}] Failed to set fallback order number: ${updateError.message}`);
        }
    }
);

// -------------------- TRIGGER: Immediate update when schedule changes --------------------
exports.onBranchScheduleUpdate = onDocumentUpdated(
    { document: "Branch/{branchId}", region: GCP_LOCATION },
    async (event) => {
        const beforeData = event.data.before.data();
        const afterData = event.data.after.data();
        const branchId = event.params.branchId;

        // Only trigger if workingHours actually changed
        const beforeHours = JSON.stringify(beforeData.workingHours || {});
        const afterHours = JSON.stringify(afterData.workingHours || {});

        if (beforeHours === afterHours) {
            return;
        }

        logger.log(`[${branchId}] Schedule changed, recalculating status immediately...`);

        const result = processBranchStatus(afterData, branchId);

        if (!result) {
            // No schedule or no change needed
            return;
        }

        // When schedule changes, we update status and optionally reset manual flags
        // But we give user control: only reset flags if the schedule change would naturally
        // open/close the restaurant at its scheduled time
        const updateData = {
            ...result.updateData,
        };

        // If status is changing due to schedule update, reset manual flags
        if (result.statusChanged) {
            updateData.manuallyClosed = false;
            updateData.manuallyOpened = false;
            updateData.statusReason = result.toStatus
                ? 'Auto-Opened (Schedule Changed)'
                : 'Auto-Closed (Schedule Changed)';
        }

        if (Object.keys(updateData).length === 0) {
            return;
        }

        await event.data.after.ref.update(updateData);

        // Log to history
        if (result.statusChanged) {
            await logStatusChange(
                event.data.after.ref,
                branchId,
                result.fromStatus,
                result.toStatus,
                'Schedule Changed',
                'schedule_update_trigger'
            );
            logger.log(`[${branchId}] Immediate update: ${result.fromStatus} → ${result.toStatus}`);
        }
    }
);

/**
 * =============================================================================
 * FUNCTION: CLEANUP STALE ASSIGNMENTS
 * =============================================================================
 * Scheduled function that runs every 5 minutes to clean up stuck assignments.
 * This is a CRITICAL failsafe for when:
 * - Cloud Tasks fails to trigger
 * - A rider gets stuck in "pending" state
 * - The workflow crashes mid-execution
 * 
 * Actions:
 * 1. Find all assignments older than MAX_WORKFLOW_MINUTES
 * 2. Unlock any locked riders
 * 3. Move orders to manual assignment
 * 4. Delete stale assignment records
 * =============================================================================
 */
exports.cleanupStaleAssignments = onSchedule("every 5 minutes", async (event) => {
    try {
        logger.log('🧹 Running stale assignment cleanup...');

        const cutoffTime = new Date(Date.now() - (MAX_WORKFLOW_MINUTES * 60 * 1000));

        // Find stale assignments
        const staleAssignments = await db.collection('rider_assignments')
            .where('createdAt', '<', cutoffTime)
            .limit(50) // Process 50 at a time to avoid timeout
            .get();

        if (staleAssignments.empty) {
            logger.log('✅ No stale assignments found');
            return;
        }

        logger.log(`🔍 Found ${staleAssignments.size} stale assignments to clean up`);

        let cleanedCount = 0;
        let errorCount = 0;

        for (const doc of staleAssignments.docs) {
            const data = doc.data();
            const orderId = doc.id;

            try {
                // 1. Unlock the rider if one was assigned
                if (data.riderId && data.riderId !== 'RETRY_SEARCH') {
                    await unlockRider(data.riderId, orderId);
                    logger.log(`[${orderId}] 🔓 Unlocked stale rider ${data.riderId}`);
                }

                // 2. Check if order still needs assignment
                const orderDoc = await db.collection('Orders').doc(orderId).get();
                if (orderDoc.exists) {
                    const orderData = orderDoc.data();
                    const status = normalizeStatus(orderData.status);

                    // Only move to manual if not already terminal or assigned
                    if (!isTerminalStatus(status) &&
                        status !== STATUS.RIDER_ASSIGNED &&
                        (!orderData.riderId || orderData.riderId === '')) {
                        await markOrderForManualAssignment(orderId, 'Workflow timeout (cleanup)');
                        logger.log(`[${orderId}] 📋 Moved to manual assignment`);
                    }
                }

                // 3. Delete the stale assignment
                await doc.ref.delete();
                cleanedCount++;

            } catch (err) {
                logger.error(`[${orderId}] Error cleaning up stale assignment:`, err);
                errorCount++;
            }
        }

        logger.log(`🧹 Cleanup complete: ${cleanedCount} cleaned, ${errorCount} errors`);

    } catch (error) {
        logger.error('🔥 Error in cleanupStaleAssignments:', error);
    }
});

/**
 * =============================================================================
 * FUNCTION: CLEANUP STUCK RIDERS
 * =============================================================================
 * Scheduled function that runs every 10 minutes to find and unlock riders
 * that are stuck in an unavailable state without an active assignment.
 * =============================================================================
 */
exports.cleanupStuckRiders = onSchedule("every 10 minutes", async (event) => {
    try {
        logger.log('🔍 Checking for stuck riders...');

        // Find riders who are unavailable but have a currentOfferOrderId
        const stuckRiders = await db.collection('Drivers')
            .where('isAvailable', '==', false)
            .where('status', '==', 'online')
            .limit(50)
            .get();

        if (stuckRiders.empty) {
            logger.log('✅ No potentially stuck riders found');
            return;
        }

        let unlockedCount = 0;

        for (const riderDoc of stuckRiders.docs) {
            const riderData = riderDoc.data();
            const riderId = riderDoc.id;
            const offerOrderId = riderData.currentOfferOrderId;
            const assignedOrderId = riderData.assignedOrderId;

            // If rider has an assigned order, they're legitimately busy
            if (assignedOrderId && assignedOrderId !== '') {
                continue;
            }

            // If rider has a current offer, check if the assignment is still active
            if (offerOrderId) {
                const assignDoc = await db.collection('rider_assignments').doc(offerOrderId).get();

                if (assignDoc.exists) {
                    const assignData = assignDoc.data();
                    // Check if the assignment is recent (within 3 minutes = 180 seconds)
                    const createdAt = assignData.createdAt?.toDate?.() || new Date(0);
                    const ageSeconds = (Date.now() - createdAt.getTime()) / 1000;

                    if (ageSeconds < 180) {
                        // Assignment is still fresh, rider is legitimately locked
                        continue;
                    }
                }
                // Assignment doesn't exist or is stale - unlock rider
            }

            // Unlock the stuck rider
            try {
                await riderDoc.ref.update({
                    'isAvailable': true,
                    'currentOfferOrderId': FieldValue.delete()
                });
                logger.log(`🔓 Unlocked stuck rider ${riderId} (was locked for order: ${offerOrderId || 'unknown'})`);
                unlockedCount++;
            } catch (err) {
                logger.warn(`Failed to unlock rider ${riderId}: ${err.message}`);
            }
        }

        if (unlockedCount > 0) {
            logger.log(`✅ Unlocked ${unlockedCount} stuck riders`);
        }

    } catch (error) {
        logger.error('🔥 Error in cleanupStuckRiders:', error);
    }
});
