import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Ensure this points to your UserScopeService

class RestaurantTimingScreen extends StatefulWidget {
  const RestaurantTimingScreen({super.key});

  @override
  State<RestaurantTimingScreen> createState() => _RestaurantTimingScreenState();
}

class _RestaurantTimingScreenState extends State<RestaurantTimingScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _workingHours = {};

  // ✅ SuperAdmin branch selection
  String? _selectedBranchId;
  List<Map<String, dynamic>> _allBranches = [];
  bool _isSuperAdmin = false;

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

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  // --- Initialization ---

  Future<void> _initializeScreen() async {
    final userScope = context.read<UserScopeService>();
    // Only use multi-branch mode if SuperAdmin has more than 1 branch assigned
    _isSuperAdmin = userScope.isSuperAdmin && userScope.branchIds.length > 1;

    if (_isSuperAdmin) {
      // Load only assigned branches for SuperAdmin with multiple branches
      await _loadAssignedBranches(userScope.branchIds);
    } else {
      // Regular user OR SuperAdmin with single branch - use their primary branch
      _selectedBranchId = userScope.branchId;
      await _loadTimings();
    }
  }

  Future<void> _loadAssignedBranches(List<String> branchIds) async {
    try {
      final List<Map<String, dynamic>> loadedBranches = [];
      
      for (final branchId in branchIds) {
        final doc = await FirebaseFirestore.instance.collection('Branch').doc(branchId).get();
        if (doc.exists) {
          final data = doc.data()!;
          loadedBranches.add({
            'id': doc.id,
            'name': data['name'] ?? doc.id,
          });
        }
      }
      
      setState(() {
        _allBranches = loadedBranches;
        if (_allBranches.isNotEmpty) {
          _selectedBranchId = _allBranches.first['id'];
        }
      });

      if (_selectedBranchId != null) {
        await _loadTimings();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error loading assigned branches: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading branches: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAllBranches() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Branch').get();
      
      setState(() {
        _allBranches = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'] ?? doc.id,
          };
        }).toList();

        // Auto-select first branch if available
        if (_allBranches.isNotEmpty) {
          _selectedBranchId = _allBranches.first['id'];
        }
      });

      if (_selectedBranchId != null) {
        await _loadTimings();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error loading branches: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading branches: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // --- Data Loading ---

  Future<void> _loadTimings() async {
    if (_selectedBranchId == null || _selectedBranchId!.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('Branch')
          .doc(_selectedBranchId)
          .get();

      if (doc.exists && doc.data()!.containsKey('workingHours')) {
        setState(() {
          _workingHours = Map<String, dynamic>.from(doc.data()!['workingHours']);
          _isLoading = false;
        });
      } else {
        _initializeDefaultTimings();
      }
    } catch (e) {
      debugPrint("Error loading timings: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _initializeDefaultTimings() {
    setState(() {
      _workingHours = {};
      for (var day in _days) {
        _workingHours[day] = {
          'isOpen': true,
          'slots': [
            {'open': '09:00', 'close': '22:00'}
          ]
        };
      }
      _isLoading = false;
    });
  }

  // --- Actions & Logic ---

  Future<void> _saveTimings() async {
    if (_selectedBranchId == null || _selectedBranchId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Error: No Branch selected'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);
    
    try {
      await FirebaseFirestore.instance
          .collection('Branch')
          .doc(_selectedBranchId)
          .set({'workingHours': _workingHours}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        final branchName = _allBranches.firstWhere(
          (b) => b['id'] == _selectedBranchId,
          orElse: () => {'name': _selectedBranchId},
        )['name'];

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

  /// Copies Monday's schedule to all other days
  void _copyMondayToAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply to All Days?'),
        content: const Text(
            'This will overwrite all other days with Monday\'s schedule. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                final mondayData = _workingHours['monday'];
                for (var day in _days) {
                  if (day != 'monday') {
                    _workingHours[day] = {
                      'isOpen': mondayData['isOpen'],
                      'slots': List.from((mondayData['slots'] as List).map((s) => Map.from(s))),
                    };
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
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
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
    setState(() {
      List slots = List.from(_workingHours[day]['slots']);
      slots.removeAt(index);
      _workingHours[day]['slots'] = slots;
    });
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Restaurant Timings',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (!_isLoading && _selectedBranchId != null)
            TextButton.icon(
              onPressed: _isSaving ? null : _saveTimings,
              icon: _isSaving
                  ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle, color: Colors.green),
              label: Text(_isSaving ? 'Saving...' : 'Save',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // ✅ Branch selector only for SuperAdmin with multiple branches
          if (_isSuperAdmin && _allBranches.length > 1) _buildBranchSelector(),
          if (_selectedBranchId != null) ...[
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
      ),
    );
  }

  // ✅ NEW: Branch selector dropdown for SuperAdmin
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
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
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
                  onChanged: (String? newValue) {
                    if (newValue != null && newValue != _selectedBranchId) {
                      setState(() {
                        _selectedBranchId = newValue;
                        _workingHours = {};
                      });
                      _loadTimings();
                    }
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              });
            },
          ),
          children: [
            if (isOpen) ...[
              const Divider(height: 1),
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
                return _buildSlotRow(day, index, slot);
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

  Widget _buildSlotRow(String day, int index, Map slot) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.access_time_filled, size: 18, color: Colors.deepPurple),
          const SizedBox(width: 12),
          Expanded(
            child: _TimeChip(
              label: "Open",
              time: _formatTimeForDisplay(context, slot['open']),
              onTap: () => _pickTime(day, index, 'open', slot['open']),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
          ),
          Expanded(
            child: _TimeChip(
              label: "Close",
              time: _formatTimeForDisplay(context, slot['close']),
              onTap: () => _pickTime(day, index, 'close', slot['close']),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _removeSlot(day, index),
            tooltip: "Remove Shift",
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