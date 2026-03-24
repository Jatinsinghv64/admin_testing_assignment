import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/staff/staff_service.dart';
import '../main.dart'; // For UserScopeService

class MyTimeClockWidget extends StatefulWidget {
  const MyTimeClockWidget({Key? key}) : super(key: key);

  @override
  State<MyTimeClockWidget> createState() => _MyTimeClockWidgetState();
}

class _MyTimeClockWidgetState extends State<MyTimeClockWidget> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  DateTime? _clockInTime;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(DateTime clockIn) {
    if (_clockInTime == clockIn && _timer != null && _timer!.isActive) return;
    
    _timer?.cancel();
    _clockInTime = clockIn;
    // Update variable directly without setState to avoid "setState during build" error
    _elapsed = DateTime.now().difference(_clockInTime!);
    
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateElapsed();
    });
  }

  void _updateElapsed() {
    if (_clockInTime != null && mounted) {
      setState(() {
        _elapsed = DateTime.now().difference(_clockInTime!);
      });
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final staffService = context.watch<StaffService>();

    if (!userScope.isLoaded) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      // Filter the global branch-level stream for this user specifically in the builder
      stream: staffService.getTodayAttendanceStream(
        branchIds: userScope.branchIds, 
        staffId: userScope.userIdentifier,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        // The stream is now filtered by staffId in the service, 
        // but we still check for clockOut == null to find the active session.
        DocumentSnapshot? activeRecord;
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['clockOut'] == null) {
            activeRecord = doc;
            break;
          }
        }

        if (activeRecord != null) {
          // Clocked in
          final data = activeRecord.data() as Map<String, dynamic>;
          final clockInTimestamp = data['clockIn'] as Timestamp?;
          
          if (clockInTimestamp != null) {
            _startTimer(clockInTimestamp.toDate());
          }

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer, color: Colors.red, size: 16),
                const SizedBox(width: 6),
                Text(
                  _formatDuration(_elapsed),
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _confirmClockOut(context, staffService, activeRecord!.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('CLOCK OUT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        } else {
          // Not clocked in
          _timer?.cancel();
          _timer = null;
          
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  await staffService.clockIn(
                    staffId: userScope.userIdentifier,
                    staffEmail: userScope.userEmail,
                    staffName: userScope.isSuperAdmin ? 'Super Admin' : userScope.userEmail.isNotEmpty ? userScope.userEmail.split('@').first : userScope.userIdentifier,
                    branchIds: userScope.branchIds,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('CLOCK IN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
      },
    );
  }

  void _confirmClockOut(BuildContext context, StaffService staffService, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clock Out?'),
        content: const Text('Are you sure you want to clock out for today?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await staffService.clockOut(docId);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clock Out'),
          ),
        ],
      ),
    );
  }
}
