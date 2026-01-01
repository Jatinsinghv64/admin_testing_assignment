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
  Map<String, dynamic> _workingHours = {};
  final List<String> _days = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
  ];

  @override
  void initState() {
    super.initState();
    _loadTimings();
  }

  Future<void> _loadTimings() async {
    final userScope = context.read<UserScopeService>();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Branch')
          .doc(userScope.branchId)
          .get();

      if (doc.exists && doc.data()!.containsKey('workingHours')) {
        setState(() {
          _workingHours = Map<String, dynamic>.from(doc.data()!['workingHours']);
          _isLoading = false;
        });
      } else {
        // Initialize default structure if missing
        setState(() {
          for (var day in _days) {
            _workingHours[day] = {'isOpen': true, 'slots': []};
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading timings: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTimings() async {
    setState(() => _isLoading = true);
    final userScope = context.read<UserScopeService>();
    try {
      await FirebaseFirestore.instance
          .collection('Branch')
          .doc(userScope.branchId)
          .set({'workingHours': _workingHours}, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Timings updated successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // Go back after saving
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error saving: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<TimeOfDay?> _pickTime(String? initialTime) async {
    TimeOfDay initial = const TimeOfDay(hour: 9, minute: 0);
    if (initialTime != null) {
      final parts = initialTime.split(':');
      initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    return showTimePicker(context: context, initialTime: initial);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _addSlot(String day) {
    setState(() {
      List slots = List.from(_workingHours[day]['slots'] ?? []);
      slots.add({'open': '09:00', 'close': '22:00'});
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

  void _updateSlot(String day, int index, String key, String value) {
    setState(() {
      _workingHours[day]['slots'][index][key] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Timings', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.deepPurple),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveTimings,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _days.length,
        itemBuilder: (context, index) {
          final day = _days[index];
          final dayData = _workingHours[day] ?? {'isOpen': false, 'slots': []};
          final isOpen = dayData['isOpen'] ?? false;
          final List slots = dayData['slots'] ?? [];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              title: Text(day.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Switch(
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
                  ...slots.asMap().entries.map((entry) {
                    final i = entry.key;
                    final slot = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          _TimeButton(
                            time: slot['open'],
                            onTap: () async {
                              final t = await _pickTime(slot['open']);
                              if (t != null) _updateSlot(day, i, 'open', _formatTime(t));
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('to'),
                          ),
                          _TimeButton(
                            time: slot['close'],
                            onTap: () async {
                              final t = await _pickTime(slot['close']);
                              if (t != null) _updateSlot(day, i, 'close', _formatTime(t));
                            },
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeSlot(day, i),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  TextButton.icon(
                    onPressed: () => _addSlot(day),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Shift'),
                  ),
                  const SizedBox(height: 8),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Closed on this day', style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String time;
  final VoidCallback onTap;
  const _TimeButton({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(time, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}