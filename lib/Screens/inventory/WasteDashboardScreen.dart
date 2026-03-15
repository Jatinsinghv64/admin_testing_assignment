import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/WasteService.dart';
import 'WasteEntryScreenLarge.dart';
import 'WasteHistoryScreen.dart';

// ─── Theme Colors (deepPurple-based to match app theme) ─────────────────────
class _WColors {
  static final Color bgDark       = Colors.grey.shade50;
  static const Color surfaceDark  = Colors.white;
  static final Color borderDark   = Colors.grey.shade200;
  static final Color primary      = Colors.deepPurple;
  static final Color primaryLight = Colors.deepPurple.shade300;
  static const Color textMain     = Color(0xFF1E293B);
  static const Color textMuted    = Color(0xFF64748B);
}

class WasteDashboardScreen extends StatefulWidget {
  const WasteDashboardScreen({super.key});

  @override
  State<WasteDashboardScreen> createState() => _WasteDashboardScreenState();
}

class _WasteDashboardScreenState extends State<WasteDashboardScreen> {
  late final WasteService _service;
  bool _serviceInitialized = false;
  String _trendMode = 'daily';
  String _datePreset = 'this_month'; // Default to this month for dashboard
  DateTimeRange? _range;

  void _applyDatePreset(String preset) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (preset == 'all') {
      setState(() {
        _datePreset = preset;
        _range = null; // No range means all time
      });
    } else if (preset == 'this_month') {
      setState(() {
        _datePreset = preset;
        _range = DateTimeRange(start: DateTime(now.year, now.month, 1), end: todayEnd);
      });
    } else if (preset == 'today') {
      setState(() {
        _datePreset = preset;
        _range = DateTimeRange(start: todayStart, end: todayEnd);
      });
    } else if (preset == 'last7') {
      setState(() {
        _datePreset = preset;
        _range = DateTimeRange(start: todayStart.subtract(const Duration(days: 6)), end: todayEnd);
      });
    } else if (preset == 'last30') {
      setState(() {
        _datePreset = preset;
        _range = DateTimeRange(start: todayStart.subtract(const Duration(days: 29)), end: todayEnd);
      });
    } else if (preset == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: now.subtract(const Duration(days: 365)),
        lastDate: now.add(const Duration(days: 365)),
        initialDateRange: _range,
      );
      if (picked != null) {
        setState(() {
          _datePreset = preset;
          _range = picked;
        });
      } else {
        // User cancelled, keep previous preset or revert to this_month
        if (_range == null) {
           setState(() => _datePreset = 'all');
        } else {
           setState(() => _datePreset = 'custom');
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _service = Provider.of<WasteService>(context, listen: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamWasteEntries(branchIds,
          limit: 400, isSuperAdmin: userScope.isSuperAdmin),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: _WColors.primary),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load waste data: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final entries = snapshot.data ?? [];
        final now = DateTime.now();
        DateTime startCurrent = DateTime(now.year, now.month, 1);
        DateTime endCurrent = DateTime(now.year, now.month, now.day, 23, 59, 59);
        
        // Define baseline ranges
        if (_range != null) {
          startCurrent = _range!.start;
          endCurrent = _range!.end;
        } else if (_datePreset == 'all') {
           // For 'all time', let's say "startCurrent" is 10 years ago so everything matches current period
           startCurrent = DateTime(now.year - 10);
        }

        // Calculate a 'previous' period of equal length for comparison Delta
        final rangeDurationDays = endCurrent.difference(startCurrent).inDays > 0 ? endCurrent.difference(startCurrent).inDays : 1;
        final endPrev = startCurrent.subtract(const Duration(seconds: 1));
        final startPrev = endPrev.subtract(Duration(days: rangeDurationDays));

        final currentWindow = entries.where((e) {
          final dt = (e['wasteDate'] as Timestamp?)?.toDate();
          if (dt == null) return false;
          return !dt.isBefore(startCurrent) && !dt.isAfter(endCurrent);
        }).toList();
        
        final prevWindow = entries.where((e) {
          final dt = (e['wasteDate'] as Timestamp?)?.toDate();
          if (dt == null) return false;
          return !dt.isBefore(startPrev) && !dt.isAfter(endPrev);
        }).toList();

        final currentLoss = _sumLoss(currentWindow);
        final prevLoss = _sumLoss(prevWindow);
        final deltaPct = prevLoss == 0
            ? 0.0
            : (((currentLoss - prevLoss) / prevLoss) * 100).toDouble();
        final reasonBreakdown = _groupByReason(currentWindow);
        final trendPoints = _buildTrendData(currentWindow, mode: _trendMode);
        final topItems = _topItems(currentWindow);
        final recent = entries.where((e) {
           final dt = (e['wasteDate'] as Timestamp?)?.toDate();
           if (dt == null) return false;
           return !dt.isBefore(startCurrent) && !dt.isAfter(endCurrent);
        }).take(5).toList();

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ─── Title ───────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _WColors.surfaceDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.analytics_outlined, color: _WColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Waste Management & Analytics',
                        style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900, color: _WColors.textMain,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Track food waste, monitor costs, and optimize kitchen efficiency.',
                        style: TextStyle(fontSize: 12, color: _WColors.textMuted),
                      ),
                    ],
                  ),
                ),
                // --- Dashboard Date Filter ---
                Container(
                  width: 170,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _WColors.borderDark),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _datePreset,
                      isExpanded: true,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      style: const TextStyle(fontSize: 13, color: _WColors.textMain, fontWeight: FontWeight.w500),
                      items: const [
                        DropdownMenuItem(value: 'this_month', child: Text('This Month')),
                        DropdownMenuItem(value: 'today', child: Text('Today')),
                        DropdownMenuItem(value: 'last7', child: Text('Last 7 Days')),
                        DropdownMenuItem(value: 'last30', child: Text('Last 30 Days')),
                        DropdownMenuItem(value: 'all', child: Text('All Time')),
                        DropdownMenuItem(value: 'custom', child: Text('Custom Range')),
                      ],
                      onChanged: (v) => _applyDatePreset(v ?? 'this_month'),
                    ),
                  ),
                ),
                if (_datePreset == 'custom' && _range != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${_range!.start.toLocal().toString().split(' ').first}\n${_range!.end.toLocal().toString().split(' ').first}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // ─── KPI Cards ───────────────────────────────────────
            _kpiRow(currentLoss: currentLoss, deltaPct: deltaPct, count: currentWindow.length),
            const SizedBox(height: 20),

            // ─── Recent Entries Table ────────────────────────────
            _card(
              title: 'Recent Waste Entries',
              trailing: TextButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const WasteHistoryScreen()),
                ),
                child: Text('View All History', style: TextStyle(color: _WColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              child: recent.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No recent waste entries.', style: TextStyle(color: _WColors.textMuted)),
                    )
                  : Column(
                      children: recent.map((e) {
                        final qty = (e['quantity'] as num?)?.toDouble() ?? 0.0;
                        final loss = (e['estimatedLoss'] as num?)?.toDouble() ?? 0.0;
                        final dt = (e['wasteDate'] as Timestamp?)?.toDate();
                        final reason = (e['reason'] ?? '').toString();
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: _WColors.borderDark.withOpacity(0.6)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (e['itemName'] ?? '').toString(),
                                      style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w600, color: _WColors.textMain,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dt?.toLocal().toString().split('.').first ?? '-',
                                      style: const TextStyle(fontSize: 11, color: _WColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${qty.toStringAsFixed(1)}',
                                  style: const TextStyle(fontSize: 13, color: _WColors.textMain),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: _reasonBadge(reason),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'QAR ${loss.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold, color: _WColors.textMain,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 20),

            // ─── Charts Row ─────────────────────────────────────
            LayoutBuilder(builder: (ctx, constraints) {
              final isWide = constraints.maxWidth > 700;
              final trendChart = _card(
                title: 'Waste Trend Analysis',
                trailing: _trendModePills(),
                child: trendPoints.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No trend data.', style: TextStyle(color: _WColors.textMuted)),
                      )
                    : SizedBox(
                        height: 240,
                        child: SfCartesianChart(
                          plotAreaBorderWidth: 0,
                          primaryXAxis: CategoryAxis(
                            labelStyle: const TextStyle(color: _WColors.textMuted, fontSize: 10),
                            majorGridLines: const MajorGridLines(width: 0),
                            axisLine: AxisLine(color: _WColors.borderDark),
                          ),
                          primaryYAxis: NumericAxis(
                            labelStyle: const TextStyle(color: _WColors.textMuted, fontSize: 10),
                            majorGridLines: MajorGridLines(
                              color: _WColors.borderDark.withOpacity(0.5),
                              dashArray: const [4, 4],
                            ),
                            axisLine: const AxisLine(width: 0),
                          ),
                          series: <CartesianSeries>[
                            ColumnSeries<_TrendPoint, String>(
                              dataSource: trendPoints,
                              xValueMapper: (p, _) => p.label,
                              yValueMapper: (p, _) => p.value,
                              color: _WColors.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              width: 0.6,
                            ),
                          ],
                        ),
                      ),
              );

              final reasonChart = _card(
                title: 'Waste Reasons',
                child: reasonBreakdown.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No data this month.', style: TextStyle(color: _WColors.textMuted)),
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 200,
                            child: SfCircularChart(
                              margin: EdgeInsets.zero,
                              legend: Legend(
                                isVisible: true,
                                position: LegendPosition.bottom,
                                textStyle: const TextStyle(color: _WColors.textMuted, fontSize: 11),
                              ),
                              series: <CircularSeries>[
                                DoughnutSeries<_ReasonPoint, String>(
                                  dataSource: reasonBreakdown,
                                  xValueMapper: (p, _) => p.reason,
                                  yValueMapper: (p, _) => p.value,
                                  innerRadius: '65%',
                                  pointColorMapper: (p, i) => _reasonColor(i),
                                  dataLabelSettings: DataLabelSettings(
                                    isVisible: true,
                                    textStyle: const TextStyle(color: Colors.white, fontSize: 10),
                                    labelPosition: ChartDataLabelPosition.outside,
                                    connectorLineSettings: ConnectorLineSettings(
                                      color: _WColors.borderDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: trendChart),
                    const SizedBox(width: 16),
                    Expanded(flex: 1, child: reasonChart),
                  ],
                );
              }
              return Column(
                children: [trendChart, const SizedBox(height: 16), reasonChart],
              );
            }),
            const SizedBox(height: 20),

            // ─── Top Wasted Items ────────────────────────────────
            _card(
              title: 'Top Wasted Items',
              child: topItems.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No items this month.', style: TextStyle(color: _WColors.textMuted)),
                    )
                  : Column(
                      children: topItems.asMap().entries.map((entry) {
                        final e = entry.value;
                        final idx = entry.key;
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: idx < topItems.length - 1
                                ? Border(bottom: BorderSide(color: _WColors.borderDark.withOpacity(0.5)))
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28, height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _WColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    color: _WColors.primary, fontWeight: FontWeight.bold, fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  e.itemName,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _WColors.textMain),
                                ),
                              ),
                              Text(
                                '${e.quantity.toStringAsFixed(1)}',
                                style: const TextStyle(fontSize: 12, color: _WColors.textMuted),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                'QAR ${e.loss.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 20),

            // ─── Bottom Actions ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(builder: (_) => const WasteHistoryScreen()),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _WColors.borderDark),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 18, color: _WColors.textMain),
                            SizedBox(width: 8),
                            Text('View History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _WColors.textMain)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(builder: (_) => const WasteEntryScreenLarge()),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _WColors.primary,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: _WColors.primary.withOpacity(0.3), blurRadius: 12)],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded, size: 18, color: _WColors.bgDark),
                            SizedBox(width: 8),
                            Text('Log Waste', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _WColors.bgDark)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  Widget _trendModePills() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ['daily', 'weekly', 'monthly'].map((mode) {
        final sel = _trendMode == mode;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: GestureDetector(
            onTap: () => setState(() => _trendMode = mode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? _WColors.primary.withOpacity(0.15) : _WColors.bgDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? _WColors.primary.withOpacity(0.4) : _WColors.borderDark,
                ),
              ),
              child: Text(
                mode[0].toUpperCase() + mode.substring(1),
                style: TextStyle(
                  fontSize: 11,
                  color: sel ? _WColors.primary : _WColors.textMuted,
                  fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _reasonBadge(String reason) {
    Color color;
    switch (reason.toLowerCase()) {
      case 'expired / spoilage':
      case 'expired':
      case 'spoilage':
        color = Colors.red;
        break;
      case 'preparation error':
      case 'prep error':
        color = Colors.orange;
        break;
      case 'spilled / dropped':
      case 'spilled':
        color = Colors.blue;
        break;
      case 'customer return':
        color = Colors.amber;
        break;
      default:
        color = _WColors.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        reason,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Color _reasonColor(int index) {
    final palette = [Colors.deepPurple, Colors.deepPurple.shade300, const Color(0xFF25254A), Colors.red, Colors.orange];
    return palette[index % palette.length];
  }

  Widget _kpiRow({
    required double currentLoss,
    required double deltaPct,
    required int count,
  }) {
    final improving = deltaPct <= 0;
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            title: 'This Month Loss',
            value: 'QAR ${currentLoss.toStringAsFixed(2)}',
            subtitle: '${improving ? '↓' : '↑'} ${deltaPct.abs().toStringAsFixed(1)}% vs last month',
            color: improving ? Colors.green : Colors.red,
            icon: Icons.trending_down,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            title: 'Waste Count',
            value: '$count',
            subtitle: 'Entries this month',
            color: _WColors.primary,
            icon: Icons.delete_outline,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _WColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _WColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: _WColors.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: _WColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _WColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _WColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _WColors.textMain),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  double _sumLoss(List<Map<String, dynamic>> entries) {
    return entries.fold<double>(
      0,
      (acc, e) => acc + ((e['estimatedLoss'] as num?)?.toDouble() ?? 0.0),
    );
  }

  List<_ReasonPoint> _groupByReason(List<Map<String, dynamic>> entries) {
    final map = <String, double>{};
    for (final e in entries) {
      final reason = (e['reason'] ?? 'other').toString();
      final loss = (e['estimatedLoss'] as num?)?.toDouble() ?? 0.0;
      map[reason] = (map[reason] ?? 0) + loss;
    }
    return map.entries.map((e) => _ReasonPoint(e.key, e.value)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  List<_TrendPoint> _buildTrendData(
    List<Map<String, dynamic>> entries, {
    required String mode,
  }) {
    final map = <String, double>{};
    for (final e in entries) {
      final dt = (e['wasteDate'] as Timestamp?)?.toDate();
      if (dt == null) continue;
      final key = switch (mode) {
        'weekly' => '${dt.year}-W${((dt.day - 1) / 7).floor() + 1}',
        'monthly' => '${dt.year}-${dt.month.toString().padLeft(2, '0')}',
        _ =>
          '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}',
      };
      final loss = (e['estimatedLoss'] as num?)?.toDouble() ?? 0.0;
      map[key] = (map[key] ?? 0) + loss;
    }
    return map.entries.map((e) => _TrendPoint(e.key, e.value)).toList()
      ..sort((a, b) => a.label.compareTo(b.label));
  }

  List<_TopItem> _topItems(List<Map<String, dynamic>> entries) {
    final qtyMap = <String, double>{};
    final lossMap = <String, double>{};
    for (final e in entries) {
      final item = (e['itemName'] ?? '').toString();
      final qty = (e['quantity'] as num?)?.toDouble() ?? 0.0;
      final loss = (e['estimatedLoss'] as num?)?.toDouble() ?? 0.0;
      qtyMap[item] = (qtyMap[item] ?? 0) + qty;
      lossMap[item] = (lossMap[item] ?? 0) + loss;
    }
    final all = qtyMap.keys
        .map((k) => _TopItem(k, qtyMap[k] ?? 0, lossMap[k] ?? 0))
        .toList()
      ..sort((a, b) => b.loss.compareTo(a.loss));
    return all.take(5).toList();
  }
}

class _ReasonPoint {
  final String reason;
  final double value;
  _ReasonPoint(this.reason, this.value);
}

class _TrendPoint {
  final String label;
  final double value;
  _TrendPoint(this.label, this.value);
}

class _TopItem {
  final String itemName;
  final double quantity;
  final double loss;
  _TopItem(this.itemName, this.quantity, this.loss);
}
