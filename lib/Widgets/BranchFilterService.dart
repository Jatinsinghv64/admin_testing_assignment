import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Service to manage branch filter state across Dashboard and Orders screens.
/// Only relevant for SuperAdmin users with multiple branches.
class BranchFilterService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sentinel value for "All Branches" selection (used because PopupMenuButton
  /// doesn't fire onSelected for null values)
  static const String allBranchesValue = '__all_branches__';

  String? _selectedBranchId; // null = "All Branches"
  Map<String, String> _branchNames = {}; // Cache: branchId -> branchName
  bool _isLoaded = false;

  /// Currently selected branch ID (null means "All Branches")
  String? get selectedBranchId => _selectedBranchId;

  /// Whether branch names have been loaded
  bool get isLoaded => _isLoaded;

  /// Get branch name by ID (returns ID if name not cached)
  String getBranchName(String branchId) {
    return _branchNames[branchId] ?? branchId;
  }

  /// Get all cached branch names
  Map<String, String> get branchNames => Map.unmodifiable(_branchNames);

  /// Select a specific branch (or allBranchesValue for "All Branches")
  /// Always notifies listeners to ensure UI refresh when user makes explicit selection
  void selectBranch(String? branchId) {
    // Convert sentinel value to null (internal representation)
    if (branchId == allBranchesValue) {
      _selectedBranchId = null;
    } else {
      _selectedBranchId = branchId;
    }
    debugPrint('BranchFilterService: Selected branch = $_selectedBranchId');
    notifyListeners();
  }

  /// Get branchIds to filter by based on selection
  /// - If a specific branch is selected, return [selectedBranchId]
  /// - If "All Branches" (null), return the full list
  List<String> getFilterBranchIds(List<String> userBranchIds) {
    if (_selectedBranchId != null) {
      return [_selectedBranchId!];
    }
    return userBranchIds;
  }

  /// Load branch names from Firestore for the given branch IDs
  Future<void> loadBranchNames(List<String> branchIds) async {
    if (branchIds.isEmpty) return;

    try {
      // Fetch branch documents in parallel
      final futures = branchIds.map((id) =>
          _db.collection('Branch').doc(id).get()
      ).toList();

      final snapshots = await Future.wait(futures);

      for (final snap in snapshots) {
        if (snap.exists) {
          final data = snap.data();
          _branchNames[snap.id] = data?['name']?.toString() ?? snap.id;
        }
      }

      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading branch names: $e');
    }
  }

  /// Clear filter (reset to "All Branches")
  void clearFilter() {
    _selectedBranchId = null;
    notifyListeners();
  }

  /// Reset service state
  void reset() {
    _selectedBranchId = null;
    _branchNames.clear();
    _isLoaded = false;
    notifyListeners();
  }

  /// Validate current selection against a list of valid branch IDs
  /// Call this when UserScope updates (e.g., branch removed from profile)
  void validateSelection(List<String> validBranchIds) {
    if (_selectedBranchId != null && !validBranchIds.contains(_selectedBranchId)) {
      _selectedBranchId = null; // Reset to "All" if current selection is no longer valid
      notifyListeners();
    }
  }
}
