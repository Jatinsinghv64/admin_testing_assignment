import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import 'ConnectionUtils.dart';

class RestaurantTimingScreen extends StatefulWidget {
  const RestaurantTimingScreen({super.key});

  @override
  State<RestaurantTimingScreen> createState() => _RestaurantTimingScreenState();
}

class _RestaurantTimingScreenState extends State<RestaurantTimingScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasError = false;
  String? _errorMessage;
  Map<String, dynamic> _workingHours = {};
  Map<String, dynamic> _originalWorkingHours =
      {}; // Track original for unsaved changes

  // SuperAdmin branch selection
  String? _selectedBranchId;
  List<Map<String, dynamic>> _allBranches = [];
  bool _isSuperAdmin = false;

  // Kitchen Operations - Preparation Time
  static const int _minEstimatedTime = 10;
  static const int _maxEstimatedTime = 90;
  static const int _defaultEstimatedTime = 20;
  static const int _warningThreshold = 60; // Warn if setting above this
  static const int _maxRetries = 3; // Retry attempts for failed updates
  
  int _preparationTime = _defaultEstimatedTime;
  int _lastSavedPrepTime = _defaultEstimatedTime; // For rollback on error
  bool _isUpdatingPrepTime = false;
  DateTime? _lastPrepTimeUpdate; // Debounce tracking
  DateTime? _estimatedTimeLastUpdatedAt; // When it was last updated in Firestore
  StreamSubscription<DocumentSnapshot>? _branchSubscription; // Real-time sync
  int _retryCount = 0; // Current retry attempt

  // Ordered list of days
  final List<String> _days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday'
  ];

  // Track if user made changes
  bool get _hasUnsavedChanges {
    return _workingHours.toString() != _originalWorkingHours.toString();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeScreen());
  }

  @override
  void dispose() {
    _branchSubscription?.cancel();
    super.dispose();
  }

  // --- Initialization ---

  Future<void> _initializeScreen() async {
    final userScope = context.read<UserScopeService>();

    // Wait for userScope to load if needed
    if (!userScope.isLoaded) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      _initializeScreen();
      return;
    }

    // Only use multi-branch mode if SuperAdmin has more than 1 branch assigned
    _isSuperAdmin = userScope.isSuperAdmin && userScope.branchIds.length > 1;

    if (_isSuperAdmin) {
      await _loadAssignedBranches(userScope.branchIds);
    } else if (userScope.branchId.isNotEmpty) {
      _selectedBranchId = userScope.branchId;
      await _loadTimings();
    } else {
      // Edge case: User with no branches
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'No branch assigned to your account.';
      });
    }
  }

  Future<void> _loadAssignedBranches(List<String> branchIds) async {
    if (branchIds.isEmpty) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'No branches assigned to your account.';
      });
      return;
    }

    try {
      final List<Map<String, dynamic>> loadedBranches = [];

      for (final branchId in branchIds) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('Branch')
              .doc(branchId)
              .get();
          if (doc.exists) {
            final data = doc.data()!;
            loadedBranches.add({
              'id': doc.id,
              'name': data['name'] ?? doc.id,
            });
          }
        } catch (e) {
          debugPrint('Error loading branch $branchId: $e');
        }
      }

      if (!mounted) return;

      if (loadedBranches.isEmpty) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              'Could not load any branches. Please check your connection.';
        });
        return;
      }

      setState(() {
        _allBranches = loadedBranches;
        _selectedBranchId = _allBranches.first['id'];
      });

      await _loadTimings();
    } catch (e) {
      debugPrint("Error loading assigned branches: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Failed to load branches: $e';
        });
      }
    }
  }

  // --- Data Loading ---

  Future<void> _loadTimings() async {
    if (_selectedBranchId == null || _selectedBranchId!.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('Branch')
          .doc(_selectedBranchId)
          .get()
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (doc.exists) {
        _parseEstimatedTimeFromDoc(doc.data()!);
        _parseWorkingHoursFromDoc(doc.data()!);
      } else {
        _initializeDefaultTimings();
      }
      
      // Start real-time listener for external updates to estimatedTime
      _startEstimatedTimeListener();
      
    } catch (e) {
      debugPrint("Error loading timings: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              'Failed to load timings. Please check your connection.';
        });
      }
    }
  }
  
  /// Parse estimated time and timestamp from Firestore document
  void _parseEstimatedTimeFromDoc(Map<String, dynamic> data) {
    // Load estimated time with robust type handling
    final rawPrepTime = data['estimatedTime'];
    int parsedTime = _defaultEstimatedTime;
    
    if (rawPrepTime is int) {
      parsedTime = rawPrepTime;
    } else if (rawPrepTime is double) {
      parsedTime = rawPrepTime.round();
    } else if (rawPrepTime is String) {
      parsedTime = int.tryParse(rawPrepTime) ?? _defaultEstimatedTime;
    }
    
    // Clamp to valid bounds
    _preparationTime = parsedTime.clamp(_minEstimatedTime, _maxEstimatedTime);
    _lastSavedPrepTime = _preparationTime;
    
    // Parse last updated timestamp
    final rawTimestamp = data['estimatedTimeUpdatedAt'];
    if (rawTimestamp is Timestamp) {
      _estimatedTimeLastUpdatedAt = rawTimestamp.toDate();
    } else {
      _estimatedTimeLastUpdatedAt = null;
    }
  }
  
  /// Parse working hours from Firestore document
  void _parseWorkingHoursFromDoc(Map<String, dynamic> data) {
    if (data.containsKey('workingHours')) {
      final loadedHours = Map<String, dynamic>.from(data['workingHours']);
      setState(() {
        _workingHours = loadedHours;
        _originalWorkingHours = Map<String, dynamic>.from(loadedHours.map(
            (key, value) => MapEntry(key, Map<String, dynamic>.from(value))));
        _isLoading = false;
      });
    } else {
      _initializeDefaultTimings();
    }
  }
  
  /// Start real-time listener for estimatedTime changes from other admins
  void _startEstimatedTimeListener() {
    _branchSubscription?.cancel(); // Cancel any existing subscription
    
    if (_selectedBranchId == null || _selectedBranchId!.isEmpty) return;
    
    _branchSubscription = FirebaseFirestore.instance
        .collection('Branch')
        .doc(_selectedBranchId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      
      final data = snapshot.data()!;
      final rawPrepTime = data['estimatedTime'];
      int newPrepTime = _defaultEstimatedTime;
      
      if (rawPrepTime is int) {
        newPrepTime = rawPrepTime;
      } else if (rawPrepTime is double) {
        newPrepTime = rawPrepTime.round();
      } else if (rawPrepTime is String) {
        newPrepTime = int.tryParse(rawPrepTime) ?? _defaultEstimatedTime;
      }
      
      newPrepTime = newPrepTime.clamp(_minEstimatedTime, _maxEstimatedTime);
      
      // Only update if value changed externally (not from our own update)
      // and we're not currently in the middle of updating
      if (newPrepTime != _lastSavedPrepTime && !_isUpdatingPrepTime) {
        setState(() {
          _preparationTime = newPrepTime;
          _lastSavedPrepTime = newPrepTime;
          
          // Update timestamp
          final rawTimestamp = data['estimatedTimeUpdatedAt'];
          if (rawTimestamp is Timestamp) {
            _estimatedTimeLastUpdatedAt = rawTimestamp.toDate();
          }
        });
        
        // Show notification that value was updated externally
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ℹ️ Estimated time updated to $newPrepTime mins by another admin'),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }, onError: (e) {
      debugPrint('Real-time listener error: $e');
    });
  }

  void _initializeDefaultTimings() {
    final defaultHours = <String, dynamic>{};
    for (var day in _days) {
      defaultHours[day] = {
        'isOpen': true,
        'slots': [
          {'open': '09:00', 'close': '22:00'}
        ]
      };
    }
    setState(() {
      _workingHours = defaultHours;
      _originalWorkingHours = Map<String, dynamic>.from(defaultHours.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value))));
      _isLoading = false;
    });
  }

  // --- Validation ---

  String? _validateSlots(String day) {
    final dayData = _workingHours[day];
    if (dayData == null || dayData['isOpen'] != true) return null;

    final List slots = dayData['slots'] ?? [];
    if (slots.isEmpty) return null;

    // Check for overlapping slots
    for (int i = 0; i < slots.length; i++) {
      for (int j = i + 1; j < slots.length; j++) {
        if (_doSlotsOverlap(slots[i], slots[j])) {
          return 'Slot ${i + 1} and Slot ${j + 1} overlap';
        }
      }
    }
    return null;
  }

  bool _doSlotsOverlap(Map slot1, Map slot2) {
    final open1 = _parseTimeToMinutes(slot1['open'] ?? '00:00');
    final close1 = _parseTimeToMinutes(slot1['close'] ?? '23:59');
    final open2 = _parseTimeToMinutes(slot2['open'] ?? '00:00');
    final close2 = _parseTimeToMinutes(slot2['close'] ?? '23:59');

    // Handle overnight slots (close < open)
    if (close1 < open1 || close2 < open2) {
      return false; // Allow overnight slots without overlap check
    }

    return (open1 < close2) && (open2 < close1);
  }

  int _parseTimeToMinutes(String time) {
    try {
      final parts = time.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    } catch (e) {
      return 0;
    }
  }

  bool _validateAllSlots() {
    for (var day in _days) {
      final error = _validateSlots(day);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${day.toUpperCase()}: $error'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }
    }
    return true;
  }

  // --- Actions & Logic ---

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
            const SizedBox(width: 12),
            const Text('Unsaved Changes'),
          ],
        ),
        content: const Text(
            'You have unsaved changes. Are you sure you want to leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _saveTimings() async {
    if (_selectedBranchId == null || _selectedBranchId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('❌ Error: No Branch selected'),
            backgroundColor: Colors.red),
      );
      return;
    }

    // Validate all slots before saving
    if (!_validateAllSlots()) return;

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection('Branch')
          .doc(_selectedBranchId)
          .set({'workingHours': _workingHours},
              SetOptions(merge: true)).timeout(const Duration(seconds: 15));

      if (mounted) {
        final branchName = _allBranches.firstWhere(
          (b) => b['id'] == _selectedBranchId,
          orElse: () => {'name': _selectedBranchId},
        )['name'];

        // Update original to match saved state
        _originalWorkingHours = Map<String, dynamic>.from(_workingHours.map(
            (key, value) => MapEntry(key, Map<String, dynamic>.from(value))));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Timings updated for $branchName!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ Error saving: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  void _copyMondayToAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Apply to All Days?'),
        content: const Text(
            'This will overwrite all other days with Monday\'s schedule. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                final mondayData = _workingHours['monday'];
                if (mondayData != null) {
                  for (var day in _days) {
                    if (day != 'monday') {
                      _workingHours[day] = {
                        'isOpen': mondayData['isOpen'] ?? true,
                        'slots': List.from((mondayData['slots'] as List? ?? [])
                            .map((s) => Map.from(s))),
                      };
                    }
                  }
                }
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Applied Monday\'s schedule to all days')),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // --- Kitchen Operations ---

  Future<void> _updatePreparationTime(int newValue, {bool skipConfirmation = false}) async {
    if (_selectedBranchId == null || _selectedBranchId!.isEmpty) return;
    
    // Clamp to valid bounds
    final clampedValue = newValue.clamp(_minEstimatedTime, _maxEstimatedTime);
    
    // Debounce: prevent rapid updates (minimum 500ms between saves)
    final now = DateTime.now();
    if (_lastPrepTimeUpdate != null &&
        now.difference(_lastPrepTimeUpdate!).inMilliseconds < 500) {
      return;
    }
    
    // Skip if value hasn't actually changed
    if (clampedValue == _lastSavedPrepTime) return;
    
    // Show warning for high values (60+ mins)
    if (!skipConfirmation && clampedValue >= _warningThreshold) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
              const SizedBox(width: 12),
              const Text('High Estimated Time'),
            ],
          ),
          content: Text(
            'Setting estimated time to $clampedValue minutes may significantly impact customer experience. '
            'Are you sure you want to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Revert slider to last saved value
                setState(() => _preparationTime = _lastSavedPrepTime);
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      
      if (shouldProceed != true) return;
    }

    // Check connectivity before attempting update
    final hasConnection = await ConnectionUtils.hasInternetConnection();
    if (!hasConnection) {
      if (mounted) {
        setState(() => _preparationTime = _lastSavedPrepTime);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('No internet connection. Please try again.'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _updatePreparationTime(clampedValue, skipConfirmation: true),
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isUpdatingPrepTime = true);
    _lastPrepTimeUpdate = now;
    _retryCount = 0;

    await _performUpdateWithRetry(clampedValue);
  }
  
  /// Performs the Firestore update with exponential backoff retry logic
  Future<void> _performUpdateWithRetry(int clampedValue) async {
    try {
      await FirebaseFirestore.instance
          .collection('Branch')
          .doc(_selectedBranchId)
          .set({
            'estimatedTime': clampedValue,
            'estimatedTimeUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      // Update last saved value and timestamp on success
      _lastSavedPrepTime = clampedValue;
      _estimatedTimeLastUpdatedAt = DateTime.now();
      _retryCount = 0;
      
      // Haptic feedback on success
      HapticFeedback.lightImpact();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Estimated time updated to $clampedValue mins'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating estimated time (attempt ${_retryCount + 1}): $e');
      
      // Retry with exponential backoff
      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delaySeconds = 1 << (_retryCount - 1); // 1s, 2s, 4s
        debugPrint('Retrying in $delaySeconds seconds...');
        
        await Future.delayed(Duration(seconds: delaySeconds));
        
        if (mounted) {
          await _performUpdateWithRetry(clampedValue);
        }
        return;
      }
      
      // All retries exhausted - rollback and show error
      if (mounted) {
        setState(() => _preparationTime = _lastSavedPrepTime);
        
        // Haptic feedback for error
        HapticFeedback.heavyImpact();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed after $_maxRetries retries. Reverted to $_lastSavedPrepTime mins.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                _retryCount = 0;
                _updatePreparationTime(clampedValue, skipConfirmation: true);
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted && _retryCount == 0) {
        // Only set loading false if we're done (not retrying)
        setState(() => _isUpdatingPrepTime = false);
      } else if (mounted && _retryCount >= _maxRetries) {
        setState(() => _isUpdatingPrepTime = false);
      }
    }
  }

  Widget _buildKitchenOperationsCard() {
    // Don't show card while initial data is loading
    if (_isLoading) {
      return const SizedBox.shrink();
    }
    
    return Semantics(
      label: 'Kitchen Operations. Estimated time is $_preparationTime minutes. '
             'Use slider to adjust between $_minEstimatedTime and $_maxEstimatedTime minutes.',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.orange.shade200, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.restaurant, color: Colors.orange.shade700, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kitchen Operations',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Adjust estimated time during busy hours',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (_isUpdatingPrepTime)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text(
                    'Estimated Time:',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  // Show unsaved indicator
                  if (_preparationTime != _lastSavedPrepTime && !_isUpdatingPrepTime)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.edit, size: 14, color: Colors.orange.shade600),
                    ),
                  // Tappable badge for direct input
                  Semantics(
                    button: true,
                    label: 'Tap to enter estimated time manually',
                    child: InkWell(
                      onTap: _isUpdatingPrepTime ? null : _showDirectInputDialog,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          // Red tint for high values (warning zone)
                          color: _preparationTime >= _warningThreshold 
                              ? Colors.red.shade100 
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _preparationTime >= _warningThreshold 
                                ? Colors.red.shade300 
                                : Colors.orange.shade300,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_preparationTime mins',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _preparationTime >= _warningThreshold 
                                    ? Colors.red.shade800 
                                    : Colors.orange.shade800,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit_outlined,
                              size: 12,
                              color: _preparationTime >= _warningThreshold 
                                  ? Colors.red.shade600 
                                  : Colors.orange.shade600,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  // Red tint for high values
                  activeTrackColor: _preparationTime >= _warningThreshold 
                      ? Colors.red.shade400 
                      : Colors.orange,
                  inactiveTrackColor: _preparationTime >= _warningThreshold 
                      ? Colors.red.shade100 
                      : Colors.orange.shade100,
                  thumbColor: _preparationTime >= _warningThreshold 
                      ? Colors.red.shade700 
                      : Colors.orange.shade700,
                  overlayColor: (_preparationTime >= _warningThreshold 
                      ? Colors.red 
                      : Colors.orange).withValues(alpha: 0.2),
                  valueIndicatorColor: _preparationTime >= _warningThreshold 
                      ? Colors.red.shade700 
                      : Colors.orange.shade700,
                  valueIndicatorTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: Slider(
                  value: _preparationTime.toDouble().clamp(
                      _minEstimatedTime.toDouble(), _maxEstimatedTime.toDouble()),
                  min: _minEstimatedTime.toDouble(),
                  max: _maxEstimatedTime.toDouble(),
                  divisions: ((_maxEstimatedTime - _minEstimatedTime) ~/ 5), // Step size of 5
                  label: '$_preparationTime mins',
                  onChanged: _isUpdatingPrepTime 
                      ? null // Disable while updating
                      : (value) {
                          // Haptic feedback on slider change
                          HapticFeedback.selectionClick();
                          setState(() {
                            _preparationTime = value.round();
                          });
                        },
                  onChangeEnd: _isUpdatingPrepTime 
                      ? null 
                      : (value) {
                          _updatePreparationTime(value.round());
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$_minEstimatedTime min', 
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text('$_maxEstimatedTime min', 
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Last updated timestamp
              if (_estimatedTimeLastUpdatedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Text(
                        'Last updated: ${_formatLastUpdated(_estimatedTimeLastUpdatedAt!)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This affects delivery time estimates shown to customers',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Format the last updated timestamp in a user-friendly way
  String _formatLastUpdated(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min${diff.inMinutes > 1 ? 's' : ''} ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
  
  /// Show dialog for direct input of estimated time
  Future<void> _showDirectInputDialog() async {
    final controller = TextEditingController(text: _preparationTime.toString());
    final formKey = GlobalKey<FormState>();
    
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.orange),
            SizedBox(width: 12),
            Text('Set Estimated Time'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Minutes',
                  hintText: 'Enter value ($_minEstimatedTime-$_maxEstimatedTime)',
                  suffixText: 'mins',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.orange, width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a value';
                  }
                  final parsed = int.tryParse(value);
                  if (parsed == null) {
                    return 'Please enter a valid number';
                  }
                  if (parsed < _minEstimatedTime || parsed > _maxEstimatedTime) {
                    return 'Must be between $_minEstimatedTime-$_maxEstimatedTime';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Enter a value between $_minEstimatedTime and $_maxEstimatedTime minutes.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final value = int.parse(controller.text);
                Navigator.pop(context, value);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    
    if (result != null && result != _preparationTime) {
      setState(() => _preparationTime = result);
      _updatePreparationTime(result);
    }
  }

  // --- Time Management ---

  Future<void> _pickTime(
      String day, int index, String key, String currentTime) async {
    TimeOfDay initial = _parseTime(currentTime);
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: const TimePickerThemeData(
              dayPeriodBorderSide: BorderSide(color: Colors.deepPurple),
              dialHandColor: Colors.deepPurple,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final String formattedPicked = _formatTimeForStorage(picked);

      final currentSlot = _workingHours[day]['slots'][index];
      String openTime = key == 'open' ? formattedPicked : currentSlot['open'];
      String closeTime =
          key == 'close' ? formattedPicked : currentSlot['close'];

      setState(() {
        _workingHours[day]['slots'][index][key] = formattedPicked;
      });

      // Show info message for overnight slots
      if (!_isTimeAfter(openTime, closeTime) && openTime != closeTime) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ℹ️ Overnight shift detected (closes next day)'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  bool _isTimeAfter(String open, String close) {
    final o = _parseTime(open);
    final c = _parseTime(close);
    final openMinutes = o.hour * 60 + o.minute;
    final closeMinutes = c.hour * 60 + c.minute;
    return closeMinutes > openMinutes;
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return const TimeOfDay(hour: 9, minute: 0); // Default fallback
    }
  }

  String _formatTimeForStorage(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTimeForDisplay(BuildContext context, String timeStr) {
    final time = _parseTime(timeStr);
    return time.format(context);
  }

  void _addSlot(String day) {
    setState(() {
      List slots = List.from(_workingHours[day]['slots'] ?? []);
      slots.add({'open': '09:00', 'close': '17:00'});
      _workingHours[day]['slots'] = slots;
    });
  }

  void _removeSlot(String day, int index) {
    final List slots = _workingHours[day]['slots'] ?? [];
    if (slots.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('At least one slot is required. Turn off the day instead.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      List newSlots = List.from(slots);
      newSlots.removeAt(index);
      _workingHours[day]['slots'] = newSlots;
    });
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('Restaurant Timings',
              style: TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.black87),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (_hasUnsavedChanges) {
                final shouldPop = await _onWillPop();
                if (shouldPop && mounted) {
                  Navigator.of(context).pop();
                }
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            if (!_isLoading && !_hasError && _selectedBranchId != null)
              TextButton.icon(
                onPressed: _isSaving ? null : _saveTimings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.green))
                    : Icon(Icons.check_circle,
                        color: _hasUnsavedChanges ? Colors.green : Colors.grey),
                label: Text(
                  _isSaving ? 'Saving...' : 'Save',
                  style: TextStyle(
                    color: _hasUnsavedChanges ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.deepPurple),
            SizedBox(height: 16),
            Text('Loading timings...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'An error occurred',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _initializeScreen,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Branch selector only for SuperAdmin with multiple branches
        if (_isSuperAdmin && _allBranches.length > 1) _buildBranchSelector(),
        if (_selectedBranchId != null) ...[
          // Unsaved changes indicator
          if (_hasUnsavedChanges)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.edit_note, size: 18, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Text(
                    'You have unsaved changes',
                    style: TextStyle(
                        color: Colors.orange[700], fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          _buildBulkActions(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: _days.length,
              itemBuilder: (context, index) {
                return _buildDayCard(_days[index]);
              },
            ),
          ),
        ] else
          const Expanded(
            child: Center(
              child: Text(
                'Please select a branch to manage timings',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBranchSelector() {
    return Container(
      width: double.infinity,
      color: Colors.indigo.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.store, color: Colors.indigo, size: 20),
          const SizedBox(width: 12),
          const Text(
            'Branch:',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedBranchId,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: Colors.indigo),
                  items: _allBranches.map((branch) {
                    return DropdownMenuItem<String>(
                      value: branch['id'],
                      child: Text(
                        branch['name'],
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) async {
                    if (newValue == null || newValue == _selectedBranchId)
                      return;

                    // Check for unsaved changes before switching
                    if (_hasUnsavedChanges) {
                      final shouldSwitch = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Unsaved Changes'),
                          content: const Text(
                              'You have unsaved changes. Switching branches will discard them.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange),
                              child: const Text('Switch Anyway'),
                            ),
                          ],
                        ),
                      );
                      if (shouldSwitch != true) return;
                    }

                    setState(() {
                      _selectedBranchId = newValue;
                      _workingHours = {};
                    });
                    _loadTimings();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActions() {
    return Container(
      width: double.infinity,
      color: Colors.deepPurple.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Quick Actions",
              style: TextStyle(
                  color: Colors.deepPurple, fontWeight: FontWeight.bold)),
          TextButton.icon(
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text("Apply Monday to All"),
            style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
            onPressed: _copyMondayToAll,
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(String day) {
    final dayData = _workingHours[day] ?? {'isOpen': false, 'slots': []};
    final bool isOpen = dayData['isOpen'] ?? false;
    final List slots = dayData['slots'] ?? [];
    final String? validationError = _validateSlots(day);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: validationError != null
            ? const BorderSide(color: Colors.orange, width: 2)
            : BorderSide.none,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isOpen,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Row(
            children: [
              Text(
                day.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isOpen ? Colors.black87 : Colors.grey,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (validationError != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.warning_amber,
                      size: 18, color: Colors.orange[700]),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOpen ? Colors.green.shade100 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isOpen ? 'OPEN' : 'CLOSED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color:
                        isOpen ? Colors.green.shade800 : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          trailing: Switch.adaptive(
            value: isOpen,
            activeColor: Colors.green,
            onChanged: (val) {
              setState(() {
                _workingHours[day] = _workingHours[day] ?? {};
                _workingHours[day]['isOpen'] = val;
                // Initialize a default slot if enabling and no slots exist
                if (val &&
                    (_workingHours[day]['slots'] == null ||
                        (_workingHours[day]['slots'] as List).isEmpty)) {
                  _workingHours[day]['slots'] = [
                    {'open': '09:00', 'close': '22:00'}
                  ];
                }
              });
            },
          ),
          children: [
            if (isOpen) ...[
              const Divider(height: 1),
              if (validationError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          validationError,
                          style: TextStyle(
                              color: Colors.orange[700], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (slots.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No shifts added. Store appears offline.',
                      style: TextStyle(color: Colors.orange)),
                ),
              ...slots.asMap().entries.map((entry) {
                final index = entry.key;
                final slot = entry.value;
                return _buildSlotRow(day, index, slot, slots.length);
              }),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OutlinedButton.icon(
                  onPressed: () => _addSlot(day),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Shift'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepPurple,
                    side: const BorderSide(color: Colors.deepPurple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ] else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.grey.shade50,
                child: const Center(
                    child: Text('Closed all day',
                        style: TextStyle(
                            color: Colors.grey, fontStyle: FontStyle.italic))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotRow(String day, int index, Map slot, int totalSlots) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _TimeChip(
              label: "Open",
              time: _formatTimeForDisplay(context, slot['open'] ?? '09:00'),
              onTap: () =>
                  _pickTime(day, index, 'open', slot['open'] ?? '09:00'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
          ),
          Expanded(
            child: _TimeChip(
              label: "Close",
              time: _formatTimeForDisplay(context, slot['close'] ?? '22:00'),
              onTap: () =>
                  _pickTime(day, index, 'close', slot['close'] ?? '22:00'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: totalSlots > 1 ? Colors.redAccent : Colors.grey,
            ),
            onPressed: totalSlots > 1 ? () => _removeSlot(day, index) : null,
            tooltip:
                totalSlots > 1 ? "Remove Shift" : "At least one slot required",
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;

  const _TimeChip(
      {required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            const SizedBox(height: 2),
            Text(time,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
