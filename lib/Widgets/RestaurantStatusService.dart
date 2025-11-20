



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
        await _updateBackgroundListener();

      } else {
        await docRef.set({
          'name': _restaurantName,
          'isOpen': false,
          'branchId': _restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _isOpen = false;
        debugPrint('✅ Created new branch document with closed status');
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
      await _updateBackgroundListener();

    } catch (e) {
      debugPrint('❌ Error updating restaurant status: $e');
      _isOpen = !newStatus;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _updateBackgroundListener() async {
    if (_restaurantId == null) {
      debugPrint("❌ Cannot update listener, restaurantId is null");
      return;
    }

    if (_isOpen) {
      debugPrint('🟢 Restaurant opened - Updating listener');
      List<String> branchIds = [_restaurantId!];
      await BackgroundOrderService.updateListener(branchIds);
    } else {
      debugPrint('🔴 Restaurant closed - Setting listener to idle');
      await BackgroundOrderService.updateListener([]);
    }

    // This line relies on the fixed BackgroundOrderService
    bool isRunning = await BackgroundOrderService.isServiceRunning();
    debugPrint('🔍 Background service isRunning status: $isRunning');
  }
}
