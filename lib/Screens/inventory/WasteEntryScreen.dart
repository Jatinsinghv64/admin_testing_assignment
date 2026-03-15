import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/WasteService.dart';

class WasteEntryScreen extends StatefulWidget {
  const WasteEntryScreen({super.key});

  @override
  State<WasteEntryScreen> createState() => _WasteEntryScreenState();
}

class _WasteEntryScreenState extends State<WasteEntryScreen> {
  late final WasteService _service;
  bool _serviceInitialized = false;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _qtyCtrl = TextEditingController();
  final TextEditingController _unitCtrl = TextEditingController();
  final TextEditingController _reasonNoteCtrl = TextEditingController();
  final TextEditingController _lossCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final List<File> _photos = [];
  final _formKey = GlobalKey<FormState>();

  String _itemType = 'ingredient';
  String _reason = 'expired';
  String? _itemId;
  String _itemName = '';
  DateTime _wasteDate = DateTime.now();
  bool _isSaving = false;

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
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _reasonNoteCtrl.dispose();
    _lossCtrl.dispose();
    _notesCtrl.dispose();
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
        title: const Text('Log Waste'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _itemType == 'ingredient'
              ? _service.streamIngredients(branchIds)
              : _service.streamMenuItems(branchIds),
          builder: (context, snapshot) {
            final items = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Item Details',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'ingredient',
                            label: Text('Ingredient'),
                          ),
                          ButtonSegment(
                            value: 'menu_item',
                            label: Text('Menu Item'),
                          ),
                        ],
                        selected: {_itemType},
                        onSelectionChanged: (value) {
                          setState(() {
                            _itemType = value.first;
                            _itemId = null;
                            _itemName = '';
                            _unitCtrl.clear();
                            _lossCtrl.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildItemSelector(items),
                      const SizedBox(height: 10),
                      _buildTextInput(
                        controller: _qtyCtrl,
                        label: 'Quantity *',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        required: true,
                        onChanged: (_) {
                          if (_itemId != null && _itemId!.isNotEmpty) {
                            final selected = items.firstWhere(
                              (i) => i['id'].toString() == _itemId,
                              // Provide empty map instead of empty set to prevent type error
                              orElse: () => <String, dynamic>{},
                            );
                            if (selected.isNotEmpty)
                              _autoCalculateLoss(selected);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildTextInput(
                        controller: _unitCtrl,
                        label: 'Unit',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Waste Reason',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _buildSelector(
                        label: 'Reason *',
                        value: _reason,
                        items: const [
                          'expired',
                          'spilled',
                          'damaged',
                          'overproduction',
                          'returned',
                          'quality',
                          'contamination',
                          'other'
                        ],
                        labelFn: _reasonLabel,
                        iconFn: _reasonIcon,
                        onChanged: (v) => setState(() => _reason = v),
                      ),
                      if (_reason == 'other') ...[
                        const SizedBox(height: 10),
                        _buildTextInput(
                          controller: _reasonNoteCtrl,
                          label: 'Reason note',
                          required: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Value & Context',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _buildTextInput(
                        controller: _lossCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        label: 'Estimated loss (QAR) *',
                        required: true,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Icon(Icons.event_outlined,
                                size: 18, color: Colors.deepPurple.shade300),
                          ),
                          title: const Text('Waste date & time',
                              style: TextStyle(fontSize: 14)),
                          subtitle: Text(
                            _wasteDate.toLocal().toString().split('.').first,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_calendar_outlined,
                                color: Colors.deepPurple),
                            onPressed: _pickDateTime,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTextInput(
                        controller: _notesCtrl,
                        maxLines: 2,
                        label: 'Notes',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Photo Proof',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ..._photos.asMap().entries.map((entry) {
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    entry.value,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: IconButton(
                                    onPressed: () => setState(
                                        () => _photos.removeAt(entry.key)),
                                    icon: const Icon(
                                      Icons.cancel,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                    splashRadius: 16,
                                  ),
                                ),
                              ],
                            );
                          }),
                          ActionChip(
                            avatar: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('Add Photo'),
                            onPressed: _pickPhoto,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _save(
                              branchIds: branchIds,
                              recordedBy: userScope.userIdentifier.isNotEmpty
                                  ? userScope.userIdentifier
                                  : (userScope.userEmail.isNotEmpty
                                      ? userScope.userEmail
                                      : 'system'),
                            ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Save Waste Entry'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─── HELPERS ──────────────────────────────────────────────

  String _reasonLabel(String r) {
    switch (r) {
      case 'expired':
        return 'Expired';
      case 'spilled':
        return 'Spilled';
      case 'damaged':
        return 'Damaged';
      case 'overproduction':
        return 'Overproduction';
      case 'returned':
        return 'Returned';
      case 'quality':
        return 'Quality Issue';
      case 'contamination':
        return 'Contamination';
      case 'other':
        return 'Other';
      default:
        return r;
    }
  }

  IconData _reasonIcon(String r) {
    switch (r) {
      case 'expired':
        return Icons.history_toggle_off;
      case 'spilled':
        return Icons.water_drop_outlined;
      case 'damaged':
        return Icons.broken_image_outlined;
      case 'overproduction':
        return Icons.trending_up;
      case 'returned':
        return Icons.keyboard_return;
      case 'quality':
        return Icons.high_quality;
      case 'contamination':
        return Icons.warning_amber_rounded;
      case 'other':
        return Icons.category_outlined;
      default:
        return Icons.label_outline;
    }
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool required = false,
    IconData? icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? prefix,
    void Function(String)? onChanged,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.deepPurple.shade300, size: 20)
            : null,
        prefix: prefix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: Colors.grey[700], fontSize: 14),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : (label == 'Estimated loss (QAR) *'
              ? (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < 0) return 'Enter valid loss amount';
                  return null;
                }
              : (label == 'Quantity *'
                  ? (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter quantity > 0';
                      return null;
                    }
                  : null)),
    );
  }

  Widget _buildSelector({
    required String label,
    required String value,
    required List<String> items,
    required String Function(String) labelFn,
    required IconData Function(String) iconFn,
    required void Function(String) onChanged,
    IconData? defaultIcon,
  }) {
    IconData valueIcon = iconFn(value);

    return InkWell(
      onTap: () => _showPicker(label, value, items, labelFn, iconFn, onChanged),
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(defaultIcon ?? valueIcon,
              size: 20, color: Colors.deepPurple.shade300),
          suffixIcon:
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[400]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(
          labelFn(value),
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
      ),
    );
  }

  void _showPicker(
    String title,
    String current,
    List<String> items,
    String Function(String) labelFn,
    IconData Function(String) iconFn,
    void Function(String) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final selected = item == current;
                  IconData itemIcon = iconFn(item);

                  return ListTile(
                    onTap: () {
                      onSelect(item);
                      Navigator.pop(ctx);
                    },
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? Colors.deepPurple.withOpacity(0.3)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Icon(itemIcon,
                          size: 18,
                          color:
                              selected ? Colors.deepPurple : Colors.grey[600]),
                    ),
                    title: Text(labelFn(item),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: selected ? Colors.deepPurple : Colors.black87,
                        )),
                    trailing: selected
                        ? const Icon(Icons.check_circle,
                            color: Colors.deepPurple, size: 20)
                        : null,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildItemSelector(List<Map<String, dynamic>> items) {
    return FormField<String>(
      validator: (v) =>
          (_itemId == null || _itemId!.isEmpty) ? 'Required' : null,
      builder: (state) {
        final hasSelection = _itemId != null && _itemId!.isNotEmpty;
        return InkWell(
          onTap: () => _showItemPickerSheet(items, state),
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Select item *',
              filled: true,
              fillColor: Colors.white,
              prefixIcon: Icon(
                  _itemType == 'ingredient'
                      ? Icons
                          .lightbulb_outline // We can use auto_awesome or kitchen or blender
                      : Icons.restaurant_menu_outlined,
                  size: 20,
                  color: Colors.deepPurple.shade300),
              suffixIcon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey[400]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Colors.deepPurple, width: 1.5),
              ),
              errorText: state.errorText,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: Text(
              hasSelection ? _itemName : 'Tap to select...',
              style: TextStyle(
                  fontSize: 14,
                  color: hasSelection ? Colors.black87 : Colors.grey[600]),
            ),
          ),
        );
      },
    );
  }

  void _showItemPickerSheet(
      List<Map<String, dynamic>> items, FormFieldState<String> state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ItemPickerSheet(
        items: items,
        currentId: _itemId,
        itemType: _itemType,
        onSelect: (id, name, item) {
          setState(() {
            _itemId = id;
            _itemName = name;
            _unitCtrl.text = _itemType == 'ingredient'
                ? (item['unit'] ?? '').toString()
                : 'portion';
            _autoCalculateLoss(item);
          });
          state.didChange(id);
        },
      ),
    );
  }

  Widget _card({required Widget child}) {
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
      child: child,
    );
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked != null && mounted) {
      setState(() => _photos.add(File(picked.path)));
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _wasteDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_wasteDate),
    );
    if (time == null) return;
    setState(() {
      _wasteDate =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _autoCalculateLoss(Map<String, dynamic> selected) {
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0.0;
    double unitCost = 0.0;
    if (_itemType == 'ingredient') {
      unitCost = (selected['costPerUnit'] as num?)?.toDouble() ?? 0.0;
    } else {
      unitCost = (selected['price'] as num?)?.toDouble() ?? 0.0;
    }
    _lossCtrl.text = (qty * unitCost).toStringAsFixed(2);
  }

  Future<void> _save({
    required List<String> branchIds,
    required String recordedBy,
  }) async {
    if (!_formKey.currentState!.validate()) return;
    if (_itemId == null || _itemId!.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      final wasteId = FirebaseFirestore.instance.collection('tmp').doc().id;
      final urls = <String>[];
      for (int i = 0; i < _photos.length; i++) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('waste_entries/$wasteId/photo_$i.jpg');
        await ref.putFile(_photos[i]);
        urls.add(await ref.getDownloadURL());
      }

      await _service.addWasteEntry(
        branchIds: branchIds,
        itemType: _itemType,
        itemId: _itemId!,
        itemName: _itemName,
        unit: _unitCtrl.text.trim(),
        quantity: double.tryParse(_qtyCtrl.text.trim()) ?? 0.0,
        reason: _reason,
        reasonNote: _reason == 'other' ? _reasonNoteCtrl.text.trim() : null,
        estimatedLoss: double.tryParse(_lossCtrl.text.trim()) ?? 0.0,
        wasteDate: _wasteDate,
        recordedBy: recordedBy,
        notes: _notesCtrl.text.trim(),
        photoUrls: urls,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Waste entry recorded'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _ItemPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String? currentId;
  final String itemType;
  final Function(String, String, Map<String, dynamic>) onSelect;

  const _ItemPickerSheet({
    required this.items,
    required this.currentId,
    required this.itemType,
    required this.onSelect,
  });

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((m) {
      final name = m['name']?.toString().toLowerCase() ?? '';
      return _search.isEmpty || name.contains(_search);
    }).toList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Select Item',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search items…',
                prefixIcon:
                    Icon(Icons.search, color: Colors.deepPurple.shade300),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No items found',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final item = filtered[i];
                      final id = item['id'].toString();
                      final name = (item['name'] ?? '').toString();
                      final selected = id == widget.currentId;

                      return ListTile(
                        onTap: () {
                          widget.onSelect(id, name, item);
                          Navigator.pop(context);
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? Colors.deepPurple.withOpacity(0.3)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Icon(
                            widget.itemType == 'ingredient'
                                ? Icons.eco_outlined
                                : Icons.restaurant_menu_outlined,
                            size: 18,
                            color:
                                selected ? Colors.deepPurple : Colors.grey[500],
                          ),
                        ),
                        title: Text(name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color:
                                  selected ? Colors.deepPurple : Colors.black87,
                            )),
                        subtitle: item['category'] != null
                            ? Text(item['category'],
                                style: const TextStyle(fontSize: 12))
                            : null,
                        trailing: selected
                            ? const Icon(Icons.check_circle,
                                color: Colors.deepPurple, size: 20)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
