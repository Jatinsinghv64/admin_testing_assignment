import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/timings/TimingKpiRow.dart';
import '../Widgets/timings/KitchenLoadCard.dart';
import '../Widgets/timings/HolidayClosuresCard.dart';
import '../Widgets/timings/WeeklyScheduleGrid.dart';
import '../constants.dart';

class RestaurantTimingScreenLarge extends StatefulWidget {
  final String branchId;

  const RestaurantTimingScreenLarge({super.key, required this.branchId});

  @override
  State<RestaurantTimingScreenLarge> createState() => _RestaurantTimingScreenLargeState();
}

class _RestaurantTimingScreenLargeState extends State<RestaurantTimingScreenLarge> {
  bool _isLoading = true;
  bool _isSaving = false;
  late String _currentBranchId;
  Map<String, dynamic> _branchData = {};
  StreamSubscription<DocumentSnapshot>? _subscription;

  // Constants for calculations
  static const double _avgHourlyRate = 25.0; // QAR
  static const double _avgDailyRevenue = 5000.0; // QAR

  @override
  void initState() {
    super.initState();
    _currentBranchId = widget.branchId;
    _startSubscription();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startSubscription() {
    _subscription?.cancel();
    _subscription = FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _branchData = snapshot.data() ?? {};
          _isLoading = false;
        });
      }
    });
  }

  // --- Calculations ---

  double _calculateLaborCost() {
    final workingHours = _branchData['workingHours'] as Map? ?? {};
    double totalCost = 0;
    workingHours.forEach((day, data) {
      final slots = (data['slots'] as List?) ?? [];
      for (var slot in slots) {
        final start = _parseTime(slot['open'] ?? '09:00');
        final end = _parseTime(slot['close'] ?? '22:00');
        final duration = end.difference(start).inHours.toDouble();
        final staffCount = (slot['staffCount'] as int?) ?? 4;
        totalCost += duration * staffCount * _avgHourlyRate;
      }
    });
    return totalCost / 7; // Average daily cost
  }

  double _calculateEfficiency() {
    final laborCost = _calculateLaborCost();
    if (laborCost == 0) return 0;
    return (_avgDailyRevenue / laborCost) * 10; // Simple ratio for display
  }

  Future<void> _applyTemplate(String name) async {
    final Map<String, dynamic> workingHours = {};
    final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    
    List<Map<String, dynamic>> slots = [];
    if (name == 'Standard Ops') {
      slots = [
        {'open': '09:00', 'close': '22:00', 'staffCount': 4, 'requiredStaff': 4}
      ];
    } else if (name == 'Extended Weekend') {
      // Split between weekdays and weekends
    }

    for (var day in days) {
      if (name == 'Extended Weekend' && (day == 'friday' || day == 'saturday')) {
        workingHours[day] = {
          'isOpen': true,
          'slots': [
            {'open': '09:00', 'close': '23:59', 'staffCount': 6, 'requiredStaff': 6}
          ]
        };
      } else {
        workingHours[day] = {'isOpen': true, 'slots': List.from(slots)};
      }
    }

    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'workingHours': workingHours, 'activeTemplate': name});
  }

  int _calculateConflicts() {
    final workingHours = _branchData['workingHours'] as Map? ?? {};
    int conflicts = 0;
    workingHours.forEach((day, data) {
      final slots = (data['slots'] as List?) ?? [];
      for (int i = 0; i < slots.length; i++) {
        for (int j = i + 1; j < slots.length; j++) {
          if (_doSlotsOverlap(slots[i], slots[j])) {
            conflicts++;
          }
        }
      }
    });
    return conflicts;
  }

  bool _doSlotsOverlap(Map slot1, Map slot2) {
    final start1 = _parseTimeMinutes(slot1['open'] ?? '09:00');
    final end1 = _parseTimeMinutes(slot1['close'] ?? '22:00');
    final start2 = _parseTimeMinutes(slot2['open'] ?? '09:00');
    final end2 = _parseTimeMinutes(slot2['close'] ?? '22:00');
    
    return start1 < end2 && start2 < end1;
  }

  int _parseTimeMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int _calculateCoverage() {
    final workingHours = _branchData['workingHours'] as Map? ?? {};
    int totalMinutes = 0;
    workingHours.forEach((day, data) {
      final slots = (data['slots'] as List?) ?? [];
      for (var slot in slots) {
        final start = _parseTimeMinutes(slot['open'] ?? '09:00');
        final end = _parseTimeMinutes(slot['close'] ?? '22:00');
        totalMinutes += (end - start);
      }
    });
    
    // Average daily coverage vs a standard 12h day (720 mins)
    final avgDailyMins = totalMinutes / 7;
    return ((avgDailyMins / 900) * 100).clamp(0, 100).toInt(); 
  }

  DateTime _parseTime(String time) {
    final parts = time.split(':');
    return DateTime(2024, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
  }

  // --- Actions ---

  Future<void> _updatePrepTime(int value) async {
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({
      'estimatedTime': value,
      'estimatedTimeUpdatedAt': FieldValue.serverTimestamp(),
    });
    setState(() => _isSaving = false);
  }

  Future<void> _addThrottleRule() async {
    final rules = List<Map<String, dynamic>>.from(_branchData['throttleRules'] ?? []);
    rules.add({'orderCount': 10, 'extraTime': 5});
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'throttleRules': rules});
  }

  Future<void> _deleteThrottleRule(int index) async {
    final rules = List<Map<String, dynamic>>.from(_branchData['throttleRules'] ?? []);
    rules.removeAt(index);
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'throttleRules': rules});
  }

  Future<void> _addHoliday() async {
    final holidays = List<Map<String, dynamic>>.from(_branchData['holidayClosures'] ?? []);
    holidays.add({
      'name': 'New Exception',
      'date': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      'type': 'Fully Closed',
    });
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'holidayClosures': holidays});
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.deepPurple));
    }

    final prepTime = (_branchData['estimatedPreparationTime'] as int?) ?? 20;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TIMING MANAGEMENT',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _branchData['name'] ?? 'Branch Schedule',
                      style: textTheme.headlineMedium?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                      ),
                    ),
                  ],
                ),
                _buildSyncStatus(context),
              ],
            ),
            const SizedBox(height: 24),
            // Template Selection
            _buildTemplateRow(context, userScope, branchFilter),
            const SizedBox(height: 32),


            // KPI Row
            TimingKpiRow(
              projectedLaborCost: _calculateLaborCost().toStringAsFixed(0),
              laborEfficiency: _calculateEfficiency().toStringAsFixed(0),
              shiftConflicts: _calculateConflicts(),
              scheduleCoverage: _calculateCoverage(),
            ),
            const SizedBox(height: 32),

            // Main Content Area
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column (Schedule)
                Expanded(
                  flex: 3, // Increased flex to reduce empty space on right if any
                  child: Column(
                    children: [
                      WeeklyScheduleGrid(
                        schedule: _prepareScheduleData(),
                        dayStatus: _prepareDayStatus(),
                        onAddShift: (day) => _addShift(day),
                        onDeleteShift: (day, index) => _deleteShift(day, index),
                        onUpdateShift: (day, index, data) => _updateShift(day, index, data, existing: data),
                        onToggleDay: (day, isOpen) => _toggleDay(day, isOpen),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                // Right Column (Kitchen Load & Holidays)
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      KitchenLoadCard(
                        preparationTime: prepTime,
                        onPreparationTimeChanged: (v) => _updatePrepTime(v),
                        isUpdatingPrepTime: _isSaving,
                        rushModeOverride: _branchData['rushModeEnabled'] ?? false,
                        onRushModeChanged: (v) => _toggleRushMode(v),
                        throttleRules: List<Map<String, dynamic>>.from(_branchData['throttleRules'] ?? []),
                        onAddRule: _addThrottleRule,
                        onDeleteRule: _deleteThrottleRule,
                      ),
                      const SizedBox(height: 32),
                      HolidayClosuresCard(
                        holidays: _prepareHolidayData(),
                        onAddHoliday: _addHoliday,
                        onDeleteHoliday: (i) => _deleteHoliday(i),
                        onEditHoliday: (i) => _editHoliday(i),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateRow(BuildContext context, UserScopeService userScope, BranchFilterService branchFilter) {
    final activeTemplate = _branchData['activeTemplate'] ?? 'Standard Ops';
    final textTheme = Theme.of(context).textTheme;
    
    return Row(
      children: [
        Text(
          'Active Template:',
          style: textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          onSelected: _applyTemplate,
          offset: const Offset(0, 48),
          itemBuilder: (context) => [
            _buildTemplateItem('Standard Ops', Icons.auto_awesome),
            _buildTemplateItem('Extended Weekend', Icons.wb_sunny),
            _buildTemplateItem('Holiday Minimal', Icons.ac_unit),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.dashboard_customize, color: Colors.deepPurple, size: 16),
                const SizedBox(width: 8),
                Text(
                  activeTemplate,
                  style: textTheme.bodySmall?.copyWith(color: Colors.deepPurple, fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
              ],
            ),
          ),
        ),

        const Spacer(),
        if (userScope.isSuperAdmin) ...[
          _buildBranchSelector(userScope, branchFilter),
          const SizedBox(width: 12),
        ],
        OutlinedButton.icon(
          onPressed: () {},
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepPurple,
            side: const BorderSide(color: Colors.deepPurple),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.history, size: 18),
          label: const Text('View Change Log', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSyncStatus(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_done, color: Colors.deepPurple, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Data Sync Status',
                style: textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Synchronized Live',
                style: textTheme.bodySmall?.copyWith(color: Colors.black87, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Data Transformation Helpers ---

  Map<String, List<Map<String, dynamic>>> _prepareScheduleData() {
    final Map<String, List<Map<String, dynamic>>> schedule = {};
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final workingHours = _branchData['workingHours'] as Map? ?? {};

    for (var day in days) {
      final dayKey = day.toLowerCase();
      final dayData = workingHours[dayKey] as Map? ?? {};
      final slots = (dayData['slots'] as List?) ?? [];
      
      schedule[day] = slots.map((s) => {
        'startTime': (s['open'] as String?) ?? '09:00',
        'endTime': (s['close'] as String?) ?? '22:00',
        'staffCount': (s['staffCount'] as int?) ?? 4,
        'requiredStaff': (s['requiredStaff'] as int?) ?? 4,
      }).toList();
    }
    return schedule;
  }

  Map<String, bool> _prepareDayStatus() {
    final Map<String, bool> status = {};
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final workingHours = _branchData['workingHours'] as Map? ?? {};

    for (var day in days) {
      final dayKey = day.toLowerCase();
      final dayData = workingHours[dayKey] as Map? ?? {};
      status[day] = (dayData['isOpen'] as bool?) ?? true;
    }
    return status;
  }

  List<Map<String, dynamic>> _prepareHolidayData() {
    final raw = _branchData['holidayClosures'] as List? ?? [];
    return raw.map((h) {
      final map = Map<String, dynamic>.from(h);
      if (map['date'] is Timestamp) {
        map['date'] = (map['date'] as Timestamp).toDate();
      }
      return map;
    }).toList();
  }

  // --- CRUD Methods ---

  Future<void> _addShift(String day) async {
    final dayKey = day.toLowerCase();
    final workingHours = Map<String, dynamic>.from(_branchData['workingHours'] ?? {});
    final dayData = Map<String, dynamic>.from(workingHours[dayKey] ?? {'isOpen': true, 'slots': []});
    final slots = List<Map<String, dynamic>>.from(dayData['slots'] ?? []);
    
    slots.add({'open': '09:00', 'close': '22:00', 'staffCount': 4, 'requiredStaff': 4});
    dayData['slots'] = slots;
    workingHours[dayKey] = dayData;
    
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'workingHours': workingHours});
  }

  Future<void> _deleteShift(String day, int index) async {
    final dayKey = day.toLowerCase();
    final workingHours = Map<String, dynamic>.from(_branchData['workingHours'] ?? {});
    final dayData = Map<String, dynamic>.from(workingHours[dayKey] ?? {});
    final slots = List<Map<String, dynamic>>.from(dayData['slots'] ?? []);
    
    slots.removeAt(index);
    dayData['slots'] = slots;
    workingHours[dayKey] = dayData;
    
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'workingHours': workingHours});
  }

  Future<void> _updateShift(String day, int index, Map<String, dynamic> data, {Map<String, dynamic>? existing}) async {
    final dayKey = day.toLowerCase();
    final workingHours = Map<String, dynamic>.from(_branchData['workingHours'] ?? {});
    final dayData = Map<String, dynamic>.from(workingHours[dayKey] ?? {});
    final slots = List<Map<String, dynamic>>.from(dayData['slots'] ?? []);
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ShiftEditDialog(initialData: existing ?? slots[index]),
    );

    if (result != null) {
      slots[index] = result;
      dayData['slots'] = slots;
      workingHours[dayKey] = dayData;
      
      await FirebaseFirestore.instance
          .collection(AppConstants.collectionBranch)
          .doc(_currentBranchId)
          .update({'workingHours': workingHours});
    }
  }

  Future<void> _toggleDay(String day, bool isOpen) async {
    final dayKey = day.toLowerCase();
    final workingHours = Map<String, dynamic>.from(_branchData['workingHours'] ?? {});
    final dayData = Map<String, dynamic>.from(workingHours[dayKey] ?? {'slots': []});
    
    dayData['isOpen'] = isOpen;
    workingHours[dayKey] = dayData;
    
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'workingHours': workingHours});
  }

  Future<void> _toggleRushMode(bool value) async {
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'rushModeEnabled': value});
  }

  Future<void> _deleteHoliday(int index) async {
    final holidays = List<Map<String, dynamic>>.from(_branchData['holidayClosures'] ?? []);
    holidays.removeAt(index);
    await FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId)
        .update({'holidayClosures': holidays});
  }
  
  Future<void> _editHoliday(int index) async {
    final holidays = List<Map<String, dynamic>>.from(_branchData['holidayClosures'] ?? []);
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _HolidayEditDialog(initialData: holidays[index]),
    );

  }
  PopupMenuItem<String> _buildTemplateItem(String name, IconData icon) {
    return PopupMenuItem(
      value: name,
      child: Row(
        children: [
          Icon(icon, color: Colors.deepPurple, size: 18),
          const SizedBox(width: 12),
          Text(name, style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBranchSelector(UserScopeService userScope, BranchFilterService branchFilter) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _currentBranchId,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.deepPurple),
          style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 13),
          onChanged: (String? newValue) {
            if (newValue != null && newValue != _currentBranchId) {
              setState(() {
                _currentBranchId = newValue;
                _isLoading = true;
              });
              _startSubscription();
            }
          },
          items: userScope.branchIds.map<DropdownMenuItem<String>>((String id) {
            return DropdownMenuItem<String>(
              value: id,
              child: Text(branchFilter.getBranchName(id)),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ShiftEditDialog extends StatefulWidget {
  final Map<String, dynamic> initialData;

  const _ShiftEditDialog({required this.initialData});

  @override
  State<_ShiftEditDialog> createState() => _ShiftEditDialogState();
}

class _ShiftEditDialogState extends State<_ShiftEditDialog> {
  late String _open;
  late String _close;
  late int _staff;
  late int _required;

  @override
  void initState() {
    super.initState();
    _open = widget.initialData['open'] ?? '09:00';
    _close = widget.initialData['close'] ?? '22:00';
    _staff = widget.initialData['staffCount'] ?? 4;
    _required = widget.initialData['requiredStaff'] ?? 4;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EDIT SHIFT',
              style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 24),
            _buildTimePicker('START TIME', _open, (v) => setState(() => _open = v)),
            const SizedBox(height: 16),
            _buildTimePicker('END TIME', _close, (v) => setState(() => _close = v)),
            const SizedBox(height: 24),
            _buildCounter('STAFF ON DUTY', _staff, (v) => setState(() => _staff = v)),
            const SizedBox(height: 16),
            _buildCounter('REQUIRED STAFF', _required, (v) => setState(() => _required = v)),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, {
                      'open': _open,
                      'close': _close,
                      'staffCount': _staff,
                      'requiredStaff': _required,
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(String label, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final time = TimeOfDay(hour: int.parse(value.split(':')[0]), minute: int.parse(value.split(':')[1]));
            final picked = await showTimePicker(context: context, initialTime: time);
            if (picked != null) {
              onChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(value, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                const Icon(Icons.access_time, color: Colors.deepPurple, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCounter(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        Row(
          children: [
            _counterButton(Icons.remove, () => onChanged(value > 0 ? value - 1 : 0)),
            const SizedBox(width: 16),
            Text(value.toString().padLeft(2, '0'), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(width: 16),
            _counterButton(Icons.add, () => onChanged(value + 1)),
          ],
        ),
      ],
    );
  }

  Widget _counterButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.deepPurple, size: 16),
      ),
    );
  }
}

class _HolidayEditDialog extends StatefulWidget {
  final Map<String, dynamic> initialData;

  const _HolidayEditDialog({required this.initialData});

  @override
  State<_HolidayEditDialog> createState() => _HolidayEditDialogState();
}

class _HolidayEditDialogState extends State<_HolidayEditDialog> {
  late String _name;
  late DateTime _date;
  late String _type;

  @override
  void initState() {
    super.initState();
    _name = widget.initialData['name'] ?? '';
    _date = widget.initialData['date'] is DateTime ? widget.initialData['date'] : (widget.initialData['date'] as Timestamp).toDate();
    _type = widget.initialData['type'] ?? 'Fully Closed';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HOLIDAY EXCEPTION',
              style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 24),
            _buildTextField('EXCEPTION NAME', _name, (v) => _name = v),
            const SizedBox(height: 16),
            _buildDatePicker('DATE', _date, (v) => setState(() => _date = v)),
            const SizedBox(height: 16),
            _buildDropdown('TYPE', _type, ['Fully Closed', 'Short Hours', 'Special Event'], (v) => setState(() => _type = v!)),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, {
                      'name': _name,
                      'date': Timestamp.fromDate(_date),
                      'type': _type,
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('SAVE EXCEPTION', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, String initialValue, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: initialValue,
          onChanged: onChanged,
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('MMM dd, yyyy').format(value), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                const Icon(Icons.calendar_today, color: Colors.deepPurple, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: Colors.white,
            underline: const SizedBox(),
            items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)))).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
