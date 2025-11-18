// This file does NOT go in your Flutter app.
// You must deploy it to Firebase using the Firebase CLI.

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
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
// I have pre-filled ALL your information.
const GCP_PROJECT_ID = 'mddprod-2954f';
const GCP_LOCATION = 'us-central1';
const QUEUE_NAME = 'assignment-timeout-queue';
const ASSIGNMENT_TIMEOUT_SECONDS = 120;

// This is the URL you just got. It is now correct.
const TASK_HANDLER_URL = 'https://us-central1-mddprod-2954f.cloudfunctions.net/processAssignmentTask';
// --------------------- ( END: !! CONFIGURATION !! ) -----------------------


/**
 * FUNCTION 1: The Initiator
 * Triggers when an order is ready. Finds the *first* rider.
 *
 * We set minInstances to 1 to keep it "warm" and send the
 * first FCM notification *instantly*, solving your "slowness" concern.
 */
exports.startAssignmentWorkflow = onDocumentUpdated(
  {
    document: "Orders/{orderId}",
    // Set minInstances to 1 to eliminate cold starts
    minInstances: 1,
    // Set the region to match your config
    region: GCP_LOCATION,
  },
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const orderId = event.params.orderId;

    const validStatuses = ['preparing', 'prepared'];
    const statusChanged = !validStatuses.includes(beforeData.status) && validStatuses.includes(afterData.status);
    const noRider = !afterData.riderId || afterData.riderId === '';

    // Only trigger if the status *just changed* to a valid one and there's no rider
    if (statusChanged && noRider) {
      logger.log(`🚀 [${orderId}] STARTING WORKFLOW...`);

      // Mark the order so this doesn't run again
      await event.data.after.ref.update({
        'autoAssignStarted': FieldValue.serverTimestamp()
      });

      // This is a "state" document for the workflow
      const assignmentRef = db.collection('rider_assignments').doc(orderId);

      // We pass 'null' for assignmentData to find the *first* rider
      const nextRider = await findNextRider(null, orderId, afterData.branchId);

      if (!nextRider) {
        logger.warn(`[${orderId}] No riders available at start.`);
        return markOrderForManualAssignment(orderId, 'No available riders found');
      }

      // 1. Create the state document
      const assignmentData = {
        orderId: orderId,
        branchId: afterData.branchId,
        riderId: nextRider.riderId,
        status: 'pending',
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + ASSIGNMENT_TIMEOUT_SECONDS * 1000),
        triedRiders: [nextRider.riderId],
        notificationSent: false,
      };
      await assignmentRef.set(assignmentData);

      // 2. Send the *first* FCM (instantly, since this function is warm)
      await sendAssignmentFCM(nextRider.riderId, orderId, afterData, assignmentData);

      // 3. Create the *first* 120-second timeout task
      await createAssignmentTask(orderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);

      logger.log(`[${orderId}] Workflow started. Rider ${nextRider.riderId} notified.`);
      return null;
    }
    return null;
  }
);

/**
 * FUNCTION 2: The Retry Loop (HTTP Function)
 * This is our reliable 120-second timer. It's called by Cloud Tasks.
 * It checks the assignment and finds the *next* rider if needed.
 */
exports.processAssignmentTask = onRequest(
  {
    // Set the region to match your config
    region: GCP_LOCATION,
  },
  async (req, res) => {
    const { orderId, expectedRiderId } = req.body;

    if (!orderId || !expectedRiderId) {
      logger.error("Missing orderId or expectedRiderId in task body");
      return res.status(400).send("Invalid request");
    }

    logger.log(`⏰ [${orderId}] PROCESSING TIMEOUT for rider ${expectedRiderId}`);

    // Get the current state of the assignment
    const assignmentRef = db.collection('rider_assignments').doc(orderId);
    const assignmentDoc = await assignmentRef.get();

    if (!assignmentDoc.exists) {
      logger.log(`[${orderId}] Assignment already completed/deleted. Task is stale.`);
      return res.status(200).send("OK (Stale)");
    }

    const assignmentData = assignmentDoc.data();

    // Check if the assignment is still for the rider we expected
    if (assignmentData.riderId !== expectedRiderId) {
      logger.log(`[${orderId}] Rider has changed. Task is stale.`);
      return res.status(200).send("OK (Stale)");
    }

    // If status is 'pending', the rider timed out.
    // If status is 'rejected', the rider actively rejected.
    if (assignmentData.status === 'pending' || assignmentData.status === 'rejected') {
      logger.log(`[${orderId}] Rider ${expectedRiderId} failed. Finding next rider...`);

      const nextRider = await findNextRider(assignmentData, orderId, assignmentData.branchId);

      if (!nextRider) {
        logger.warn(`[${orderId}] All riders exhausted.`);
        await markOrderForManualAssignment(orderId, 'All available riders failed to accept');
        await assignmentRef.delete(); // Clean up
        return res.status(200).send("OK (Exhausted)");
      }

      // 1. Update the state document for the *next* rider
      const nextAssignmentData = {
        ...assignmentData, // keep old data like triedRiders
        riderId: nextRider.riderId,
        status: 'pending',
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + ASSIGNMENT_TIMEOUT_SECONDS * 1000),
        triedRiders: [...assignmentData.triedRiders, nextRider.riderId],
        notificationSent: false,
      };
      await assignmentRef.update(nextAssignmentData);

      // 2. Send FCM to the *next* rider
      const orderDoc = await db.collection('Orders').doc(orderId).get();
      await sendAssignmentFCM(nextRider.riderId, orderId, orderDoc.data(), nextAssignmentData);

      // 3. Create a *new* 120-second task for the next rider
      await createAssignmentTask(orderId, nextRider.riderId, ASSIGNMENT_TIMEOUT_SECONDS);

      logger.log(`[${orderId}] Retry loop: Rider ${nextRider.riderId} notified.`);
      return res.status(200).send("OK (Retrying)");

    } else if (assignmentData.status === 'accepted') {
      logger.log(`[${orderId}] Rider accepted. Task is complete.`);
      // Function 3 will handle the cleanup.
      return res.status(200).send("OK (Accepted)");
    }

    return res.status(200).send("OK (No action)");
  }
);

