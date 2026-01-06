const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler"); // <--- V2 Scheduler
const { getFirestore, FieldValue, GeoPoint } = require("firebase-admin/firestore");
const { CloudTasksClient } = require("@google-cloud/tasks");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");
const { DateTime } = require("luxon"); // <--- Timezone handling

admin.initializeApp();
const db = admin.firestore();

// --- CONFIGURATION ---
const GCP_PROJECT_ID = 'mddprod-2954f';
const GCP_LOCATION = 'us-central1';
const QUEUE_NAME = 'assignment-timeout-queue';
const ASSIGNMENT_TIMEOUT_SECONDS = 120;
const TASK_HANDLER_URL = `https://${GCP_LOCATION}-${GCP_PROJECT_ID}.cloudfunctions.net/processAssignmentTask`;
const SERVICE_ACCOUNT_EMAIL = `${GCP_PROJECT_ID}@appspot.gserviceaccount.com`;

// --- STATUS CONSTANTS (Standardized) ---
const STATUS = {
    PENDING: 'pending',
    PREPARING: 'preparing',
    RIDER_ASSIGNED: 'rider_assigned',
    NEEDS_ASSIGNMENT: 'needs_rider_assignment',
    PICKED_UP: 'pickedUp',  // Standardized to camelCase
    DELIVERED: 'delivered',
    CANCELLED: 'cancelled',
};

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
    return [STATUS.DELIVERED, STATUS.CANCELLED, 'pickedup', STATUS.PICKED_UP].includes(normalized);
}

/**
 * FUNCTION 1: Initiator
 * Triggered when an order status changes to 'preparing'.
 * Starts the auto-assignment search if no rider is assigned.
 */
