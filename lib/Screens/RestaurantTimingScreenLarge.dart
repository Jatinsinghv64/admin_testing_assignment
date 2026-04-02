import 'dart:convert';
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
import '../Widgets/timings/working_hours_utils.dart';
import '../models/timing_template.dart';
import '../services/timing_template_service.dart';
import 'TimingTemplatesManagement.dart';
import '../constants.dart';

class RestaurantTimingScreenLarge extends StatefulWidget {
  final String branchId;

  const RestaurantTimingScreenLarge({super.key, required this.branchId});

  @override
  State<RestaurantTimingScreenLarge> createState() =>
      _RestaurantTimingScreenLargeState();
}

class _RestaurantTimingScreenLargeState
    extends State<RestaurantTimingScreenLarge> {
  bool _isLoading = true;
  bool _isSaving = false;
  late String _currentBranchId;
  Map<String, dynamic> _branchData = {};
  StreamSubscription<DocumentSnapshot>? _subscription;
  final _templateService = TimingTemplateService();

  // Constants for calculations
  static const double _avgHourlyRate = 25.0; // QAR
  static const double _avgDailyRevenue = 5000.0; // QAR

  @override
  void initState() {
    super.initState();
    _currentBranchId = widget.branchId;
    _templateService.seedDefaultTemplates(); // Ensure defaults exist
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

  Future<void> _updateFirestore(
      Map<String, dynamic> data, String description) async {
    final userEmail = context.read<UserScopeService>().userEmail;
    final batch = FirebaseFirestore.instance.batch();

    final branchRef = FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(_currentBranchId);
    batch.update(branchRef, data);

    final logRef = branchRef.collection('changeLogs').doc();
    batch.set(logRef, {
      'description': description,
      'user': userEmail,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'timing_update'
    });

    await batch.commit();
  }

  // --- Calculations ---

  double _calculateLaborCost() {
    final workingHours = WorkingHoursUtils.cloneWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );
    double totalCost = 0;
    workingHours.forEach((day, data) {
      final slots = (data['slots'] as List?) ?? [];
      for (var slot in slots) {
        final duration = WorkingHoursUtils.calculateSlotDurationMinutes(
              Map<String, dynamic>.from(slot),
            ) /
            60;
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

  Future<void> _applyTemplate(TimingTemplate template) async {
    final validation = WorkingHoursUtils.validateWorkingHours(
      template.workingHours,
      includeStaffingDefaults: true,
    );

    if (!validation.isValid) {
      _showSnackBar(
        validation.firstErrorMessage ??
            'Template contains an invalid schedule.',
        backgroundColor: Colors.red,
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.deepPurple)),
    );

    try {
      await _updateFirestore({
        'workingHours': validation.normalizedWorkingHours,
        'activeTemplate': template.name
      }, 'Applied template: ${template.name}');

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applied "${template.name}" template')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to apply template: $e')),
        );
      }
    }
  }

  void _showSnackBar(
    String message, {
    Color backgroundColor = Colors.black87,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveWorkingHours(
    Map<String, dynamic> candidateWorkingHours, {
    required String description,
    String? successMessage,
  }) async {
    if (_isSaving) {
      return;
    }

    final validation = WorkingHoursUtils.validateWorkingHours(
      candidateWorkingHours,
      includeStaffingDefaults: true,
    );

    if (!validation.isValid) {
      _showSnackBar(
        validation.firstErrorMessage ?? 'The schedule contains invalid shifts.',
        backgroundColor: Colors.red,
      );
      return;
    }

    final existingNormalized = WorkingHoursUtils.cloneWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );

    if (jsonEncode(existingNormalized) ==
        jsonEncode(validation.normalizedWorkingHours)) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _updateFirestore(
        {'workingHours': validation.normalizedWorkingHours},
        description,
      );
      if (successMessage != null) {
        _showSnackBar(successMessage, backgroundColor: Colors.green);
      }
    } catch (error) {
      _showSnackBar(
        'Failed to update schedule: $error',
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showShiftEditor(
    String day, {
    int? index,
    Map<String, dynamic>? initialData,
  }) async {
    var draft = Map<String, dynamic>.from(
      initialData ??
          WorkingHoursUtils.createDefaultSlot(includeStaffingDefaults: true),
    );

    while (mounted) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ShiftEditDialog(initialData: draft),
      );

      if (result == null) {
        return;
      }

      draft = Map<String, dynamic>.from(result);

      final dayKey = day.toLowerCase();
      final workingHours = WorkingHoursUtils.cloneWorkingHours(
        Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
        includeStaffingDefaults: true,
      );
      final dayData = Map<String, dynamic>.from(
        workingHours[dayKey] ??
            <String, dynamic>{
              'isOpen': true,
              'slots': <Map<String, dynamic>>[]
            },
      );
      final slots =
          List<Map<String, dynamic>>.from(dayData['slots'] ?? const []);

      if (index != null && index >= 0 && index < slots.length) {
        slots[index] = draft;
      } else {
        slots.add(draft);
      }

      dayData['isOpen'] = true;
      dayData['slots'] = slots;
      workingHours[dayKey] = dayData;

      final validation = WorkingHoursUtils.validateWorkingHours(
        workingHours,
        includeStaffingDefaults: true,
      );

      if (!validation.isValid) {
        _showSnackBar(
          validation.firstErrorMessage ??
              'This shift overlaps with another shift.',
          backgroundColor: Colors.red,
        );
        continue;
      }

      final action = index == null ? 'Added' : 'Updated';
      await _saveWorkingHours(
        validation.normalizedWorkingHours,
        description: '$action shift on $day',
        successMessage: '$action shift on $day',
      );
      return;
    }
  }

  Future<void> _saveHolidayList(
    List<Map<String, dynamic>> holidays, {
    required String description,
    String? successMessage,
  }) async {
    if (_isSaving) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _updateFirestore({'holidayClosures': holidays}, description);
      if (successMessage != null) {
        _showSnackBar(successMessage, backgroundColor: Colors.green);
      }
    } catch (error) {
      _showSnackBar(
        'Failed to update holiday exceptions: $error',
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showHolidayEditor({int? index}) async {
    final holidays =
        List<Map<String, dynamic>>.from(_branchData['holidayClosures'] ?? []);
    final initialData = index != null && index >= 0 && index < holidays.length
        ? holidays[index]
        : <String, dynamic>{
            'name': '',
            'date': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 7)),
            ),
            'type': 'Fully Closed',
          };

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _HolidayEditDialog(initialData: initialData),
    );

    if (result == null) {
      return;
    }

    final normalizedName = (result['name'] as String? ?? '').trim();
    if (normalizedName.isEmpty) {
      _showSnackBar(
        'Holiday exception name is required.',
        backgroundColor: Colors.red,
      );
      return;
    }

    final normalizedHoliday = <String, dynamic>{
      ...result,
      'name': normalizedName,
    };
    final normalizedDate = normalizedHoliday['date'] is Timestamp
        ? (normalizedHoliday['date'] as Timestamp).toDate()
        : normalizedHoliday['date'] as DateTime;

    final hasDuplicate = holidays.asMap().entries.any((entry) {
      if (index != null && entry.key == index) {
        return false;
      }

      final existing = entry.value;
      final existingDate = existing['date'] is Timestamp
          ? (existing['date'] as Timestamp).toDate()
          : existing['date'] as DateTime;

      return existingDate.year == normalizedDate.year &&
          existingDate.month == normalizedDate.month &&
          existingDate.day == normalizedDate.day &&
          (existing['type'] ?? '') == normalizedHoliday['type'] &&
          (existing['name'] ?? '').toString().trim().toLowerCase() ==
              normalizedName.toLowerCase();
    });

    if (hasDuplicate) {
      _showSnackBar(
        'A matching holiday exception already exists for that date.',
        backgroundColor: Colors.red,
      );
      return;
    }

    if (index != null && index >= 0 && index < holidays.length) {
      holidays[index] = normalizedHoliday;
      await _saveHolidayList(
        holidays,
        description: 'Updated holiday exception',
        successMessage: 'Updated holiday exception',
      );
    } else {
      holidays.add(normalizedHoliday);
      await _saveHolidayList(
        holidays,
        description: 'Added a new holiday exception',
        successMessage: 'Added holiday exception',
      );
    }
  }

  int _calculateConflicts() {
    final validation = WorkingHoursUtils.validateWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );

    return validation.issues
        .where((issue) =>
            issue.code == 'same_day_overlap' ||
            issue.code == 'cross_day_overlap')
        .length;
  }

  int _calculateCoverage() {
    final workingHours = WorkingHoursUtils.cloneWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );
    int totalMinutes = 0;
    workingHours.forEach((day, data) {
      final slots = (data['slots'] as List?) ?? [];
      for (var slot in slots) {
        totalMinutes += WorkingHoursUtils.calculateSlotDurationMinutes(
          Map<String, dynamic>.from(slot),
        );
      }
    });

    // Average daily coverage against a 15-hour operating target.
    final avgDailyMins = totalMinutes / 7;
    return ((avgDailyMins / 900) * 100).clamp(0, 100).toInt();
  }

  // --- Actions ---

  Future<void> _updatePrepTime(int value) async {
    setState(() => _isSaving = true);
    await _updateFirestore({
      'estimatedTime': value,
      'estimatedTimeUpdatedAt': FieldValue.serverTimestamp(),
    }, 'Updated estimated prep time to $value mins');
    setState(() => _isSaving = false);
  }

  Future<void> _showThrottleRuleDialog([int? index]) async {
    final rules =
        List<Map<String, dynamic>>.from(_branchData['throttleRules'] ?? []);
    int orderCount = index != null
        ? (rules[index]['orderCount'] as num?)?.toInt() ?? 10
        : 10;
    int extraTime =
        index != null ? (rules[index]['extraTime'] as num?)?.toInt() ?? 5 : 5;

    final countController = TextEditingController(text: orderCount.toString());
    final timeController = TextEditingController(text: extraTime.toString());
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? 'Add Throttle Rule' : 'Edit Throttle Rule'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: countController,
                decoration: const InputDecoration(labelText: 'If orders >'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: timeController,
                decoration:
                    const InputDecoration(labelText: 'Add extra time (mins)'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'orderCount': int.parse(countController.text),
                  'extraTime': int.parse(timeController.text),
                });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      if (index != null) {
        rules[index] = result;
        await _updateFirestore(
            {'throttleRules': rules}, 'Updated throttle rule');
      } else {
        rules.add(result);
        await _updateFirestore({'throttleRules': rules}, 'Added throttle rule');
      }
    }
  }

  Future<void> _deleteThrottleRule(int index) async {
    final rules =
        List<Map<String, dynamic>>.from(_branchData['throttleRules'] ?? []);
    rules.removeAt(index);
    await _updateFirestore({'throttleRules': rules}, 'Deleted a throttle rule');
  }

  Future<void> _addHoliday() async {
    await _showHolidayEditor();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();

    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.deepPurple));
    }

    final prepTime = (_branchData['estimatedTime'] as num?)?.toInt() ?? 20;
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
                  flex:
                      3, // Increased flex to reduce empty space on right if any
                  child: Column(
                    children: [
                      WeeklyScheduleGrid(
                        schedule: _prepareScheduleData(),
                        dayStatus: _prepareDayStatus(),
                        onAddShift: (day) => _addShift(day),
                        onDeleteShift: (day, index) => _deleteShift(day, index),
                        onUpdateShift: (day, index, data) =>
                            _updateShift(day, index, data, existing: data),
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
                        rushModeOverride:
                            _branchData['rushModeEnabled'] ?? false,
                        onRushModeChanged: (v) => _toggleRushMode(v),
                        throttleRules: List<Map<String, dynamic>>.from(
                            _branchData['throttleRules'] ?? []),
                        onAddRule: () => _showThrottleRuleDialog(),
                        onDeleteRule: _deleteThrottleRule,
                        onEditRule: (idx) => _showThrottleRuleDialog(idx),
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

  Widget _buildTemplateRow(BuildContext context, UserScopeService userScope,
      BranchFilterService branchFilter) {
    final activeTemplate = _branchData['activeTemplate'] ?? 'Standard Ops';
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Text(
          'Active Template:',
          style: textTheme.labelSmall
              ?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        StreamBuilder<List<TimingTemplate>>(
            stream: _templateService.getTemplates(),
            builder: (context, snapshot) {
              final templates = snapshot.data ?? [];
              return PopupMenuButton<TimingTemplate>(
                onSelected: _applyTemplate,
                offset: const Offset(0, 48),
                itemBuilder: (context) =>
                    templates.map((t) => _buildTemplateItem(t)).toList(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.deepPurple.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.dashboard_customize,
                          color: Colors.deepPurple, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        activeTemplate,
                        style: textTheme.bodySmall?.copyWith(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.bold),
                      ),
                      const Icon(Icons.arrow_drop_down,
                          color: Colors.deepPurple),
                    ],
                  ),
                ),
              );
            }),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const TimingTemplatesManagement()),
            );
          },
          icon: const Icon(Icons.settings, color: Colors.grey, size: 20),
          tooltip: 'Manage Templates',
        ),
        const Spacer(),
        if (userScope.isSuperAdmin) ...[
          _buildBranchSelector(userScope, branchFilter),
          const SizedBox(width: 12),
        ],
        OutlinedButton.icon(
          onPressed: () {
            showDialog(
                context: context,
                builder: (_) => ChangeLogDialog(branchId: _currentBranchId));
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepPurple,
            side: const BorderSide(color: Colors.deepPurple),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.history, size: 18),
          label: const Text('View Change Log',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
            child: const Icon(Icons.cloud_done,
                color: Colors.deepPurple, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Data Sync Status',
                style: textTheme.labelSmall
                    ?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Synchronized Live',
                style: textTheme.bodySmall?.copyWith(
                    color: Colors.black87, fontWeight: FontWeight.w900),
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
    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final workingHours = WorkingHoursUtils.cloneWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );
    final conflictKeys = WorkingHoursUtils.validateWorkingHours(
      workingHours,
      includeStaffingDefaults: true,
    ).conflictSlotKeys;

    for (var day in days) {
      final dayKey = day.toLowerCase();
      final dayData = workingHours[dayKey] as Map? ?? {};
      final slots =
          List<Map<String, dynamic>>.from(dayData['slots'] ?? const []);

      schedule[day] = slots.asMap().entries.map((entry) {
        final index = entry.key;
        final slot = entry.value;
        return <String, dynamic>{
          'startTime': (slot['open'] as String?) ?? '09:00',
          'endTime': (slot['close'] as String?) ?? '22:00',
          'staffCount': (slot['staffCount'] as int?) ?? 4,
          'requiredStaff': (slot['requiredStaff'] as int?) ?? 4,
          'hasConflict': conflictKeys.contains(
            WorkingHoursUtils.slotKey(dayKey, index),
          ),
        };
      }).toList();
    }
    return schedule;
  }

  Map<String, bool> _prepareDayStatus() {
    final Map<String, bool> status = {};
    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final workingHours = WorkingHoursUtils.cloneWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );

    for (var day in days) {
      final dayKey = day.toLowerCase();
      final dayData = workingHours[dayKey] as Map? ?? {};
      status[day] = (dayData['isOpen'] as bool?) ?? false;
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
    await _showShiftEditor(day);
  }

  Future<void> _deleteShift(String day, int index) async {
    final dayKey = day.toLowerCase();
    final workingHours = WorkingHoursUtils.cloneWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );
    final dayData = Map<String, dynamic>.from(workingHours[dayKey] ?? {});
    final slots = List<Map<String, dynamic>>.from(dayData['slots'] ?? []);

    if (index < 0 || index >= slots.length) {
      _showSnackBar(
        'Unable to remove shift: invalid selection.',
        backgroundColor: Colors.red,
      );
      return;
    }

    slots.removeAt(index);
    dayData['slots'] = slots;
    if (slots.isEmpty) {
      dayData['isOpen'] = false;
    }
    workingHours[dayKey] = dayData;

    await _saveWorkingHours(
      workingHours,
      description: slots.isEmpty
          ? 'Removed last shift and closed $day'
          : 'Deleted shift on $day',
      successMessage: slots.isEmpty
          ? 'Removed last shift and closed $day'
          : 'Deleted shift on $day',
    );
  }

  Future<void> _updateShift(String day, int index, Map<String, dynamic> data,
      {Map<String, dynamic>? existing}) async {
    final dayKey = day.toLowerCase();
    final workingHours = WorkingHoursUtils.cloneWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );
    final dayData = Map<String, dynamic>.from(workingHours[dayKey] ?? {});
    final slots = List<Map<String, dynamic>>.from(dayData['slots'] ?? const []);

    if (index < 0 || index >= slots.length) {
      _showSnackBar(
        'Unable to edit shift: invalid selection.',
        backgroundColor: Colors.red,
      );
      return;
    }

    await _showShiftEditor(
      day,
      index: index,
      initialData: existing ?? slots[index],
    );
  }

  Future<void> _toggleDay(String day, bool isOpen) async {
    final dayKey = day.toLowerCase();
    final workingHours = WorkingHoursUtils.cloneWorkingHours(
      Map<String, dynamic>.from(_branchData['workingHours'] ?? {}),
      includeStaffingDefaults: true,
    );
    final dayData = Map<String, dynamic>.from(
      workingHours[dayKey] ?? <String, dynamic>{'isOpen': false, 'slots': []},
    );

    dayData['isOpen'] = isOpen;
    if (isOpen && (dayData['slots'] as List? ?? const []).isEmpty) {
      dayData['slots'] = <Map<String, dynamic>>[
        WorkingHoursUtils.createDefaultSlot(includeStaffingDefaults: true),
      ];
    }
    workingHours[dayKey] = dayData;

    await _saveWorkingHours(
      workingHours,
      description: isOpen ? 'Opened on $day' : 'Closed on $day',
      successMessage: isOpen ? 'Opened $day' : 'Closed $day',
    );
  }

  Future<void> _toggleRushMode(bool value) async {
    // Optimistic UI update
    setState(() {
      _branchData['rushModeEnabled'] = value;
    });
    try {
      await _updateFirestore(
          {'rushModeEnabled': value}, 'Toggled Rush Mode: $value');
    } catch (e) {
      if (mounted) {
        setState(() {
          _branchData['rushModeEnabled'] = !value;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to toggle rush mode: $e')));
      }
    }
  }

  Future<void> _deleteHoliday(int index) async {
    final holidays =
        List<Map<String, dynamic>>.from(_branchData['holidayClosures'] ?? []);
    if (index < 0 || index >= holidays.length) {
      _showSnackBar(
        'Unable to delete holiday exception.',
        backgroundColor: Colors.red,
      );
      return;
    }
    holidays.removeAt(index);
    await _saveHolidayList(
      holidays,
      description: 'Deleted a holiday condition',
      successMessage: 'Deleted holiday exception',
    );
  }

  Future<void> _editHoliday(int index) async {
    await _showHolidayEditor(index: index);
  }

  PopupMenuItem<TimingTemplate> _buildTemplateItem(TimingTemplate template) {
    IconData icon;
    switch (template.icon) {
      case 'wb_sunny':
        icon = Icons.wb_sunny;
        break;
      case 'ac_unit':
        icon = Icons.ac_unit;
        break;
      default:
        icon = Icons.auto_awesome;
    }
    return PopupMenuItem(
      value: template,
      child: Row(
        children: [
          Icon(icon, color: Colors.deepPurple, size: 18),
          const SizedBox(width: 12),
          Text(template.name,
              style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBranchSelector(
      UserScopeService userScope, BranchFilterService branchFilter) {
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
          style: const TextStyle(
              color: Colors.deepPurple,
              fontWeight: FontWeight.bold,
              fontSize: 13),
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
    _open = widget.initialData['open'] ??
        widget.initialData['startTime'] ??
        '09:00';
    _close =
        widget.initialData['close'] ?? widget.initialData['endTime'] ?? '22:00';
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
              style: TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5),
            ),
            const SizedBox(height: 24),
            _buildTimePicker(
                'START TIME', _open, (v) => setState(() => _open = v)),
            const SizedBox(height: 16),
            _buildTimePicker(
                'END TIME', _close, (v) => setState(() => _close = v)),
            const SizedBox(height: 24),
            _buildCounter(
                'STAFF ON DUTY', _staff, (v) => setState(() => _staff = v)),
            const SizedBox(height: 16),
            _buildCounter('REQUIRED STAFF', _required,
                (v) => setState(() => _required = v)),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL',
                        style: TextStyle(
                            color: Colors.grey, fontWeight: FontWeight.bold)),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('SAVE CHANGES',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(
      String label, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final time = TimeOfDay(
                hour: int.parse(value.split(':')[0]),
                minute: int.parse(value.split(':')[1]));
            final picked =
                await showTimePicker(context: context, initialTime: time);
            if (picked != null) {
              onChanged(
                  '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
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
                Text(value,
                    style: const TextStyle(
                        color: Colors.black87, fontWeight: FontWeight.bold)),
                const Icon(Icons.access_time,
                    color: Colors.deepPurple, size: 18),
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
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        Row(
          children: [
            _counterButton(
                Icons.remove, () => onChanged(value > 0 ? value - 1 : 0)),
            const SizedBox(width: 16),
            Text(value.toString().padLeft(2, '0'),
                style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
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
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late DateTime _date;
  late String _type;
  late String _open;
  late String _close;
  late bool _openAllDay;

  @override
  void initState() {
    super.initState();
    _name = widget.initialData['name'] ?? '';
    _date = widget.initialData['date'] is DateTime
        ? widget.initialData['date']
        : (widget.initialData['date'] as Timestamp).toDate();
    _type = widget.initialData['type'] ?? 'Fully Closed';
    final initialSlots = List<Map<String, dynamic>>.from(
        widget.initialData['slots'] ?? const []);
    final initialOpen = widget.initialData['open'] as String?;
    final initialClose = widget.initialData['close'] as String?;
    _open = (initialSlots.isNotEmpty ? initialSlots.first['open'] : initialOpen)
            as String? ??
        '09:00';
    _close = (initialSlots.isNotEmpty
            ? initialSlots.first['close']
            : initialClose) as String? ??
        '22:00';
    _openAllDay = widget.initialData['forceOpen'] == true ||
        widget.initialData['isOpenAllDay'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'HOLIDAY EXCEPTION',
                style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 24),
              _buildTextField('EXCEPTION NAME', _name, (v) => _name = v),
              const SizedBox(height: 16),
              _buildDatePicker('DATE', _date, (v) => setState(() => _date = v)),
              const SizedBox(height: 16),
              _buildDropdown(
                  'TYPE',
                  _type,
                  ['Fully Closed', 'Short Hours', 'Special Event'],
                  (v) => setState(() => _type = v!)),
              if (_type != 'Fully Closed') ...[
                const SizedBox(height: 16),
                if (_type == 'Special Event')
                  SwitchListTile.adaptive(
                    value: _openAllDay,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Open all day',
                      style: TextStyle(
                          color: Colors.black87, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Disable to set a custom event window',
                      style: TextStyle(fontSize: 12),
                    ),
                    onChanged: (value) => setState(() => _openAllDay = value),
                    activeColor: Colors.deepPurple,
                  ),
                if (!(_type == 'Special Event' && _openAllDay)) ...[
                  const SizedBox(height: 8),
                  _buildTimePicker(
                    'START TIME',
                    _open,
                    (value) => setState(() => _open = value),
                  ),
                  const SizedBox(height: 16),
                  _buildTimePicker(
                    'END TIME',
                    _close,
                    (value) => setState(() => _close = value),
                  ),
                ],
              ],
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL',
                          style: TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() != true) {
                          return;
                        }
                        final payload = <String, dynamic>{
                          'name': _name.trim(),
                          'date': Timestamp.fromDate(_date),
                          'type': _type,
                        };

                        if (_type == 'Short Hours') {
                          payload['slots'] = [
                            {'open': _open, 'close': _close}
                          ];
                        } else if (_type == 'Special Event') {
                          if (_openAllDay) {
                            payload['forceOpen'] = true;
                            payload['isOpenAllDay'] = true;
                          } else {
                            payload['slots'] = [
                              {'open': _open, 'close': _close}
                            ];
                          }
                        }

                        Navigator.pop(context, {
                          ...payload,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('SAVE EXCEPTION',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      String label, String initialValue, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: initialValue,
          onChanged: onChanged,
          style: const TextStyle(
              color: Colors.black87, fontWeight: FontWeight.bold),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Name is required';
            }
            return null;
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(
      String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
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
                Text(DateFormat('MMM dd, yyyy').format(value),
                    style: const TextStyle(
                        color: Colors.black87, fontWeight: FontWeight.bold)),
                const Icon(Icons.calendar_today,
                    color: Colors.deepPurple, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options,
      ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF94a3b8),
                fontSize: 10,
                fontWeight: FontWeight.bold)),
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
            items: options
                .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(o,
                        style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold))))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildTimePicker(
      String label, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final parts = value.split(':');
            final initialTime = TimeOfDay(
              hour: int.tryParse(parts.first) ?? 9,
              minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
            );
            final picked = await showTimePicker(
              context: context,
              initialTime: initialTime,
            );
            if (picked != null) {
              onChanged(
                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.access_time,
                    color: Colors.deepPurple, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChangeLogDialog extends StatefulWidget {
  final String branchId;
  const ChangeLogDialog({super.key, required this.branchId});

  @override
  State<ChangeLogDialog> createState() => _ChangeLogDialogState();
}

class _ChangeLogDialogState extends State<ChangeLogDialog> {
  late Stream<QuerySnapshot> _logStream;

  @override
  void initState() {
    super.initState();
    _logStream = FirebaseFirestore.instance
        .collection(AppConstants.collectionBranch)
        .doc(widget.branchId)
        .collection('changeLogs')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Timing Change Logs',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple)),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _logStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                    return const Center(
                        child: Text('No change logs found.',
                            style: TextStyle(color: Colors.grey)));
                  return ListView.separated(
                    itemCount: snapshot.data!.docs.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final data = snapshot.data!.docs[index].data()
                          as Map<String, dynamic>;
                      final desc =
                          data['description'] ?? 'System configuration updated';
                      final user = data['usedBy'] ??
                          data['user'] ??
                          'System'; // Fixed typo in previous implementation mapping?
                      final ts = data['timestamp'] as Timestamp?;
                      final dateStr = ts != null
                          ? DateFormat('MMM dd, yyyy HH:mm').format(ts.toDate())
                          : 'Unknown Date';
                      return ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: Colors.deepPurple,
                            child: Icon(Icons.history,
                                color: Colors.white, size: 18)),
                        title: Text(desc, style: const TextStyle(fontSize: 14)),
                        subtitle: Text('By $user on $dateStr',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
