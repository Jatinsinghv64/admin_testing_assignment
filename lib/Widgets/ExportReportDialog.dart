// lib/Widgets/ExportReportDialog.dart
// Export Report Dialog — Multi-select checkboxes for data sections, date range, format

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../Widgets/BranchFilterService.dart';
import '../services/ExportReportService.dart';

class ExportReportDialog extends StatefulWidget {
  /// Pre-selected sections based on the context screen
  final Set<String>? preSelectedSections;

  const ExportReportDialog({super.key, this.preSelectedSections});

  /// Show the export report dialog with optional context-aware pre-selections
  static Future<void> show(BuildContext context,
      {Set<String>? preSelectedSections}) {
    return showDialog(
      context: context,
      builder: (_) =>
          ExportReportDialog(preSelectedSections: preSelectedSections),
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

  // Multi-select sections
  late Set<String> _selectedSections;

  bool _isGenerating = false;
  String? _error;

  static const List<Map<String, dynamic>> _allSections = [
    {
      'key': 'sales_summary',
      'label': 'Sales Summary',
      'icon': Icons.summarize,
      'desc': 'Orders, revenue, AOV'
    },
    {
      'key': 'order_details',
      'label': 'Order Details',
      'icon': Icons.list_alt,
      'desc': 'Line-by-line order listing'
    },
    {
      'key': 'revenue_by_source',
      'label': 'Revenue by Source',
      'icon': Icons.pie_chart,
      'desc': 'App, POS, Web breakdown'
    },
    {
      'key': 'revenue_by_branch',
      'label': 'Revenue by Branch',
      'icon': Icons.business,
      'desc': 'Branch-wise split'
    },
    {
      'key': 'item_wise_sales',
      'label': 'Item-wise Sales',
      'icon': Icons.restaurant,
      'desc': 'Top selling items'
    },
    {
      'key': 'profit_margin',
      'label': 'Profit & Margin',
      'icon': Icons.trending_up,
      'desc': 'Item-level cost & margin'
    },
    {
      'key': 'inventory_stock',
      'label': 'Inventory & Stock',
      'icon': Icons.inventory_2,
      'desc': 'Stock levels, low alerts'
    },
    {
      'key': 'staff_summary',
      'label': 'Staff Summary',
      'icon': Icons.groups,
      'desc': 'Team count & attendance'
    },
    {
      'key': 'promotions_performance',
      'label': 'Promotions',
      'icon': Icons.campaign,
      'desc': 'Active deals & usage'
    },
    {
      'key': 'expense_summary',
      'label': 'Expense Summary',
      'icon': Icons.receipt_long,
      'desc': 'Paid expenses list'
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedSections = widget.preSelectedSections != null
        ? Set<String>.from(widget.preSelectedSections!)
        : {'sales_summary'}; // default
  }

  DateTimeRange get _effectiveDateRange {
    if (_datePreset == 'custom' && _customRange != null) return _customRange!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_datePreset) {
      case 'yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        return DateTimeRange(
            start: yesterday, end: today.subtract(const Duration(seconds: 1)));
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

  bool get _allSelected => _selectedSections.length == _allSections.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selectedSections.clear();
      } else {
        _selectedSections = _allSections.map((s) => s['key'] as String).toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final branchFilter = context.read<BranchFilterService>();
    final branchLabel = branchFilter.selectedBranchId == null
        ? 'All Branches'
        : branchFilter.getBranchName(branchFilter.selectedBranchId!);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed header
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.file_download_outlined,
                            color: Colors.deepPurple),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text('Export Report',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.store,
                            size: 16, color: Colors.deepPurple),
                        const SizedBox(width: 8),
                        Text(branchLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.deepPurple)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date range
                    const Text('Date Range',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
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
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 365)),
                              lastDate: DateTime.now(),
                              initialDateRange: _customRange,
                            );
                            if (range != null)
                              setState(() => _customRange = range);
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
                    const SizedBox(height: 20),

                    // Report data sections (multi-select checkboxes)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Report Sections',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        TextButton.icon(
                          onPressed: _toggleAll,
                          icon: Icon(
                            _allSelected ? Icons.deselect : Icons.select_all,
                            size: 16,
                          ),
                          label: Text(
                            _allSelected ? 'Deselect All' : 'Select All',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_selectedSections.length} of ${_allSections.length} selected',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    // Checkbox list
                    ..._allSections.map((section) {
                      final key = section['key'] as String;
                      final isSelected = _selectedSections.contains(key);
                      return _buildSectionCheckbox(
                        key: key,
                        label: section['label'] as String,
                        desc: section['desc'] as String,
                        icon: section['icon'] as IconData,
                        isSelected: isSelected,
                      );
                    }),
                    const SizedBox(height: 18),

                    // Format toggle
                    const Text('Format',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildFormatToggle('PDF', 'pdf', Icons.picture_as_pdf),
                        const SizedBox(width: 12),
                        _buildFormatToggle('Excel', 'excel', Icons.table_chart),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // Fixed footer
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
              child: Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: (_isGenerating || _selectedSections.isEmpty)
                          ? null
                          : _generate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _isGenerating
                            ? 'Generating...'
                            : _selectedSections.isEmpty
                                ? 'Select at least 1 section'
                                : 'Generate Report (${_selectedSections.length} sections)',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCheckbox({
    required String key,
    required String label,
    required String desc,
    required IconData icon,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedSections.remove(key);
            } else {
              _selectedSections.add(key);
            }
          });
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.deepPurple.withOpacity(0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? Colors.deepPurple.withOpacity(0.3)
                  : Colors.grey[200]!,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) {
                    setState(() {
                      if (isSelected) {
                        _selectedSections.remove(key);
                      } else {
                        _selectedSections.add(key);
                      }
                    });
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon,
                  size: 18,
                  color: isSelected ? Colors.deepPurple : Colors.grey[600]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              isSelected ? Colors.deepPurple : Colors.black87,
                        )),
                    Text(desc,
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
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
          border: Border.all(
              color: selected ? Colors.deepPurple : Colors.grey[300]!),
        ),
        child: Text(label,
            style: TextStyle(
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
            color:
                selected ? Colors.deepPurple.withOpacity(0.1) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.deepPurple : Colors.grey[300]!,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: selected ? Colors.deepPurple : Colors.grey),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
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

    if (_selectedSections.isEmpty) {
      setState(() => _error = 'Please select at least one report section.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final userScope = context.read<UserScopeService>();
      final branchFilter = context.read<BranchFilterService>();
      final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

      await ExportReportService.generateReport(
        context: context,
        dateRange: _effectiveDateRange,
        format: _format,
        selectedSections: _selectedSections,
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
