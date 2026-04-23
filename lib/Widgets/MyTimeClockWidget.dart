import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/BranchFilterService.dart';
import '../services/staff/staff_service.dart';
import '../main.dart'; // For UserScopeService

class MyTimeClockWidget extends StatefulWidget {
  const MyTimeClockWidget({super.key});

  @override
  State<MyTimeClockWidget> createState() => _MyTimeClockWidgetState();
}

class _MyTimeClockWidgetState extends State<MyTimeClockWidget> {
  Timer? _timer;
  DateTime? _clockInTime;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(DateTime clockIn) {
    if (_clockInTime == clockIn && _timer != null && _timer!.isActive) return;

    _timer?.cancel();
    _clockInTime = clockIn;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateElapsed();
    });
  }

  void _updateElapsed() {
    if (_clockInTime != null && mounted) {
      setState(() {});
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _clockInTime = null;
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  List<String> _resolveClockInBranchIds(
    UserScopeService userScope,
    BranchFilterService branchFilter,
  ) {
    final selectedBranchId = branchFilter.selectedBranchId;
    if (selectedBranchId != null &&
        userScope.branchIds.contains(selectedBranchId)) {
      return [selectedBranchId];
    }
    if (userScope.branchIds.isNotEmpty) {
      return [userScope.branchIds.first];
    }
    return const [];
  }

  Future<void> _handleClockIn(
    BuildContext context,
    StaffService staffService,
    UserScopeService userScope,
    BranchFilterService branchFilter,
  ) async {
    if (_isSubmitting) return;

    final clockInBranchIds = _resolveClockInBranchIds(userScope, branchFilter);
    if (clockInBranchIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No branch is assigned to this account.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await staffService.clockIn(
        staffId: userScope.userIdentifier,
        staffEmail: userScope.userEmail,
        staffName: userScope.isSuperAdmin
            ? 'Super Admin'
            : userScope.userEmail.isNotEmpty
                ? userScope.userEmail.split('@').first
                : userScope.userIdentifier,
        branchIds: clockInBranchIds,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleClockOut(
    BuildContext context,
    StaffService staffService,
    String docId,
  ) async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      await staffService.clockOut(docId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      key: ValueKey('time-clock-loading'),
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildClockOutChip(
    BuildContext context,
    StaffService staffService,
    String docId,
    Duration elapsed,
  ) {
    return Container(
      key: const ValueKey('time-clock-active'),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: Colors.red, size: 16),
          const SizedBox(width: 6),
          Text(
            _formatDuration(elapsed),
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _isSubmitting
                ? null
                : () => _confirmClockOut(context, staffService, docId),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'CLOCK OUT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClockInButton(
    BuildContext context,
    StaffService staffService,
    UserScopeService userScope,
    BranchFilterService branchFilter,
  ) {
    return Container(
      key: const ValueKey('time-clock-idle'),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: _isSubmitting
            ? null
            : () => _handleClockIn(
                  context,
                  staffService,
                  userScope,
                  branchFilter,
                ),
        icon: _isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.login, size: 16),
        label: Text(_isSubmitting ? 'CLOCKING IN...' : 'CLOCK IN'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final staffService = context.watch<StaffService>();
    final branchFilter = context.watch<BranchFilterService>();

    if (!userScope.isLoaded) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: staffService.getTodayAttendanceStream(
        staffId: userScope.userIdentifier,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoadingIndicator();
        }

        final docs = snapshot.data?.docs ?? const [];
        DocumentSnapshot? activeRecord;
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['clockIn'] != null && data['clockOut'] == null) {
            activeRecord = doc;
            break;
          }
        }

        if (activeRecord != null) {
          final data = activeRecord.data() as Map<String, dynamic>;
          final clockInTimestamp = data['clockIn'] as Timestamp?;
          if (clockInTimestamp != null) {
            final clockIn = clockInTimestamp.toDate();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _startTimer(clockIn);
              }
            });
            final elapsed = DateTime.now().difference(clockIn);
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _buildClockOutChip(
                context,
                staffService,
                activeRecord.id,
                elapsed,
              ),
            );
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _stopTimer();
        });

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _buildClockInButton(
            context,
            staffService,
            userScope,
            branchFilter,
          ),
        );
      },
    );
  }

  void _confirmClockOut(
      BuildContext context, StaffService staffService, String docId) {
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
              await _handleClockOut(context, staffService, docId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clock Out'),
          ),
        ],
      ),
    );
  }
}
