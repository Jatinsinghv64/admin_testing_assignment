import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart' as intl;
import '../../Widgets/BranchFilterService.dart';
import '../../main.dart';
import '../../services/inventory/WasteService.dart';

class WasteEntryScreenLarge extends StatefulWidget {
  const WasteEntryScreenLarge({super.key});

  @override
  State<WasteEntryScreenLarge> createState() => _WasteEntryScreenLargeState();
}

class _WasteEntryScreenLargeState extends State<WasteEntryScreenLarge> {
  late final WasteService _service;
  bool _serviceInitialized = false;

  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _qtyCtrl = TextEditingController();
  final TextEditingController _unitCtrl = TextEditingController();
  final TextEditingController _reasonNoteCtrl = TextEditingController();
  final TextEditingController _lossCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  final List<File> _photos = [];

  String _itemType = 'ingredient';
  String _reason = 'expired';
  String? _itemId;
  String _itemName = '';
  DateTime _wasteDate = DateTime.now();
  bool _isLoading = false;

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

  // ── Helpers ──────────────────────────────────────────────────

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red,
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  // ── Auto Calculate Loss ──────────────────────────────────────

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

  // ── Save ─────────────────────────────────────────────────────

  Future<void> _save({
    required List<String> branchIds,
    required String recordedBy,
  }) async {
    if (!_formKey.currentState!.validate()) return;
    if (_itemId == null || _itemId!.isEmpty) {
      _showError('Please select an item to log waste for.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final wasteId = FirebaseFirestore.instance.collection('tmp').doc().id;
      final urls = <String>[];

      for (int i = 0; i < _photos.length; i++) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('waste_entries/$wasteId/photo_$i.jpg');
        await ref.putFile(_photos[i]);
        final url = await ref.getDownloadURL();
        urls.add(url);
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

      _showSuccess('Waste entry recorded successfully!');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Failed to record waste entry: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    final recorderId = userScope.userIdentifier.isNotEmpty
        ? userScope.userIdentifier
        : (userScope.userEmail.isNotEmpty ? userScope.userEmail : 'system');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // ── Header bar ──────────────────────────────────────
          _buildHeader(branchIds, recorderId),
          // ── Body ────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _itemType == 'ingredient'
                  ? _service.streamIngredients(branchIds)
                  : _service.streamMenuItems(branchIds),
              builder: (context, snapshot) {
                final items = snapshot.data ?? [];

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT COLUMN (2/3)
                            Expanded(
                              flex: 2,
                              child: Column(
                                children: [
                                  _buildItemDetailsCard(items),
                                  const SizedBox(height: 20),
                                  _buildWasteReasonCard(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            // RIGHT COLUMN (1/3)
                            Expanded(
                              flex: 1,
                              child: Column(
                                children: [
                                  _buildValueAndContextCard(),
                                  const SizedBox(height: 20),
                                  _buildPhotoProofCard(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  HEADER
  // ══════════════════════════════════════════════════════════════

  Widget _buildHeader(List<String> branchIds, String recorderId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Log Waste Entry',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        'Deduction',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Branches: ${branchIds.join(", ")}  •  Recording as: $recorderId',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isLoading
                ? null
                : () => _save(branchIds: branchIds, recordedBy: recorderId),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save Entry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  ITEM DETAILS
  // ══════════════════════════════════════════════════════════════

  Widget _buildItemDetailsCard(List<Map<String, dynamic>> items) {
    return _card(
      icon: Icons.inventory_2_outlined,
      title: 'Item Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'ingredient',
                      icon: Icon(Icons.shopping_basket_outlined),
                      label: Text('Ingredient'),
                    ),
                    ButtonSegment(
                      value: 'menu_item',
                      icon: Icon(Icons.restaurant_menu_outlined),
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
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                      (Set<WidgetState> states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.deepPurple.shade50;
                        }
                        return Colors.white;
                      },
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                      (Set<WidgetState> states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.deepPurple;
                        }
                        return Colors.grey.shade700;
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildItemSelector(items),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _qtyCtrl,
                  label: 'Quantity Wasted *',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    if (_itemId != null && _itemId!.isNotEmpty) {
                      final selected = items.firstWhere(
                        (i) => i['id'].toString() == _itemId,
                        orElse: () => <String, dynamic>{},
                      );
                      if (selected.isNotEmpty) {
                        _autoCalculateLoss(selected);
                      }
                    }
                  },
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = double.tryParse(v);
                    if (n == null || n <= 0) return '> 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  controller: _unitCtrl,
                  label: 'Unit Measurement',
                  helperText: _itemType == 'menu_item' ? 'Usually "portion"' : null,
                ),
              ),
            ],
          ),
        ],
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
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Select item to log *',
              filled: true,
              fillColor: Colors.white,
              prefixIcon: Icon(
                  _itemType == 'ingredient'
                      ? Icons.kitchen
                      : Icons.restaurant_menu_outlined,
                  size: 20,
                  color: Colors.deepPurple.shade300),
              suffixIcon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey[400]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Colors.deepPurple, width: 1.5),
              ),
              errorText: state.errorText,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: Text(
              hasSelection ? _itemName : 'Tap to search and select item...',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasSelection ? FontWeight.w600 : FontWeight.normal,
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

  // ══════════════════════════════════════════════════════════════
  //  WASTE REASON
  // ══════════════════════════════════════════════════════════════

  Widget _buildWasteReasonCard() {
    return _card(
      icon: Icons.quiz_outlined,
      title: 'Waste Reason',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSelector(
                  label: 'Action Reason *',
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
              ),
              if (_reason != 'other') const SizedBox(width: 16),
              if (_reason != 'other') const Spacer(),
            ],
          ),
          if (_reason == 'other') ...[
            const SizedBox(height: 16),
            _textField(
              controller: _reasonNoteCtrl,
              label: 'Reason note (please specify) *',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  VALUE & CONTEXT (right column)
  // ══════════════════════════════════════════════════════════════

  Widget _buildValueAndContextCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.money_off_csred_rounded,
                  color: Colors.red.shade400, size: 22),
              const SizedBox(width: 10),
              const Text('Value & Context',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          _textField(
            controller: _lossCtrl,
            label: 'Estimated Loss (QAR)*',
            prefixText: 'QAR ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final n = double.tryParse(v);
              if (n == null || n < 0) return 'Valid amount required';
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Date/Time picker
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ListTile(
              leading: Icon(Icons.event_outlined,
                  size: 20, color: Colors.deepPurple.shade300),
              title: const Text('Waste date & time',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              subtitle: Text(
                intl.DateFormat('MMM dd, yyyy · hh:mm a').format(_wasteDate),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar_outlined,
                    color: Colors.deepPurple, size: 20),
                onPressed: _pickDateTime,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _notesCtrl,
            label: 'Additional Notes',
            maxLines: 3,
          ),
        ],
      ),
    );
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

  // ══════════════════════════════════════════════════════════════
  //  PHOTO PROOF (right column)
  // ══════════════════════════════════════════════════════════════

  Widget _buildPhotoProofCard() {
    return _card(
      icon: Icons.add_a_photo_outlined,
      title: 'Photo Proof',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attaching photos of damaged or spilled items helps with record keeping and auditing.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (_photos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 32, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('No photos added',
                      style: TextStyle(color: Colors.grey.shade500)),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _photos.asMap().entries.map((entry) {
                return Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          entry.value,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton(
                        onPressed: () =>
                            setState(() => _photos.removeAt(entry.key)),
                        icon: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: const Icon(
                            Icons.cancel,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                        splashRadius: 16,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Add Photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                side: BorderSide(color: Colors.deepPurple.shade200),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Photo'),
        content: Column(
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

  // ══════════════════════════════════════════════════════════════
  //  SHARED COMPONENTS
  // ══════════════════════════════════════════════════════════════

  Widget _card({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.deepPurple, size: 22),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (trailing != null) ...[const Spacer(), trailing],
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? prefixText,
    String? helperText,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefixText,
        helperText: helperText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildSelector({
    required String label,
    required String value,
    required List<String> items,
    required String Function(String) labelFn,
    required IconData Function(String) iconFn,
    required void Function(String) onChanged,
  }) {
    IconData valueIcon = iconFn(value);

    return InkWell(
      onTap: () => _showPicker(label, value, items, labelFn, iconFn, onChanged),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(valueIcon,
              size: 20, color: Colors.deepPurple.shade300),
          suffixIcon:
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[400]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
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
                      color: selected ? Colors.deepPurple : Colors.grey[600]),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          )
        ],
      ),
    );
  }

  // Same logic as before
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
}

// ── Item Picker Sheet (matches original implementation but styled) ──

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
    final filtered = widget.items.where((i) {
      final name = (i['name'] ?? '').toString().toLowerCase();
      final idText = (i['id'] ?? '').toString().toLowerCase();
      return name.contains(_search.toLowerCase()) ||
          idText.contains(_search.toLowerCase());
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search items...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = filtered[i];
                final id = item['id'].toString();
                final name = item['name']?.toString() ?? 'Unnamed';
                final isSelected = widget.currentId == id;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Colors.deepPurple.shade50,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  title: Text(name,
                      style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500)),
                  subtitle: Text(
                      widget.itemType == 'ingredient'
                          ? 'Stock: ${item['currentStock']} ${item['unit']} | Cost: QAR ${item['costPerUnit']}'
                          : 'Price: QAR ${item['price']}',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Colors.deepPurple)
                      : const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    widget.onSelect(id, name, item);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
