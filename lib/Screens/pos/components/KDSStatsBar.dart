// lib/Screens/pos/components/KDSStatsBar.dart
// Real-time stats summary bar for KDS

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../constants.dart';
import 'kds_constants.dart';

class KDSStatsBar extends StatelessWidget {
  final bool isDark;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> activeOrders;

  const KDSStatsBar({
    super.key,
    required this.isDark,
    required this.activeOrders,
  });

  @override
  Widget build(BuildContext context) {
    // Compute stats
    int pending = 0, preparing = 0, ready = 0, delayed = 0;
    double totalPrepMinutes = 0;
    int prepCount = 0;
    final Map<String, int> bySource = {};

    for (final doc in activeOrders) {
      final data = doc.data();
      final status = data['status']?.toString() ?? '';
      final source = (data['source']?.toString() ?? 'app').toLowerCase();

      if (status == AppConstants.statusPending) pending++;
      if (status == AppConstants.statusPreparing) preparing++;
      if (status == AppConstants.statusPrepared || status == AppConstants.statusServed) ready++;

      // Elapsed time
      final ts = data['timestamp'] as Timestamp?;
      if (ts != null) {
        final elapsed = DateTime.now().difference(ts.toDate()).inMinutes;
        if (elapsed >= KDSConfig.lateMinutes) delayed++;
        if (status == AppConstants.statusPreparing) {
          totalPrepMinutes += elapsed;
          prepCount++;
        }
      }

      // Source counts
      bySource[source] = (bySource[source] ?? 0) + 1;
    }

    final avgPrepTime = prepCount > 0 ? (totalPrepMinutes / prepCount).round() : 0;
    final total = activeOrders.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16213e) : Colors.white,
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatChip('Total', total.toString(), Colors.deepPurple),
            const SizedBox(width: 8),
            _buildStatChip('New', pending.toString(), Colors.blue),
            const SizedBox(width: 8),
            _buildStatChip('Cooking', preparing.toString(), Colors.orange),
            const SizedBox(width: 8),
            _buildStatChip('Ready', ready.toString(), Colors.green),
            const SizedBox(width: 12),
            Container(
              width: 1,
              height: 24,
              color: isDark ? Colors.white12 : Colors.grey[300],
            ),
            const SizedBox(width: 12),
            _buildStatChip('Avg Prep', '${avgPrepTime}m', Colors.teal),
            const SizedBox(width: 8),
            if (delayed > 0) ...[
              _buildStatChip('Delayed', delayed.toString(), Colors.red, isAlert: true),
              const SizedBox(width: 12),
            ],
            if (bySource.isNotEmpty) ...[
              Container(
                width: 1,
                height: 24,
                color: isDark ? Colors.white12 : Colors.grey[300],
              ),
              const SizedBox(width: 12),
              ...bySource.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildSourceChip(e.key, e.value),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color, {bool isAlert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isAlert ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: isAlert ? Border.all(color: color, width: 1.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(String source, int count) {
    final color = KDSConfig.getSourceColor(source);
    final label = KDSConfig.getSourceLabel(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(KDSConfig.getSourceIcon(source), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
