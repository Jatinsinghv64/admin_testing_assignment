// lib/Widgets/ExportReportDialog.dart
// Export Report Dialog — Date range, format (PDF/Excel), and report type selection

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../Widgets/BranchFilterService.dart';
import '../services/ExportReportService.dart';

class ExportReportDialog extends StatefulWidget {
  const ExportReportDialog({super.key});

  /// Show the export report dialog
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ExportReportDialog(),
    );
  }

  @override
  State<ExportReportDialog> createState() => _ExportReportDialogState();
}

class _ExportReportDialogState extends State<ExportReportDialog> {
  // Date range presets
  String _datePreset = 'today';
  DateTimeRange? _customRange;

  // Format
  String _format = 'pdf'; // 'pdf' or 'excel'

  // Report type
  String _reportType = 'sales_summary';

  bool _isGenerating = false;
  String? _error;

  DateTimeRange get _effectiveDateRange {
    if (_datePreset == 'custom' && _customRange != null) return _customRange!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_datePreset) {
      case 'yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: yesterday, end: today.subtract(const Duration(seconds: 1)));
      case 'this_week':
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(start: startOfWeek, end: now);
      case 'this_month':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case 'last_month':
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        final lastDay = DateTime(now.year, now.month, 0);
        return DateTimeRange(start: lastMonth, end: lastDay);
      case 'today':
      default:
        return DateTimeRange(start: today, end: now);
    }
  }

  final _reportTypes = const [
    {'key': 'sales_summary', 'label': 'Sales Summary', 'icon': Icons.summarize},
    {'key': 'order_details', 'label': 'Order Details', 'icon': Icons.list_alt},
    {'key': 'revenue_by_source', 'label': 'Revenue by Source', 'icon': Icons.pie_chart},
    {'key': 'revenue_by_branch', 'label': 'Revenue by Branch', 'icon': Icons.business},
    {'key': 'item_wise_sales', 'label': 'Item-wise Sales', 'icon': Icons.restaurant},
  ];

  @override
  Widget build(BuildContext context) {
    final branchFilter = context.read<BranchFilterService>();
    final branchLabel = branchFilter.selectedBranchId == null
        ? 'All Branches'
        : branchFilter.getBranchName(branchFilter.selectedBranchId!);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.file_download_outlined, color: Colors.deepPurple),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('Export Report', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Branch scope indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store, size: 16, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    Text(branchLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.deepPurple)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Date range
              const Text('Date Range', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPresetChip('Today', 'today'),
                  _buildPresetChip('Yesterday', 'yesterday'),
                  _buildPresetChip('This Week', 'this_week'),
                  _buildPresetChip('This Month', 'this_month'),
                  _buildPresetChip('Last Month', 'last_month'),
                  _buildPresetChip('Custom', 'custom'),
                ],
              ),
              if (_datePreset == 'custom')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                        initialDateRange: _customRange,
                      );
                      if (range != null) setState(() => _customRange = range);
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _customRange != null
                          ? '${_fmtDate(_customRange!.start)} – ${_fmtDate(_customRange!.end)}'
                          : 'Select dates...',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              const SizedBox(height: 18),

              // Report type
              const Text('Report Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _reportTypes.map((rt) {
                  final selected = _reportType == rt['key'];
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(rt['icon'] as IconData, size: 16, color: selected ? Colors.white : Colors.deepPurple),
                        const SizedBox(width: 6),
                        Text(rt['label'] as String, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.black87)),
                      ],
                    ),
                    selected: selected,
                    selectedColor: Colors.deepPurple,
                    onSelected: (_) => setState(() => _reportType = rt['key'] as String),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // Format toggle
              const Text('Format', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildFormatToggle('PDF', 'pdf', Icons.picture_as_pdf),
                  const SizedBox(width: 12),
                  _buildFormatToggle('Excel', 'excel', Icons.table_chart),
                ],
              ),
              const SizedBox(height: 20),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),

              // Generate button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isGenerating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.download_rounded),
                  label: Text(_isGenerating ? 'Generating...' : 'Generate Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, String value) {
    final selected = _datePreset == value;
    return GestureDetector(
      onTap: () => setState(() => _datePreset = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.deepPurple : Colors.grey[300]!),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          color: selected ? Colors.white : Colors.black87,
        )),
      ),
    );
  }

  Widget _buildFormatToggle(String label, String value, IconData icon) {
    final selected = _format == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _format = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.deepPurple.withOpacity(0.1) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.deepPurple : Colors.grey[300]!,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.deepPurple : Colors.grey),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.deepPurple : Colors.grey[700],
              )),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _generate() async {
    if (_datePreset == 'custom' && _customRange == null) {
      setState(() => _error = 'Please select a custom date range.');
      return;
    }

    setState(() { _isGenerating = true; _error = null; });

    try {
      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

      await ExportReportService.generateReport(
        context: context,
        dateRange: _effectiveDateRange,
        format: _format,
        reportType: _reportType,
        branchIds: branchIds,
        branchFilter: branchFilter,
        userScope: userScope,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }
}
