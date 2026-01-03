// lib/constants.dart

class AppConstants {
  // Firestore Collections
  static const String collectionOrders = 'Orders';
  static const String collectionStaff = 'staff';
  static const String collectionBranch = 'Branch';
  static const String collectionDrivers = 'Drivers';
  static const String collectionRiderAssignments = 'rider_assignments';

  // Order Statuses (Optional, but good practice)
  static const String statusPending = 'pending';
  static const String statusPreparing = 'preparing';
  static const String statusPrepared = 'prepared';
  static const String statusRiderAssigned = 'rider_assigned';
  static const String statusPickedUp = 'pickedUp';
  static const String statusDelivered = 'delivered';
  static const String statusCancelled = 'cancelled';
  static const String statusNeedsAssignment = 'needs_rider_assignment';
}