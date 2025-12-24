



// Restaurant Status Service
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'BackgroundOrderService.dart';

class RestaurantStatusService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isOpen = false;
  bool _isLoading = false;
  String? _restaurantId;
  String? _restaurantName;

  bool get isOpen => _isOpen;
  bool get isLoading => _isLoading;
  String? get restaurantId => _restaurantId;
  String? get restaurantName => _restaurantName;

  void initialize(String restaurantId, {String restaurantName = "Restaurant"}) {
    _restaurantId = restaurantId;
    _restaurantName = restaurantName;
    _loadRestaurantStatus();
  }

  Future<void> _loadRestaurantStatus() async {
    if (_restaurantId == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      final docRef = _db.collection('Branch').doc(_restaurantId!);
      final doc = await docRef.get();

      if (doc.exists) {
        _isOpen = doc.data()?['isOpen'] ?? false;
        _restaurantName = doc.data()?['name'] ?? _restaurantName;
        debugPrint('✅ Loaded restaurant status: $_isOpen for $_restaurantName');

        // ✅ NEW LOGIC: Just update the listener.
        // main.dart already handled starting the service.
        await _updateBackgroundListener();

      } else {
        // Create document with default closed status
        await docRef.set({
          'name': _restaurantName,
          'isOpen': false,
          'branchId': _restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _isOpen = false;
        debugPrint('✅ Created new branch document with closed status');
        // Update listener to 'idle' state
        await _updateBackgroundListener();
      }
    } catch (e) {
      debugPrint('❌ Error loading restaurant status: $e');
      _isOpen = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleRestaurantStatus(bool newStatus) async {
    if (_restaurantId == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      final docRef = _db.collection('Branch').doc(_restaurantId!);

      await docRef.set({
        'isOpen': newStatus,
        'lastStatusUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _isOpen = newStatus;
      debugPrint('✅ Restaurant status updated to: $newStatus');

      // ✅ NEW LOGIC: Just update the listener.
      await _updateBackgroundListener();

    } catch (e) {
      debugPrint('❌ Error updating restaurant status: $e');
      _isOpen = !newStatus; // Revert on failure
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _updateBackgroundListener() async {
    // This is now the single source of truth for updating the service.
    if (_restaurantId == null) {
      debugPrint("❌ Cannot update listener, restaurantId is null");
      return;
    }

    if (_isOpen) {
      // Restaurant is Open, give it the branch ID
      debugPrint('🟢 Restaurant opened - Updating listener');
      List<String> branchIds = [_restaurantId!];
      await BackgroundOrderService.updateListener(branchIds);
    } else {
      // Restaurant is Closed, give it an empty list
      debugPrint('🔴 Restaurant closed - Setting listener to idle');
      await BackgroundOrderService.updateListener([]);
    }

    // We can check the 'isRunning' status just for logging
    bool isRunning = await BackgroundOrderService.isServiceRunning();
    debugPrint('🔍 Background service isRunning status: $isRunning');
  }

// ❌ _startBackgroundService() and _stopBackgroundService() are no longer needed
}
