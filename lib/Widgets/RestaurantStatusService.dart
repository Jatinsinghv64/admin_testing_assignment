import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ❌ REMOVED: import 'BackgroundOrderService.dart'; 

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
      } else {
        // Create document with default closed status if it doesn't exist
        await docRef.set({
          'name': _restaurantName,
          'isOpen': false,
          'branchId': _restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _isOpen = false;
        debugPrint('✅ Created new branch document with closed status');
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

      // Update Firestore
      await docRef.set({
        'isOpen': newStatus,
        'lastStatusUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _isOpen = newStatus;
      debugPrint('✅ Restaurant status updated to: $newStatus');

      // ❌ REMOVED: await _updateBackgroundListener(); (No longer needed)

    } catch (e) {
      debugPrint('❌ Error updating restaurant status: $e');
      _isOpen = !newStatus; // Revert UI on failure
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}