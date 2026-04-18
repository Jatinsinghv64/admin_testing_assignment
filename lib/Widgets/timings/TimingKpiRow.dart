import 'package:flutter/material.dart';

class TimingKpiRow extends StatelessWidget {
  final String projectedLaborCost;
  final String laborEfficiency;
  final int shiftConflicts;
  final int scheduleCoverage;

  const TimingKpiRow({
    super.key,
    required this.projectedLaborCost,
    required this.laborEfficiency,
    required this.shiftConflicts,
    required this.scheduleCoverage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildKpiCard(
          context: context,
          title: 'Projected Labor Cost',
          value: 'QAR $projectedLaborCost',
          subtitle: 'Estimated today',
          icon: Icons.payments,
          color: Colors.deepPurple,
        ),
        const SizedBox(width: 24),
        _buildKpiCard(
          context: context,
          title: 'Labor Efficiency',
          value: '$laborEfficiency%',
          subtitle: 'Revenue vs Cost',
          icon: Icons.trending_up,
          color: Colors.blue,
        ),
        const SizedBox(width: 24),
        _buildKpiCard(
          context: context,
          title: 'Shift Conflicts',
          value: shiftConflicts.toString(),
          subtitle: 'Overlaps detected',
          icon: Icons.warning_amber_rounded,
          color: shiftConflicts > 0 ? Colors.orange : Colors.grey,
        ),
        const SizedBox(width: 24),
        _buildKpiCard(
          context: context,
          title: 'Schedule Coverage',
          value: '$scheduleCoverage%',
          subtitle: 'Operational uptime',
          icon: Icons.verified_user,
          color: scheduleCoverage > 80 ? Colors.deepPurple : Colors.orange,
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.labelSmall?.copyWith(color: Colors.grey[400], fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
