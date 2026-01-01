// Add this to imports in functions/index.js
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { DateTime } = require("luxon"); // Recommended for robust timezone handling

/**
 * ROBUSTNESS FIX: Server-side Cron Job
 * Checks restaurant schedules every minute and updates Firestore.
 * This ensures the restaurant closes even if the Admin App is dead.
 */
exports.autoManageRestaurantStatus = onSchedule("every 1 minutes", async (event) => {
    const branchesSnapshot = await db.collection('Branch').get();
    const batch = db.batch();
    let updatesCount = 0;

    branchesSnapshot.forEach(doc => {
        const data = doc.data();
        const timezone = data.timezone || 'UTC';
        const workingHours = data.workingHours;
        const currentIsOpen = data.isOpen || false;

        // If no schedule exists, skip
        if (!workingHours) return;

        // 1. Get Current Time in Branch's Timezone
        const now = DateTime.now().setZone(timezone);
        const currentDayName = now.weekdayLong.toLowerCase(); // 'monday', 'tuesday'...

        // 2. Check if Open
        const daySchedule = workingHours[currentDayName];
        let shouldBeOpen = false;

        if (daySchedule && daySchedule.isOpen && daySchedule.slots) {
            for (const slot of daySchedule.slots) {
                const openTime = DateTime.fromFormat(slot.open, "HH:mm", { zone: timezone });
                const closeTime = DateTime.fromFormat(slot.close, "HH:mm", { zone: timezone });

                // Handle overnight slots (e.g., 22:00 to 02:00)
                let adjustedCloseTime = closeTime;
                if (closeTime < openTime) {
                    adjustedCloseTime = closeTime.plus({ days: 1 });
                }

                // Check interval
                if (now >= openTime && now < adjustedCloseTime) {
                    shouldBeOpen = true;
                    break;
                }
            }
        }

        // 3. Only update DB if status has CHANGED
        if (currentIsOpen !== shouldBeOpen) {
            batch.update(doc.ref, {
                'isOpen': shouldBeOpen,
                'lastStatusUpdate': FieldValue.serverTimestamp(),
                'statusReason': shouldBeOpen ? 'Auto-Opened by Scheduler' : 'Auto-Closed by Scheduler'
            });
            updatesCount++;
        }
    });

    if (updatesCount > 0) {
        await batch.commit();
        logger.log(`🔄 Updated status for ${updatesCount} branches.`);
    }
});