/**
 * FUNCTION 3: The Finisher
 * Triggers when a rider's app updates status to 'accepted'.
 * This completes the assignment.
 */
exports.handleRiderAcceptance = onDocumentUpdated(
  {
    document: "rider_assignments/{orderId}",
    // Set the region to match your config
    region: GCP_LOCATION,
  },
  async (event) => {
    const afterData = event.data.after.data();
    const beforeData = event.data.before.data();

    // Only trigger if status *changed* to 'accepted'
    if (beforeData.status !== 'accepted' && afterData.status === 'accepted') {
      logger.log(`✅ [${afterData.orderId}] Rider ${afterData.riderId} ACCEPTED.`);

      // This is your _completeAssignment logic
      const batch = db.batch();
      const orderRef = db.collection('Orders').doc(afterData.orderId);
      batch.update(orderRef, {
        'riderId': afterData.riderId,
        'status': 'rider_assigned',
        'timestamps.riderAssigned': FieldValue.serverTimestamp(),
        'autoAssignStarted': FieldValue.delete(),
      });

      const riderRef = db.collection('Drivers').doc(afterData.riderId);
      batch.update(riderRef, {
        'assignedOrderId': afterData.orderId,
        'isAvailable': false,
      });

      await batch.commit();

      // Clean up the assignment document.
      // This also helps any pending tasks for this order to self-terminate.
      return event.data.after.ref.delete();
    }
    return null;
  }
);

// --- HELPER FUNCTIONS ---

/**
 * Creates a new task in the Cloud Tasks queue.
 */
async function createAssignmentTask(orderId, riderId, delayInSeconds) {
  const client = new CloudTasksClient();
  const project = GCP_PROJECT_ID;
  const location = GCP_LOCATION;
  const queue = QUEUE_NAME;

  const queuePath = client.queuePath(project, location, queue);

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
    logger.log(`[${orderId}] Task created for ${riderId}, due in ${delayInSeconds}s.`);
  } catch (error) {
    // Check if the error is because the URL isn't set yet
    if (error.message.includes("Invalid resource name") || error.message.includes("NOT_FOUND")) {
        logger.error(`[${orderId}] CRITICAL ERROR: Failed to create task. Is the 'TASK_HANDLER_URL' variable set correctly in your index.js?`);
        logger.error(`Current URL: ${TASK_HANDLER_URL}`);
    } else {
        logger.error(`[${orderId}] Failed to create task:`, error);
    }
  }
}

/**
 * Sends the FCM notification to the rider.
 */
async function sendAssignmentFCM(riderId, orderId, orderData, assignmentData) {
  try {
    const driverDoc = await db.collection('Drivers').doc(riderId).get();
    const fcmToken = driverDoc.data().fcmToken;

    if (!fcmToken) {
      logger.error(`[${orderId}] No FCM token for rider ${riderId}`);
      // Mark as notificationSent: true to avoid retries on this rider
      await db.collection('rider_assignments').doc(orderId).update({ notificationSent: true });
      return;
    }

    const payload = {
      notification: {
        title: '📦 New Order Available',
        body: `New ${orderData.Order_type || 'Delivery'} Order - QAR ${orderData.totalAmount || 0}`
      },
      data: {
        type: 'auto_assignment',
        orderId: orderId,
        orderNumber: orderData.dailyOrderNumber?.toString() || '',
        timeoutSeconds: ASSIGNMENT_TIMEOUT_SECONDS.toString(),
      }
    };

    await getMessaging().sendToDevice(fcmToken, payload);
    await db.collection('rider_assignments').doc(orderId).update({ notificationSent: true });
    logger.log(`[${orderId}] FCM sent to rider ${riderId}`);
  } catch (e) {
    logger.error(`[${orderId}] Failed to send FCM: ${e}`);
  }
}

