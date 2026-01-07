import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

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
  Map<String, dynamic> _originalWorkingHours = {}; // Track original for unsaved changes

  // SuperAdmin branch selection
  String? _selectedBranchId;
  List<Map<String, dynamic>> _allBranches = [];
  bool _isSuperAdmin = false;

  // Ordered list of days
  final List<String> _days = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
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
          final doc = await FirebaseFirestore.instance.collection('Branch').doc(branchId).get();
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
          _errorMessage = 'Could not load any branches. Please check your connection.';
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

      if (doc.exists && doc.data()!.containsKey('workingHours')) {
        final loadedHours = Map<String, dynamic>.from(doc.data()!['workingHours']);
        setState(() {
          _workingHours = loadedHours;
          _originalWorkingHours = Map<String, dynamic>.from(
            loadedHours.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)))
          );
          _isLoading = false;
        });
      } else {
        _initializeDefaultTimings();
      }
    } catch (e) {
      debugPrint("Error loading timings: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Failed to load timings. Please check your connection.';
        });
      }
    }
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
      _originalWorkingHours = Map<String, dynamic>.from(
        defaultHours.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)))
      );
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
        content: const Text('You have unsaved changes. Are you sure you want to leave without saving?'),
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
        const SnackBar(content: Text('❌ Error: No Branch selected'), backgroundColor: Colors.red),
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
          .set({'workingHours': _workingHours}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        final branchName = _allBranches.firstWhere(
          (b) => b['id'] == _selectedBranchId,
          orElse: () => {'name': _selectedBranchId},
        )['name'];

        // Update original to match saved state
        _originalWorkingHours = Map<String, dynamic>.from(
          _workingHours.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)))
        );

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
          SnackBar(content: Text('❌ Error saving: $e'), backgroundColor: Colors.red),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                final mondayData = _workingHours['monday'];
                if (mondayData != null) {
                  for (var day in _days) {
                    if (day != 'monday') {
                      _workingHours[day] = {
                        'isOpen': mondayData['isOpen'] ?? true,
                        'slots': List.from((mondayData['slots'] as List? ?? []).map((s) => Map.from(s))),
                      };
                    }
                  }
                }
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Applied Monday\'s schedule to all days')),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // --- Time Management ---

  Future<void> _pickTime(String day, int index, String key, String currentTime) async {
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
      String closeTime = key == 'close' ? formattedPicked : currentSlot['close'];

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
          content: Text('At least one slot is required. Turn off the day instead.'),
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
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
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
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green))
                    : Icon(Icons.check_circle, color: _hasUnsavedChanges ? Colors.green : Colors.grey),
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
        body: _buildBody(),
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
                    style: TextStyle(color: Colors.orange[700], fontWeight: FontWeight.w500),
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
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.indigo),
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
                    if (newValue == null || newValue == _selectedBranchId) return;
                    
                    // Check for unsaved changes before switching
                    if (_hasUnsavedChanges) {
                      final shouldSwitch = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Unsaved Changes'),
                          content: const Text('You have unsaved changes. Switching branches will discard them.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
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
              style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
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
                  child: Icon(Icons.warning_amber, size: 18, color: Colors.orange[700]),
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
                    color: isOpen ? Colors.green.shade800 : Colors.grey.shade600,
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
                if (val && (_workingHours[day]['slots'] == null || 
                    (_workingHours[day]['slots'] as List).isEmpty)) {
                  _workingHours[day]['slots'] = [{'open': '09:00', 'close': '22:00'}];
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
                          style: TextStyle(color: Colors.orange[700], fontSize: 12),
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
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
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
              onTap: () => _pickTime(day, index, 'open', slot['open'] ?? '09:00'),
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
              onTap: () => _pickTime(day, index, 'close', slot['close'] ?? '22:00'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: totalSlots > 1 ? Colors.redAccent : Colors.grey,
            ),
            onPressed: totalSlots > 1 ? () => _removeSlot(day, index) : null,
            tooltip: totalSlots > 1 ? "Remove Shift" : "At least one slot required",
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

  const _TimeChip({required this.label, required this.time, required this.onTap});

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
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            const SizedBox(height: 2),
            Text(time,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}