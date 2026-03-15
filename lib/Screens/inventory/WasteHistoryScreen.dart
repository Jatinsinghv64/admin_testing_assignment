import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../services/inventory/WasteService.dart';
import '../../services/CsvExportService.dart';
import '../../main.dart';

class WasteHistoryScreen extends StatefulWidget {
  const WasteHistoryScreen({super.key});

  @override
  State<WasteHistoryScreen> createState() => _WasteHistoryScreenState();
}

class _WasteHistoryScreenState extends State<WasteHistoryScreen> {
  late final WasteService _service;
  bool _serviceInitialized = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _minCtrl = TextEditingController();
  final TextEditingController _maxCtrl = TextEditingController();
  String _reason = 'all';
  String _datePreset = 'all'; // New state for dropdown
  DateTimeRange? _range;

  void _applyDatePreset(String preset) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (preset == 'all') {
      setState(() {
        _datePreset = preset;
        _range = null;
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
        // User cancelled, keep previous preset or revert to all
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
  void dispose() {
    _searchCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Waste History',
            style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.deepPurple),
            tooltip: 'Export CSV',
            onPressed: () {
              final range = _range ??
                  DateTimeRange(
                      start: DateTime.now().subtract(const Duration(days: 30)),
                      end: DateTime.now());
              CsvExportService.exportWasteHistory(context, branchIds, range);
            },
          )
        ],
      ),
      body: Column(
        children: [
          _filters(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.streamWasteEntries(branchIds,
                  isSuperAdmin: userScope.isSuperAdmin),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.deepPurple),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load history: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                final rows = _applyFilters(snapshot.data ?? []);
                if (rows.isEmpty) {
                  return const Center(
                      child: Text('No matching waste entries.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _entryCard(rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search item name...',
              prefixIcon: Icon(Icons.search, color: Colors.deepPurple.shade300),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'expired', child: Text('Expired')),
                    DropdownMenuItem(value: 'spilled', child: Text('Spilled')),
                    DropdownMenuItem(value: 'damaged', child: Text('Damaged')),
                    DropdownMenuItem(
                        value: 'overproduction', child: Text('Overproduction')),
                    DropdownMenuItem(
                        value: 'returned', child: Text('Returned')),
                    DropdownMenuItem(value: 'quality', child: Text('Quality')),
                    DropdownMenuItem(
                        value: 'contamination', child: Text('Contamination')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _reason = v ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _datePreset,
                  decoration: const InputDecoration(labelText: 'Date Range'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Time')),
                    DropdownMenuItem(value: 'today', child: Text('Today')),
                    DropdownMenuItem(value: 'last7', child: Text('Last 7 Days')),
                    DropdownMenuItem(value: 'last30', child: Text('Last 30 Days')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom Range')),
                  ],
                  onChanged: (v) => _applyDatePreset(v ?? 'all'),
                ),
              ),
            ],
          ),
          if (_datePreset == 'custom' && _range != null) ...[
            const SizedBox(height: 8),
            Text(
              'Selected: ${_range!.start.toLocal().toString().split(' ').first} - ${_range!.end.toLocal().toString().split(' ').first}',
              style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Min loss'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _maxCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Max loss'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> rows) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final min = double.tryParse(_minCtrl.text.trim());
    final max = double.tryParse(_maxCtrl.text.trim());

    return rows.where((r) {
      final name = (r['itemName'] ?? '').toString().toLowerCase();
      final reason = (r['reason'] ?? '').toString();
      final loss = (r['estimatedLoss'] as num?)?.toDouble() ?? 0.0;
      final dt = (r['wasteDate'] as Timestamp?)?.toDate();

      if (q.isNotEmpty && !name.contains(q)) return false;
      if (_reason != 'all' && reason != _reason) return false;
      if (min != null && loss < min) return false;
      if (max != null && loss > max) return false;
      if (_range != null && dt != null) {
        if (dt.isBefore(_range!.start) || dt.isAfter(_range!.end)) return false;
      }
      return true;
    }).toList();
  }

  Widget _entryCard(Map<String, dynamic> e) {
    final photos = List<String>.from(e['photoUrls'] as List? ?? []);
    final dt = (e['wasteDate'] as Timestamp?)?.toDate();
    final loss = (e['estimatedLoss'] as num?)?.toDouble() ?? 0.0;
    final qty = (e['quantity'] as num?)?.toDouble() ?? 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (e['itemName'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => _deleteEntry(e['id'].toString()),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${qty.toStringAsFixed(2)} ${(e['unit'] ?? '').toString()} • ${(e['reason'] ?? '').toString()}',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Loss: QAR ${loss.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.deepPurple,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dt?.toLocal().toString().split('.').first ?? '-',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 68,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    photos[i],
                    width: 68,
                    height: 68,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteEntry(String id) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Waste Entry?'),
            content: const Text(
              'This will remove the entry and reverse inventory deduction for ingredient entries.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await _service.deleteWasteEntry(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Waste entry deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
