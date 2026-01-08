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

        // --- STRICT GUARD: Only Delivery Orders ---
        // Ensure "Order_type" matches exactly what is stored in Firestore
        // Fallback to checking both Case Styles just to be safe
        const rawOrderType = afterData.Order_type || afterData.orderType || '';
        const orderType = rawOrderType.toLowerCase();

        if (orderType !== 'delivery') {
            // Log this ONLY if it would have theoretically triggered (preparing + no rider)
            // to avoid log spam for every single update
            if (afterData.status === STATUS.PREPARING && (!afterData.riderId)) {
                logger.log(`[${orderId}] Skipping auto-assignment for type: '${rawOrderType}' (not delivery)`);
            }
            return null;
        }

        // Simplified: trigger only when status becomes 'preparing'
        const statusJustEntered = beforeData.status !== STATUS.PREPARING && afterData.status === STATUS.PREPARING;
        const noRider = !afterData.riderId || afterData.riderId === '';
        const notAlreadyStarted = !afterData.autoAssignStarted;

        if (statusJustEntered && noRider && notAlreadyStarted) {
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