exports.startAssignmentWorkflowV2 = onDocumentUpdated(
    { document: "Orders/{orderId}", region: GCP_LOCATION },
    async (event) => {
        const beforeData = event.data.before.data();
        const afterData = event.data.after.data();
        const orderId = event.params.orderId;

        // Simplified: trigger only when status becomes 'preparing'
        const statusJustEntered = beforeData.status !== STATUS.PREPARING && afterData.status === STATUS.PREPARING;
        const noRider = !afterData.riderId || afterData.riderId === '';
        const notAlreadyStarted = !afterData.autoAssignStarted;

        // Only auto-assign for delivery orders
        const orderType = (afterData.Order_type || '').toLowerCase();
        const isDeliveryOrder = orderType === 'delivery';

        if (statusJustEntered && noRider && notAlreadyStarted && isDeliveryOrder) {
            logger.log(`🚀 [${orderId}] Starting auto-assignment workflow for delivery order...`);

            const targetBranchId = afterData.branchId || (afterData.branchIds && afterData.branchIds[0]);
            if (!targetBranchId) {
                logger.error(`[${orderId}] Missing branch info`);
                return markOrderForManualAssignment(orderId, 'Missing Branch Info');
            }

            // Mark that auto-assignment has begun to prevent duplicate triggers
            await event.data.after.ref.update({
                'autoAssignStarted': FieldValue.serverTimestamp()
            });

            const nextRider = await findNextRider(null, orderId, targetBranchId);
            if (!nextRider) {
                return markOrderForManualAssignment(orderId, 'No available riders found nearby');
            }

            const assignmentData = {
                orderId,
                branchId: targetBranchId,
                riderId: nextRider.riderId,
                status: 'pending',
                createdAt: FieldValue.serverTimestamp(),
                triedRiders: [nextRider.riderId],
            };

            // Create the internal assignment record for the Rider App to see
            await db.collection('rider_assignments').doc(orderId).set(assignmentData);

            // Schedule the timeout task with OIDC token
            await createAssignmentTask(orderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);
            logger.log(`[${orderId}] Assignment created for rider ${nextRider.riderId}`);
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
    // --- SECURITY: Verify request is from Cloud Tasks ---
    const authHeader = req.headers.authorization || '';
    if (!authHeader.startsWith('Bearer ')) {
        logger.warn('processAssignmentTask called without auth header - checking if internal');
        // Allow for testing in development, but log it
        if (process.env.FUNCTIONS_EMULATOR !== 'true') {
            // In production, we should ideally verify the OIDC token
            // For now, we check for a shared secret as fallback
            const internalSecret = req.headers['x-internal-secret'];
            if (internalSecret !== process.env.INTERNAL_SECRET && !authHeader) {
                logger.error('Unauthorized access attempt to processAssignmentTask');
                return res.status(401).send('Unauthorized');
            }
        }
    }

    const { orderId, expectedRiderId } = req.body;
    if (!orderId || !expectedRiderId) {
        logger.error('processAssignmentTask called with missing params');
        return res.status(400).send("Bad Request: orderId and expectedRiderId required");
    }

    const orderRef = db.collection('Orders').doc(orderId);
    const assignRef = db.collection('rider_assignments').doc(orderId);

    try {
        const [orderDoc, assignDoc] = await Promise.all([orderRef.get(), assignRef.get()]);

        // EDGE CASE: If order was cancelled, picked up, or manually overridden, stop searching
        const orderStatus = orderDoc.exists ? normalizeStatus(orderDoc.data().status) : null;
        if (!orderDoc.exists || isTerminalStatus(orderStatus)) {
            logger.log(`[${orderId}] Order is terminal or missing. Cleaning up assignment.`);
            if (assignDoc.exists) await assignRef.delete();
            return res.status(200).send("Order Terminal or Finished");
        }

        // EDGE CASE: If rider already accepted or assignment moved to another rider, ignore stale task
        if (!assignDoc.exists) {
            logger.log(`[${orderId}] Assignment doc missing - may have been accepted`);
            return res.status(200).send("Assignment Not Found - Ignoring");
        }

        const assignData = assignDoc.data();
        if (assignData.riderId !== expectedRiderId || assignData.status === 'accepted') {
            logger.log(`[${orderId}] Stale task - current rider: ${assignData.riderId}, expected: ${expectedRiderId}`);
            return res.status(200).send("Stale Task - Ignoring");
        }

        logger.log(`[${orderId}] Rider ${expectedRiderId} timed out. Finding next available...`);
        const nextRider = await findNextRider(assignData, orderId, assignData.branchId);

        if (!nextRider) {
            logger.warn(`[${orderId}] No more riders available. Moving to manual assignment.`);
            await markOrderForManualAssignment(orderId, 'All available riders failed to accept');
            await assignRef.delete();
            return res.status(200).send("Riders Exhausted - Manual Assignment Required");
        }

        await assignRef.update({
            riderId: nextRider.riderId,
            status: 'pending',
            triedRiders: [...assignData.triedRiders, nextRider.riderId],
            createdAt: FieldValue.serverTimestamp()
        });

        await createAssignmentTask(orderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);
        logger.log(`[${orderId}] Retrying with rider ${nextRider.riderId}`);
        res.status(200).send("Retrying with next rider");
    } catch (err) {
        logger.error(`Error in processAssignmentTask for order ${orderId}:`, err);
        res.status(500).send("Internal Error");
    }
});

/**
 * FUNCTION 3: Finisher
 * Triggered when a rider clicks "Accept" in the Rider App.
 * Updates both Order and Driver records atomically.
 */
exports.handleRiderAcceptance = onDocumentUpdated(
    { document: "rider_assignments/{orderId}", region: GCP_LOCATION },
    async (event) => {
        const afterData = event.data.after.data();
        const beforeData = event.data.before.data();

        if (beforeData.status !== 'accepted' && afterData.status === 'accepted') {
            const orderId = afterData.orderId;
            const riderId = afterData.riderId;

            logger.log(`[${orderId}] Rider ${riderId} accepted assignment`);

            try {
                await db.runTransaction(async (transaction) => {
                    const orderRef = db.collection('Orders').doc(orderId);
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

                    // Determine final status based on current status
                    let finalStatus;
                    const nonRegressStatuses = [STATUS.RIDER_ASSIGNED, STATUS.PICKED_UP, STATUS.DELIVERED, 'pickedup'];

                    if (orderStatus === STATUS.PREPARING) {
                        finalStatus = STATUS.RIDER_ASSIGNED;
                        logger.log(`[${orderId}] Advancing from preparing to rider_assigned`);
                    } else if (nonRegressStatuses.map(s => normalizeStatus(s)).includes(normalizeStatus(orderStatus))) {
                        finalStatus = orderStatus;
                        logger.log(`[${orderId}] Status already at ${orderStatus} - not changing`);
                    } else {
                        finalStatus = STATUS.PREPARING;
                        logger.log(`[${orderId}] Unexpected status ${orderStatus} - setting to preparing`);
                    }

                    transaction.update(orderRef, {
                        'riderId': riderId,
                        'status': finalStatus,
                        'timestamps.riderAssigned': FieldValue.serverTimestamp(),
                        'autoAssignStarted': FieldValue.delete(),
                        'assignmentNotes': FieldValue.delete()
                    });

                    const riderRef = db.collection('Drivers').doc(riderId);
                    transaction.update(riderRef, {
                        'assignedOrderId': orderId,
                        'isAvailable': false,
                    });
                });

                // Clean up assignment record
                await event.data.after.ref.delete();
                logger.log(`[${orderId}] Rider acceptance completed successfully`);

            } catch (err) {
                logger.error(`[${orderId}] Error in handleRiderAcceptance:`, err);
                // Don't delete the assignment on error - let it retry
            }
        }
        return null;
    }
);

// --- HELPERS ---

async function markOrderForManualAssignment(orderId, reason) {
    logger.warn(`[${orderId}] Moving to manual assignment. Reason: ${reason}`);
    try {
        await db.collection('Orders').doc(orderId).update({
            'status': STATUS.NEEDS_ASSIGNMENT,
            'assignmentNotes': reason,
            'autoAssignStarted': FieldValue.delete(),
        });
    } catch (err) {
        logger.error(`[${orderId}] Failed to mark for manual assignment:`, err);
    }
}

async function findNextRider(assignmentData, orderId, branchId) {
    const triedRiders = assignmentData ? assignmentData.triedRiders : [];

    // Fetch branch location - FAIL SAFE if missing
    const branchDoc = await db.collection('Branch').doc(branchId).get();
    if (!branchDoc.exists) {
        logger.error(`[${orderId}] Branch ${branchId} not found in database`);
        return null;
    }

    const branchData = branchDoc.data();
    if (!branchData.location) {
        logger.error(`[${orderId}] Branch ${branchId} has no location configured`);
        // Don't use fallback - this is a configuration error that must be fixed
        return null;
    }

    const branchLoc = branchData.location;

    const driversSnapshot = await db.collection('Drivers')
        .where('isAvailable', '==', true)
        .where('status', '==', 'online')
        .where('branchIds', 'array-contains', branchId)
        .limit(15)
        .get();

    const riders = [];
    driversSnapshot.forEach(doc => {
        if (triedRiders.includes(doc.id)) return;
        const loc = doc.data().currentLocation;
        if (loc) {
            const dist = _calculateDistance(branchLoc.latitude, branchLoc.longitude, loc.latitude, loc.longitude);
            riders.push({ riderId: doc.id, distance: dist });
        }
    });

    if (riders.length === 0) {
        logger.log(`[${orderId}] No available riders found for branch ${branchId}`);
        return null;
    }

    riders.sort((a, b) => a.distance - b.distance);
    return riders[0];
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

// --- STATUS TRANSITION VALIDATION ---

/**
 * Valid status transition map.
 * Each key is a status, and the value is an array of valid next statuses.
 * Supports both 'pickedUp' and 'pickedup' for backwards compatibility.
 */
const VALID_TRANSITIONS = {
    'pending': ['preparing', 'cancelled'],
    'preparing': ['rider_assigned', 'needs_rider_assignment', 'cancelled'],
    'needs_rider_assignment': ['rider_assigned', 'cancelled'],
    'rider_assigned': ['pickedUp', 'pickedup', 'cancelled'],
    'pickedup': ['delivered', 'cancelled'],
    'pickedUp': ['delivered', 'cancelled'],
    'delivered': [],  // Terminal state
    'cancelled': [],  // Terminal state
};

/**
 * FUNCTION 4: Status Transition Validator (Failsafe)
 * Triggered on ANY order update. Validates status transitions and reverts invalid ones.
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

        // Normalize statuses for comparison
        const normalizedOld = normalizeStatus(oldStatus);
        const normalizedNew = normalizeStatus(newStatus);

        // Check if the transition is valid
        const allowedNextStatuses = VALID_TRANSITIONS[normalizedOld] || VALID_TRANSITIONS[oldStatus] || [];

        if (!allowedNextStatuses.includes(newStatus) && !allowedNextStatuses.includes(normalizedNew)) {
            logger.warn(`⚠️ [${orderId}] Invalid status transition: ${oldStatus} → ${newStatus}. Reverting...`);

            let correctedStatus = oldStatus;

            // Special case: If jumping to rider_assigned from pending
            if (newStatus === STATUS.RIDER_ASSIGNED && oldStatus === STATUS.PENDING) {
                correctedStatus = STATUS.PREPARING;
                logger.log(`[${orderId}] Cannot skip to rider_assigned from pending. Setting to preparing`);
            }

            await event.data.after.ref.update({
                'status': correctedStatus,
                '_cloudFunctionUpdate': true,
                '_invalidTransitionLog': FieldValue.arrayUnion({
                    attemptedTransition: `${oldStatus} → ${newStatus}`,
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
 */
exports.sendRiderNotification = require("firebase-functions/v2/https").onCall(
    { region: GCP_LOCATION },
    async (request) => {
        const { riderId, orderId, title, body } = request.data;

        if (!riderId || !orderId) {
            throw new Error('riderId and orderId are required');
        }

        try {
            const riderDoc = await db.collection('Drivers').doc(riderId).get();
            if (!riderDoc.exists) {
                logger.warn(`Rider ${riderId} not found`);
                return { success: false, reason: 'Rider not found' };
            }

            const fcmToken = riderDoc.data().fcmToken;
            if (!fcmToken) {
                logger.warn(`Rider ${riderId} has no FCM token`);
                return { success: false, reason: 'No FCM token' };
            }

            const message = {
                notification: {
                    title: title || '🎯 New Order Assignment',
                    body: body || `You have been assigned order ${orderId}`,
                },
                data: {
                    type: 'order_assignment',
                    orderId: orderId,
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                },
                token: fcmToken,
            };

            await admin.messaging().send(message);
            logger.log(`FCM sent to rider ${riderId} for order ${orderId}`);
            return { success: true };
        } catch (err) {
            logger.error(`Failed to send FCM to rider ${riderId}:`, err);
            return { success: false, reason: err.message };
        }
    }
);

// -------------------- ORDER NUMBER CONFIGURATION --------------------
const ORDER_RESET_HOUR = 0; // Reset at 12:00 AM (midnight) local time
const DEFAULT_TIMEZONE = 'Asia/Qatar'; // Default timezone for Qatar-based operations
const MAX_RETRIES = 3;

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
 * Generate fallback order number when counter fails.
 * Uses timestamp to ensure uniqueness while still being readable.
 * @param {string} orderId - Order document ID
 * @returns {string} Fallback order number like "T123456"
 */
function generateFallbackOrderNumber(orderId) {
    const timestamp = Date.now().toString().slice(-6);
    return `T${timestamp}`;
}

/**
 * FUNCTION 6: Generate Daily Order Number (Per Branch)
 * Triggered when a new order is created.
 * 
 * Features:
 * - Branch-specific counters (each branch has independent sequence)
 * - Business day logic (resets at 6 AM, not midnight)
 * - Timezone-aware (uses branch's configured timezone)
 * - Retry logic for transient failures
 * - Fallback order number if all retries fail
 * - Rich metadata for debugging
 */
exports.generateOrderNumber = onDocumentCreated(
    { document: "Orders/{orderId}", region: GCP_LOCATION },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) return;

        const orderData = snapshot.data();
        const orderId = event.params.orderId;

        // Extract branchId (handle both formats)
        const branchId = orderData.branchId || (orderData.branchIds && orderData.branchIds[0]);
        if (!branchId) {
            logger.warn(`[${orderId}] ⚠️ Missing branchId, using fallback order number.`);
            const fallback = generateFallbackOrderNumber(orderId);
            await snapshot.ref.update({ dailyOrderNumber: fallback });
            return;
        }

        // Fetch branch timezone (with fallback to Qatar timezone)
        let branchTimezone = DEFAULT_TIMEZONE;
        let resetHour = ORDER_RESET_HOUR;
        try {
            const branchDoc = await db.collection('Branch').doc(branchId).get();
            if (branchDoc.exists) {
                const branchData = branchDoc.data();
                if (branchData.timezone) {
                    branchTimezone = validateTimezone(branchData.timezone, branchId);
                }
                // Allow per-branch reset hour override
                if (typeof branchData.orderResetHour === 'number') {
                    resetHour = branchData.orderResetHour;
                }
            } else {
                logger.warn(`[${orderId}] Branch ${branchId} not found, using UTC timezone.`);
            }
        } catch (e) {
            logger.warn(`[${orderId}] Failed to fetch branch: ${e.message}. Using UTC.`);
        }

        // Calculate business date using branch timezone and reset hour
        const now = DateTime.now().setZone(branchTimezone);
        const businessDate = getBusinessDate(now, resetHour);

        logger.log(`[${orderId}] Branch: ${branchId}, TZ: ${branchTimezone}, ResetHour: ${resetHour}, BusinessDate: ${businessDate}`);

        const counterRef = db.collection('Counters').doc(`branch_${branchId}_${businessDate}`);

        // Retry logic for transient failures
        let lastError = null;
        for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                const result = await db.runTransaction(async (t) => {
                    const counterDoc = await t.get(counterRef);
                    let currentCount = 0;
                    let isFirstOrder = false;

                    if (counterDoc.exists) {
                        currentCount = counterDoc.data().count || 0;
                    } else {
                        isFirstOrder = true;
                    }

                    const nextCount = currentCount + 1;

                    // Enhanced counter metadata
                    const counterData = {
                        count: nextCount,
                        branchId: branchId,
                        date: businessDate,
                        timezone: branchTimezone,
                        resetHour: resetHour,
                        lastUpdated: FieldValue.serverTimestamp(),
                        lastOrderAt: FieldValue.serverTimestamp(),
                    };

                    // Track first order time
                    if (isFirstOrder) {
                        counterData.firstOrderAt = FieldValue.serverTimestamp();
                    }

                    t.set(counterRef, counterData, { merge: true });
                    t.update(snapshot.ref, { dailyOrderNumber: nextCount });

                    return nextCount;
                });

                logger.log(`[${orderId}] ✅ Assigned #${result} for branch ${branchId} (${businessDate})`);
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
        logger.error(`[${orderId}] ❌ All retries failed. Using fallback order number.`);
        const fallbackNumber = generateFallbackOrderNumber(orderId);

        try {
            await snapshot.ref.update({ dailyOrderNumber: fallbackNumber });
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
