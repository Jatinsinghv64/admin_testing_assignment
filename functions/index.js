// This file does NOT go in your Flutter app.
// You must deploy it to Firebase using the Firebase CLI:
// firebase deploy --only functions

const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, GeoPoint } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { initializeApp } = require("firebase-admin/app");
const { logger } = require("firebase-functions");
const { CloudTasksClient } = require("@google-cloud/tasks");

// Initialize Firebase Admin
initializeApp();
const db = getFirestore();

// --------------------- ( START: !! CONFIGURATION !! ) ---------------------
// Update these with your ACTUAL project details if they differ.
const GCP_PROJECT_ID = 'mddprod-2954f';
const GCP_LOCATION = 'us-central1';
const QUEUE_NAME = 'assignment-timeout-queue';
const ASSIGNMENT_TIMEOUT_SECONDS = 120;

// IMPORTANT: Run 'firebase functions:list' to verify this URL after deployment.
const TASK_HANDLER_URL = 'https://us-central1-mddprod-2954f.cloudfunctions.net/processAssignmentTask';
// --------------------- ( END: !! CONFIGURATION !! ) -----------------------


/**
 * FUNCTION 1: The Initiator
 * Triggers when an order is ready. Finds the *first* rider.
 */
exports.startAssignmentWorkflow = onDocumentUpdated(
  {
    document: "Orders/{orderId}",
    minInstances: 1,
    region: GCP_LOCATION,
  },
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const orderId = event.params.orderId;

    const validStatuses = ['preparing', 'prepared'];
    const statusChanged = !validStatuses.includes(beforeData.status) && validStatuses.includes(afterData.status);
    const noRider = !afterData.riderId || afterData.riderId === '';

    if (statusChanged && noRider) {
      logger.log(`🚀 [${orderId}] STARTING WORKFLOW...`);

      // --- FIX 1: Robust Branch ID Logic ---
      let targetBranchId = afterData.branchId;
      if (!targetBranchId && afterData.branchIds && afterData.branchIds.length > 0) {
        targetBranchId = afterData.branchIds[0];
        logger.log(`[${orderId}] 'branchId' field missing. Using first ID from 'branchIds': ${targetBranchId}`);
      }

      if (!targetBranchId) {
        logger.error(`[${orderId}] FAILED: Order has no 'branchId' or 'branchIds'. Cannot find riders.`);
        return markOrderForManualAssignment(orderId, 'Missing Branch Info');
      }
      // -------------------------------------

      // Mark order to prevent re-runs
      await event.data.after.ref.update({
        'autoAssignStarted': FieldValue.serverTimestamp()
      });

      const assignmentRef = db.collection('rider_assignments').doc(orderId);
      const nextRider = await findNextRider(null, orderId, targetBranchId);

      if (!nextRider) {
        logger.warn(`[${orderId}] No riders available at start.`);
        return markOrderForManualAssignment(orderId, 'No available riders found');
      }

      const assignmentData = {
        orderId: orderId,
        branchId: targetBranchId, // Save the resolved ID
        riderId: nextRider.riderId,
        status: 'pending',
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + ASSIGNMENT_TIMEOUT_SECONDS * 1000),
        triedRiders: [nextRider.riderId],
        notificationSent: false,
      };

      await assignmentRef.set(assignmentData);
      await sendAssignmentFCM(nextRider.riderId, orderId, afterData, assignmentData);
      await createAssignmentTask(orderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);

      logger.log(`[${orderId}] Workflow started. Rider ${nextRider.riderId} notified.`);
      return null;
    }
    return null;
  }
);

/**
 * FUNCTION 2: The Retry Loop (HTTP Function)
 */
exports.processAssignmentTask = onRequest(
  {
    region: GCP_LOCATION,
  },
  async (req, res) => {
    const { orderId, expectedRiderId } = req.body;

    if (!orderId || !expectedRiderId) {
      return res.status(400).send("Invalid request");
    }

    const assignmentRef = db.collection('rider_assignments').doc(orderId);
    const assignmentDoc = await assignmentRef.get();

    if (!assignmentDoc.exists) return res.status(200).send("OK (Stale)");

    const assignmentData = assignmentDoc.data();

    if (assignmentData.riderId !== expectedRiderId) return res.status(200).send("OK (Stale)");

    if (assignmentData.status === 'pending' || assignmentData.status === 'rejected') {
      logger.log(`[${orderId}] Rider ${expectedRiderId} failed/timed out. Finding next...`);

      const nextRider = await findNextRider(assignmentData, orderId, assignmentData.branchId);

      if (!nextRider) {
        logger.warn(`[${orderId}] All riders exhausted.`);
        await markOrderForManualAssignment(orderId, 'All available riders failed to accept');
        await assignmentRef.delete();
        return res.status(200).send("OK (Exhausted)");
      }

      const nextAssignmentData = {
        ...assignmentData,
        riderId: nextRider.riderId,
        status: 'pending',
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + ASSIGNMENT_TIMEOUT_SECONDS * 1000),
        triedRiders: [...assignmentData.triedRiders, nextRider.riderId],
        notificationSent: false,
      };

      await assignmentRef.update(nextAssignmentData);

      const orderDoc = await db.collection('Orders').doc(orderId).get();
      await sendAssignmentFCM(nextRider.riderId, orderId, orderDoc.data(), nextAssignmentData);
      await createAssignmentTask(orderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);

      return res.status(200).send("OK (Retrying)");
    }

    return res.status(200).send("OK (No action)");
  }
);

/**
 * FUNCTION 3: The Finisher
 */
