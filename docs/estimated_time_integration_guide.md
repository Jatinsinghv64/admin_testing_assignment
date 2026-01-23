# Estimated Time Integration Guide - User App (Zayka)

================================================================================
                              OVERVIEW
================================================================================

The Zayka Admin app allows restaurant owners to adjust their "Estimated Time" 
for order preparation. This value is stored in Firestore and should be read 
by the User app to show customers accurate delivery/pickup time estimates.

This document explains:
1. What data is stored in Firestore
2. How to read this data in the User app
3. How to calculate and display delivery time
4. Best practices and edge cases


================================================================================
                         FIRESTORE DATA STRUCTURE
================================================================================

COLLECTION: Branch
DOCUMENT ID: The unique branch ID (e.g., "branch_123")

FIELDS:
┌─────────────────────────┬──────────────┬─────────┬──────────────────────────┐
│ Field Name              │ Type         │ Default │ Description              │
├─────────────────────────┼──────────────┼─────────┼──────────────────────────┤
│ estimatedTime           │ Integer      │ 20      │ Prep time in minutes     │
│                         │              │         │ Range: 10 to 90 minutes  │
├─────────────────────────┼──────────────┼─────────┼──────────────────────────┤
│ estimatedTimeUpdatedAt  │ Timestamp    │ null    │ When admin last changed  │
│                         │              │         │ this value               │
└─────────────────────────┴──────────────┴─────────┴──────────────────────────┘

IMPORTANT NOTES:
- The "estimatedTime" field may not exist in old branches (treat as 20)
- Value is always between 10 and 90 minutes
- Admins can change this anytime (e.g., busy Friday night = higher value)
- The User app should read this value to show accurate delivery estimates


================================================================================
                    STEP 1: READ ESTIMATED TIME FROM FIRESTORE
================================================================================

When the user views a restaurant or branch, fetch the estimated time:

DART CODE:
----------

Future<int> getEstimatedTime(String branchId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('Branch')
        .doc(branchId)
        .get();

    if (!doc.exists) {
      return 20; // Default if branch not found
    }

    final data = doc.data()!;
    final rawTime = data['estimatedTime'];

    // Handle different data types safely
    if (rawTime is int) {
      return rawTime.clamp(10, 90);
    } else if (rawTime is double) {
      return rawTime.round().clamp(10, 90);
    } else if (rawTime is String) {
      return (int.tryParse(rawTime) ?? 20).clamp(10, 90);
    } else {
      return 20; // Default for null or unknown type
    }
  } catch (e) {
    print('Error fetching estimated time: $e');
    return 20; // Default on error
  }
}

WHY HANDLE MULTIPLE TYPES?
- Firebase may store numbers as int or double depending on how they were written
- Old data might have strings or null values
- Always clamp to 10-90 to prevent invalid values


================================================================================
                    STEP 2: CALCULATE TOTAL DELIVERY TIME
================================================================================

Total Delivery Time = Preparation Time + Travel Time

FORMULA:
--------
  Total = estimatedTime + (distanceKm / averageSpeed * 60)

WHERE:
- estimatedTime = from Firestore (minutes)
- distanceKm = distance from restaurant to user (kilometers)
- averageSpeed = typical rider speed (30 km/h is reasonable for city traffic)

DART CODE:
----------

int calculateTotalDeliveryTime({
  required int prepTimeMinutes,  // From Firestore
  required double distanceKm,    // User's distance from restaurant
  double riderSpeedKmh = 30.0,   // Average speed in km/h
}) {
  // Calculate travel time in minutes
  final travelMinutes = (distanceKm / riderSpeedKmh * 60).ceil();
  
  // Total time
  return prepTimeMinutes + travelMinutes;
}

EXAMPLE:
--------
- Prep time from Firestore: 25 minutes
- Distance: 5 km
- Rider speed: 30 km/h

Travel time = (5 / 30) * 60 = 10 minutes
Total = 25 + 10 = 35 minutes

Display to user: "Estimated delivery: 35-45 mins" (with 10 min buffer)


================================================================================
                    STEP 3: DISPLAY TIME TO USER
================================================================================

ALWAYS show a RANGE, not an exact number. This manages customer expectations.

DART CODE:
----------

String formatDeliveryTime(int totalMinutes) {
  final minTime = totalMinutes;
  final maxTime = totalMinutes + 10; // 10 minute buffer
  
  if (totalMinutes < 30) {
    return '$minTime-$maxTime mins';
  } else if (totalMinutes < 60) {
    return '$minTime-$maxTime mins';
  } else {
    // For long times, round to nearest 5
    final roundedMin = (minTime / 5).ceil() * 5;
    final roundedMax = roundedMin + 15;
    return '$roundedMin-$roundedMax mins';
  }
}

DISPLAY EXAMPLES:
-----------------
  Total 25 mins → "25-35 mins"
  Total 40 mins → "40-50 mins"
  Total 70 mins → "70-85 mins"