/**
 * Finds the next available rider who hasn't been tried.
 * This is your _findNearestRiders and _getRestaurantLocation logic.
 */
async function findNextRider(assignmentData, orderId, branchId) {
  const triedRiders = assignmentData ? assignmentData.triedRiders : [];

  // 1. Get Restaurant Location
  let restaurantLocation;
  try {
    const branchDoc = await db.collection('Branch').doc(branchId).get();
    const data = branchDoc.data();
    if (data && data.location) {
        restaurantLocation = data.location; // GeoPoint
    } else {
        throw new Error("No location field in branch doc");
    }
  } catch (e) {
    logger.warn(`[${orderId}] Warning: ${e.message}. Using default location for branch ${branchId}.`);
    restaurantLocation = new GeoPoint(25.2614, 51.5651); // Default
  }

  // 2. Find Nearest Riders
  const driversSnapshot = await db.collection('Drivers')
    .where('isAvailable', '==', true)
    .where('status', '==', 'online')
    .where('branchIds', 'array-contains', branchId)
    .get();

  const ridersWithDistance = [];
  driversSnapshot.forEach(doc => {
    if (triedRiders.includes(doc.id)) return; // Skip already-tried riders

    const data = doc.data();
    const riderLocation = data.currentLocation;
    if (riderLocation) {
      const distance = _calculateDistance(
        restaurantLocation.latitude, restaurantLocation.longitude,
        riderLocation.latitude, riderLocation.longitude
      );
      ridersWithDistance.push({ riderId: doc.id, distance: distance });
    }
  });

  if (ridersWithDistance.length === 0) return null;

  ridersWithDistance.sort((a, b) => a.distance - b.distance);
  return ridersWithDistance[0];
}

/**
 * Marks the order as needing manual help.
 */
async function markOrderForManualAssignment(orderId, reason) {
  return db.collection('Orders').doc(orderId).update({
    'status': 'needs_rider_assignment',
    'assignmentNotes': reason,
    'autoAssignStarted': FieldValue.delete(),
  });
}

/**
 * Haversine formula from your Dart code, in JS
 */
function _calculateDistance(lat1, lon1, lat2, lon2) {
    const earthRadius = 6371;
    const _toRadians = (degree) => degree * Math.PI / 180;
    const dLat = _toRadians(lat2 - lat1);
    const dLon = _toRadians(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(_toRadians(lat1)) * Math.cos(_toRadians(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadius * c;
}

// This is your old function from functions/index.js.
// It is good to keep, as it notifies admins of new orders.
// It does not conflict with the new logic.
exports.sendNotificationOnNewOrder = onDocumentCreated("Orders/{orderId}", async (event) => {
  try {
    const snap = event.data;
    if (!snap) {
      logger.log("No data associated with the event, exiting.");
      return;
    }
    const orderData = snap.data();
    const orderId = event.params.orderId;
    if (orderData.status !== "pending") {
      logger.log(`Order ${orderId} is not 'pending', skipping notification.`);
      return;
    }
    const branchIds = orderData.branchIds;
    if (!branchIds || branchIds.length === 0) {
      logger.log(`Order ${orderId} has no branch IDs, skipping.`);
      return;
    }
    const staffQuery = await db
      .collection("staff")
      .where("role", "==", "branch_admin")
      .where("isActive", "==", true)
      .where("branchIds", "array-contains-any", branchIds)
      .get();
    if (staffQuery.empty) {
      logger.log("No active branch admin staff found for these branches.");
      return;
    }
    const tokens = new Set();
    staffQuery.docs.forEach((doc) => {
      const staffData = doc.data();
      if (staffData.fcmToken) {
        tokens.add(staffData.fcmToken);
      }
    });
    if (tokens.size === 0) {
      logger.log("No staff have valid FCM tokens.");
      return;
    }
    const tokensList = Array.from(tokens);
    const orderNumber = orderData.dailyOrderNumber || orderId.substring(0, 8).toUpperCase();
    const orderType = orderData.Order_type || 'order';
    const customerName = orderData.customerName || 'Customer';
    const notificationBody = `New ${orderType} order from ${customerName}`;
    const notificationTitle = `New Order #${orderNumber}`;
    const dataPayload = {
      title: notificationTitle,
      body: notificationBody,
      orderId: orderId,
      orderNumber: orderNumber.toString(),
      type: "new_order",
    };
    const multicastMessage = {
      data: dataPayload,
      tokens: tokensList,
      android: { priority: "high" },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { "content-available": 1 } },
      },
    };
    logger.log(`Sending DATA-ONLY notification to ${tokensList.length} tokens for order ${orderId}`);
    await getMessaging().sendEachForMulticast(multicastMessage);
  } catch (error) {
    logger.error("Error in sendNotificationOnNewOrder:", error);
  }
});