exports.handleRiderAcceptance = onDocumentUpdated(
  {
    document: "rider_assignments/{orderId}",
    region: GCP_LOCATION,
  },
  async (event) => {
    const afterData = event.data.after.data();
    const beforeData = event.data.before.data();

    if (beforeData.status !== 'accepted' && afterData.status === 'accepted') {
      logger.log(`✅ [${afterData.orderId}] Rider ${afterData.riderId} ACCEPTED.`);

      const batch = db.batch();
      const orderRef = db.collection('Orders').doc(afterData.orderId);

      batch.update(orderRef, {
        'riderId': afterData.riderId,
        'status': 'rider_assigned',
        'timestamps.riderAssigned': FieldValue.serverTimestamp(),
        'autoAssignStarted': FieldValue.delete(),
        'assignmentNotes': FieldValue.delete(), // Clear any previous error notes
      });

      const riderRef = db.collection('Drivers').doc(afterData.riderId);
      batch.update(riderRef, {
        'assignedOrderId': afterData.orderId,
        'isAvailable': false,
      });

      await batch.commit();
      return event.data.after.ref.delete();
    }
    return null;
  }
);

// --- HELPER FUNCTIONS ---

async function findNextRider(assignmentData, orderId, branchId) {
  const triedRiders = assignmentData ? assignmentData.triedRiders : [];

  // 1. Get Restaurant Location
  let restaurantLocation;
  try {
    const branchDoc = await db.collection('Branch').doc(branchId).get();
    if (branchDoc.exists && branchDoc.data().location) {
        restaurantLocation = branchDoc.data().location;
    } else {
        logger.warn(`[${orderId}] Branch ${branchId} has no location. Using default.`);
        restaurantLocation = new GeoPoint(25.2614, 51.5651);
    }
  } catch (e) {
    logger.error(`[${orderId}] Error fetching branch: ${e.message}`);
    restaurantLocation = new GeoPoint(25.2614, 51.5651);
  }

  // 2. Find Nearest Riders
  // --- FIX 2: Detailed Logging for Debugging ---
  const driversSnapshot = await db.collection('Drivers')
    .where('isAvailable', '==', true)
    .where('status', '==', 'online')
    .where('branchIds', 'array-contains', branchId)
    .get();

  if (driversSnapshot.empty) {
    logger.log(`[${orderId}] Query returned 0 drivers. (Checked: isAvailable=true, status=online, branchIds contains ${branchId})`);
    return null;
  }

  const ridersWithDistance = [];
  driversSnapshot.forEach(doc => {
    if (triedRiders.includes(doc.id)) return;

    const data = doc.data();
    const riderLocation = data.currentLocation;

    // --- FIX 3: Ensure rider location exists before math ---
    if (riderLocation && riderLocation.latitude && riderLocation.longitude) {
      const distance = _calculateDistance(
        restaurantLocation.latitude, restaurantLocation.longitude,
        riderLocation.latitude, riderLocation.longitude
      );
      ridersWithDistance.push({ riderId: doc.id, distance: distance });
    } else {
        logger.warn(`[${orderId}] Rider ${doc.id} is online but has invalid location data.`);
    }
  });

  if (ridersWithDistance.length === 0) return null;

  ridersWithDistance.sort((a, b) => a.distance - b.distance);
  return ridersWithDistance[0];
}

async function createAssignmentTask(orderId, riderId, delayInSeconds) {
  const client = new CloudTasksClient();
  const queuePath = client.queuePath(GCP_PROJECT_ID, GCP_LOCATION, QUEUE_NAME);
  const payload = { orderId, expectedRiderId: riderId };

  const task = {
    httpRequest: {
      httpMethod: 'POST',
      url: TASK_HANDLER_URL,
      headers: { 'Content-Type': 'application/json' },
      body: Buffer.from(JSON.stringify(payload)).toString('base64'),
    },
    scheduleTime: {
      seconds: Date.now() / 1000 + delayInSeconds,
    },
  };

  try {
    await client.createTask({ parent: queuePath, task: task });
  } catch (error) {
    logger.error(`[${orderId}] Failed to create Cloud Task: ${error.message}`);
  }
}

async function sendAssignmentFCM(riderId, orderId, orderData, assignmentData) {
  try {
    const driverDoc = await db.collection('Drivers').doc(riderId).get();
    const fcmToken = driverDoc.data().fcmToken;

    if (!fcmToken) {
      logger.error(`[${orderId}] Rider ${riderId} has no FCM token.`);
      await db.collection('rider_assignments').doc(orderId).update({ notificationSent: true });
      return;
    }

    const payload = {
      notification: {
        title: '📦 New Order Available',
        body: `New ${orderData.Order_type || 'Delivery'} Order`
      },
      data: {
        type: 'auto_assignment',
        orderId: orderId,
        timeoutSeconds: ASSIGNMENT_TIMEOUT_SECONDS.toString(),
      }
    };

    await getMessaging().sendToDevice(fcmToken, payload);
    await db.collection('rider_assignments').doc(orderId).update({ notificationSent: true });
  } catch (e) {
    logger.error(`[${orderId}] Failed to send FCM: ${e}`);
  }
}

async function markOrderForManualAssignment(orderId, reason) {
  logger.log(`[${orderId}] Marking for manual assignment: ${reason}`);
  return db.collection('Orders').doc(orderId).update({
    'status': 'needs_rider_assignment',
    'assignmentNotes': reason,
    'autoAssignStarted': FieldValue.delete(),
  });
}

function _calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
}

// Keeping your original notification function as is
exports.sendNotificationOnNewOrder = onDocumentCreated("Orders/{orderId}", async (event) => {
    // ... (Code remains same as your original file for this function)
});