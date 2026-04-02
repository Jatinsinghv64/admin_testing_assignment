import 'package:cloud_firestore/cloud_firestore.dart';
import '../Widgets/TimeUtils.dart';
import '../constants.dart';

class BranchMetricsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Global KPIs
  Stream<int> getActiveBranchesCount() {
    return _db
        .collection(AppConstants.collectionBranch)
        .where('isOpen', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Stream<double> getTodayVolume(List<String> branchIds) {
    final start = TimeUtils.getBusinessStartTimestamp();
    Query<Map<String, dynamic>> query = _db.collection(AppConstants.collectionOrders);
    
    // We can't easily filter by branchIds aggregate in Firestore if the list is long
    // For global volume, we just sum everything from today if super admin
    return query
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .snapshots()
        .map((snap) {
      double total = 0;
      final billableStatuses = {'delivered', 'completed', 'paid', 'collected'};
      for (var doc in snap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (!billableStatuses.contains(status)) continue;

        final docBranchIds = (data['branchIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        
        bool matches = branchIds.isEmpty; // Super admin
        if (!matches) {
          for (var id in branchIds) {
            if (docBranchIds.contains(id)) {
              matches = true;
              break;
            }
          }
        }

        if (matches) {
          total += (data['totalAmount'] as num? ?? 0).toDouble();
        }
      }
      return total;
    });
  }

  Stream<String> getTodayAvgDeliveryTime(List<String> branchIds) {
    // This is tricky as we don't store actual delivery duration in a simple field usually.
    // For now, let's use the average estimatedTime of today's orders or a static value if unavailable.
    // Or we can average the 'estimatedTime' field from the Branch documents themselves.
    return _db.collection(AppConstants.collectionBranch).snapshots().map((snap) {
      double total = 0;
      int count = 0;
      for (var doc in snap.docs) {
        final data = doc.data();
        if (branchIds.isEmpty || branchIds.contains(doc.id)) {
          total += (data['estimatedTime'] as num? ?? 25).toDouble();
          count++;
        }
      }
      if (count == 0) return '0m';
      return '${(total / count).toStringAsFixed(1)}m';
    });
  }

  // Branch Specific Metrics
  Stream<int> getActiveOrdersCount(String branchId) {
    return _db
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: branchId)
        .snapshots()
        .map((snap) {
      return snap.docs.where((doc) {
        final status = doc.data()['status']?.toString();
        return !AppConstants.isTerminalStatus(status);
      }).length;
    });
  }

  Stream<int> getRiderCount(String branchId) {
    return _db
        .collection('staff')
        .where('staffType', isEqualTo: 'driver')
        .where('branchIds', arrayContains: branchId)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // City Filter
  Stream<List<String>> getUniqueCities() {
    return _db.collection(AppConstants.collectionBranch).snapshots().map((snap) {
      final cities = snap.docs
          .map((doc) => (doc.data()['address'] as Map?)?['city']?.toString() ?? '')
          .where((city) => city.isNotEmpty)
          .toSet()
          .toList();
      cities.sort();
      return ['All', ...cities];
    });
  }
}