================================================================================
                    STEP 4: STORE TIME IN ORDER (AT CHECKOUT)
================================================================================

When the user places an order, SAVE the estimated time at that moment.

WHY?
- Admin might change the prep time after the order is placed
- User's order tracking should use the time that was shown at checkout
- Helps with order history and analytics

DART CODE:
----------

await FirebaseFirestore.instance.collection('Orders').add({
  // ... other order fields ...
  
  // Save estimated times as snapshot
  'estimatedPrepTimeMinutes': prepTime,      // From Firestore at checkout
  'estimatedTravelMinutes': travelTime,       // Calculated from distance
  'totalEstimatedMinutes': prepTime + travelTime,
  
  // Timestamps
  'createdAt': FieldValue.serverTimestamp(),
  'estimatedDeliveryAt': Timestamp.fromDate(
    DateTime.now().add(Duration(minutes: prepTime + travelTime + 5)),
  ),
});


================================================================================
                    STEP 5: REAL-TIME UPDATES (OPTIONAL)
================================================================================

If user is on the restaurant page or checkout, listen for changes:

DART CODE:
----------

class _RestaurantScreenState extends State<RestaurantScreen> {
  StreamSubscription? _subscription;
  int _estimatedTime = 20;

  @override
  void initState() {
    super.initState();
    _listenToEstimatedTime();
  }

  void _listenToEstimatedTime() {
    _subscription = FirebaseFirestore.instance
        .collection('Branch')
        .doc(widget.branchId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final rawTime = snapshot.data()?['estimatedTime'];
        setState(() {
          if (rawTime is int) {
            _estimatedTime = rawTime.clamp(10, 90);
          } else if (rawTime is double) {
            _estimatedTime = rawTime.round().clamp(10, 90);
          } else {
            _estimatedTime = 20;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}


================================================================================
                         UI DESIGN SUGGESTIONS
================================================================================

1. RESTAURANT CARD (in listing)
   ┌────────────────────────────────────┐
   │ 🍕 Pizza Palace                    │
   │ ⭐ 4.5 • 2.3 km away               │
   │ 🕐 Est. 35-45 mins                 │
   └────────────────────────────────────┘

2. RESTAURANT DETAILS PAGE
   ┌────────────────────────────────────┐
   │ Delivery Time                      │
   │ 🍳 Preparation: ~25 mins           │
   │ 🚗 Delivery: ~15 mins              │
   │ ────────────────────────────       │
   │ Total: 40-50 mins                  │
   └────────────────────────────────────┘

3. BUSY INDICATOR (when prep time > 45 mins)
   ┌────────────────────────────────────┐
   │ 🔥 Currently Busy                  │
   │ Estimated wait: 50-60 mins         │
   └────────────────────────────────────┘

4. CHECKOUT SCREEN
   ┌────────────────────────────────────┐
   │ 📦 Order Summary                   │
   │ ────────────────────────────       │
   │ Delivery Address: ...              │
   │ Estimated Arrival: 6:45 PM - 7:00 PM│
   │ (approximately 35-45 mins)         │
   └────────────────────────────────────┘

5. ORDER TRACKING
   Show live countdown using:
   - Order's createdAt timestamp
   - Order's totalEstimatedMinutes (saved at checkout)


================================================================================
                         EDGE CASES TO HANDLE
================================================================================

1. FIELD MISSING
   - If 'estimatedTime' doesn't exist, default to 20 minutes

2. INVALID VALUE
   - If value is outside 10-90, clamp it to valid range
   - If value is null, use default 20

3. OFFLINE/ERROR
   - Cache the last known value locally
   - Show cached value with "(last updated X ago)" note

4. VERY HIGH VALUES
   - If prep time > 60 mins, show warning: "High demand - longer wait times"

5. RESTAURANT CLOSED
   - Don't show estimated time if restaurant is currently closed
   - Show "Opens at X:XX" instead


================================================================================
                         DEVELOPER CHECKLIST
================================================================================

[ ] Read 'estimatedTime' from Branch collection
[ ] Handle int, double, String, and null types safely
[ ] Always clamp values to 10-90 range
[ ] Calculate total = prep time + travel time
[ ] Display as range with buffer (e.g., "35-45 mins")
[ ] Save estimated times in Order document at checkout
[ ] Show "Busy" indicator when prep time > 45 mins
[ ] (Optional) Add real-time listener for restaurant screens
[ ] (Optional) Cache last known value for offline support


================================================================================
                              SUMMARY
================================================================================

The Admin app stores 'estimatedTime' (10-90 mins) in each Branch document.

Your User app should:
1. READ this value when showing restaurant info
2. ADD travel time based on user's distance
3. DISPLAY as a time range with buffer
4. SAVE snapshot in Order document at checkout
5. HANDLE edge cases (null, invalid, offline)

This ensures customers see accurate, real-time delivery estimates that 
restaurants can adjust during busy periods.

================================================================================

