const { onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, GeoPoint } = require("firebase-admin/firestore");
const { CloudTasksClient } = require("@google-cloud/tasks");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// --- CONFIGURATION ---
const GCP_PROJECT_ID = 'mddprod-2954f';
const GCP_LOCATION = 'us-central1';
const QUEUE_NAME = 'assignment-timeout-queue';
const ASSIGNMENT_TIMEOUT_SECONDS = 120;
const TASK_HANDLER_URL = `https://${GCP_LOCATION}-${GCP_PROJECT_ID}.cloudfunctions.net/processAssignmentTask`;

/**
 * FUNCTION 1: Initiator
 * Triggered when an order status changes to 'preparing' or 'prepared'.
 * Starts the auto-assignment search if no rider is assigned.
 */
exports.startAssignmentWorkflowV2 = onDocumentUpdated(
    { document: "Orders/{orderId}", region: GCP_LOCATION },
    async (event) => {
        const beforeData = event.data.before.data();
        const afterData = event.data.after.data();
        const orderId = event.params.orderId;

        const validStatuses = ['preparing', 'prepared'];
        const statusJustEntered = !validStatuses.includes(beforeData.status) && validStatuses.includes(afterData.status);
        const noRider = !afterData.riderId || afterData.riderId === '';
        const notAlreadyStarted = !afterData.autoAssignStarted;

        if (statusJustEntered && noRider && notAlreadyStarted) {
            logger.log(`🚀 [${orderId}] Starting auto-assignment workflow...`);

            const targetBranchId = afterData.branchId || (afterData.branchIds && afterData.branchIds[0]);
            if (!targetBranchId) {
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

            // Schedule the timeout task
            await createAssignmentTask(orderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);
        }
    }
);

/**
 * FUNCTION 2: Retry Loop (Cloud Task Handler)
 * Triggered when a rider fails to accept within the timeout period.
 */
exports.processAssignmentTask = onRequest({ region: GCP_LOCATION }, async (req, res) => {
    const { orderId, expectedRiderId } = req.body;
    if (!orderId || !expectedRiderId) return res.status(400).send("Bad Request");

    const orderRef = db.collection('Orders').doc(orderId);
    const assignRef = db.collection('rider_assignments').doc(orderId);

    try {
        const [orderDoc, assignDoc] = await Promise.all([orderRef.get(), assignRef.get()]);

        // EDGE CASE: If order was cancelled, picked up, or manually overridden, stop searching
        if (!orderDoc.exists || ['cancelled', 'pickedup', 'delivered'].includes(orderDoc.data().status)) {
            if (assignDoc.exists) await assignRef.delete();
            return res.status(200).send("Order Terminal or Finished");
        }

        // EDGE CASE: If rider already accepted or assignment moved to another rider, ignore stale task
        if (!assignDoc.exists || assignDoc.data().riderId !== expectedRiderId || assignDoc.data().status === 'accepted') {
            return res.status(200).send("Stale Task - Ignoring");
        }

        logger.log(`[${orderId}] Rider ${expectedRiderId} timed out. Finding next available...`);
        const assignData = assignDoc.data();
        const nextRider = await findNextRider(assignData, orderId, assignData.branchId);

        if (!nextRider) {
            await markOrderForManualAssignment(orderId, 'All available riders failed to accept');
            await assignRef.delete();
            return res.status(200).send("Riders Exhausted");
        }

        await assignRef.update({
            riderId: nextRider.riderId,
            status: 'pending',
            triedRiders: [...assignData.triedRiders, nextRider.riderId],
            createdAt: FieldValue.serverTimestamp()
        });

        await createAssignmentTask(orderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);
        res.status(200).send("Retrying with next rider");
    } catch (err) {
        logger.error(`Error in processAssignmentTask: ${err}`);
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

            await db.runTransaction(async (transaction) => {
                const orderRef = db.collection('Orders').doc(orderId);
                const orderDoc = await transaction.get(orderRef);

                if (!orderDoc.exists) throw "Order Missing";
                const orderStatus = orderDoc.data().status;

                // EDGE CASE: Prevent acceptance if order was manually assigned or cancelled during acceptance
                if (orderDoc.data().riderId && orderDoc.data().riderId !== riderId) throw "Already Assigned to another rider";
                if (orderStatus === 'cancelled') throw "Order was cancelled";

                /**
                 * ROBUSTNESS FIX (COMPLETE):
                 * The kitchen workflow is: pending -> preparing -> prepared -> rider_assigned -> pickedUp -> delivered
                 * 
                 * When a rider accepts:
                 * - If kitchen is still 'preparing' -> Keep status as 'preparing', just attach riderId
                 * - If kitchen has marked as 'prepared' -> Advance to 'rider_assigned'
                 * - If already 'rider_assigned' or later -> Don't change status (prevent regression)
                 */
                let finalStatus;
                const nonRegressStatuses = ['rider_assigned', 'pickedup', 'pickedUp', 'delivered'];

                if (orderStatus === 'preparing') {
                    // Kitchen is still working - don't advance status, just attach rider
                    finalStatus = 'preparing';
                    logger.log(`[${orderId}] Rider assigned while preparing - keeping status as 'preparing'`);
                } else if (orderStatus === 'prepared') {
                    // Food is ready - now we can advance to rider_assigned
                    finalStatus = 'rider_assigned';
                    logger.log(`[${orderId}] Food prepared - advancing to 'rider_assigned'`);
                } else if (nonRegressStatuses.includes(orderStatus)) {
                    // Already at or past rider_assigned - don't change (prevent regression)
                    finalStatus = orderStatus;
                    logger.log(`[${orderId}] Status already at '${orderStatus}' - not changing`);
                } else {
                    // Fallback for any other status (e.g., pending) - set to preparing at minimum
                    finalStatus = 'preparing';
                    logger.log(`[${orderId}] Unexpected status '${orderStatus}' - setting to 'preparing'`);
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

            return event.data.after.ref.delete();
        }
        return null;
    }
);

// --- HELPERS ---

async function markOrderForManualAssignment(orderId, reason) {
    logger.warn(`[${orderId}] Moving to manual assignment. Reason: ${reason}`);
    return db.collection('Orders').doc(orderId).update({
        'status': 'needs_rider_assignment',
        'assignmentNotes': reason,
        'autoAssignStarted': FieldValue.delete(),
    });
}

async function findNextRider(assignmentData, orderId, branchId) {
    const triedRiders = assignmentData ? assignmentData.triedRiders : [];

    const branchDoc = await db.collection('Branch').doc(branchId).get();
    const branchLoc = branchDoc.exists ? branchDoc.data().location : new GeoPoint(25.2, 51.5);

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

    if (riders.length === 0) return null;
    riders.sort((a, b) => a.distance - b.distance);
    return riders[0];
}

async function createAssignmentTask(orderId, riderId, delayInSeconds) {
    const client = new CloudTasksClient();
    const queuePath = client.queuePath(GCP_PROJECT_ID, GCP_LOCATION, QUEUE_NAME);
    const task = {
        httpRequest: {
            httpMethod: 'POST',
            url: TASK_HANDLER_URL,
            headers: { 'Content-Type': 'application/json' },
            body: Buffer.from(JSON.stringify({ orderId, expectedRiderId: riderId })).toString('base64'),
        },
        scheduleTime: { seconds: (Date.now() / 1000) + delayInSeconds },
    };
    await client.createTask({ parent: queuePath, task });
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
 */
const VALID_TRANSITIONS = {
    'pending': ['preparing', 'cancelled'],
    'preparing': ['prepared', 'cancelled'],
    'prepared': ['rider_assigned', 'needs_rider_assignment', 'cancelled'],
    'needs_rider_assignment': ['rider_assigned', 'cancelled'],
    'rider_assigned': ['pickedup', 'pickedUp', 'cancelled'],
    'pickedup': ['delivered', 'cancelled'],
    'pickedUp': ['delivered', 'cancelled'],
    'delivered': [],  // Terminal state
    'cancelled': [],  // Terminal state
};

/**
 * FUNCTION 4: Status Transition Validator (Failsafe)
 * Triggered on ANY order update. Validates status transitions and reverts invalid ones.
 * This is a defense-in-depth measure in case Security Rules are bypassed.
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

        // Skip validation for Cloud Function-initiated changes (marked by internal flag)
        if (afterData._cloudFunctionUpdate) {
            // Clear the flag
            await event.data.after.ref.update({ '_cloudFunctionUpdate': FieldValue.delete() });
            return null;
        }

        // Check if the transition is valid
        const allowedNextStatuses = VALID_TRANSITIONS[oldStatus] || [];

        if (!allowedNextStatuses.includes(newStatus)) {
            // INVALID TRANSITION DETECTED!
            logger.warn(`⚠️ [${orderId}] Invalid status transition: ${oldStatus} → ${newStatus}. Reverting...`);

            // Determine the correct status based on the invalid attempt
            let correctedStatus = oldStatus; // Default: revert to previous

            // Special case: If someone tried to jump to rider_assigned but food isn't ready
            if (newStatus === 'rider_assigned' && ['pending', 'preparing'].includes(oldStatus)) {
                // If a rider is attached, keep status at current kitchen state
                if (afterData.riderId) {
                    correctedStatus = oldStatus === 'pending' ? 'preparing' : 'preparing';
                    logger.log(`[${orderId}] Rider attached but kitchen not ready. Setting to '${correctedStatus}'`);
                } else {
                    correctedStatus = oldStatus;
                }
            }

            // Revert to valid status
            await event.data.after.ref.update({
                'status': correctedStatus,
                '_cloudFunctionUpdate': true, // Flag to prevent infinite loop
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

