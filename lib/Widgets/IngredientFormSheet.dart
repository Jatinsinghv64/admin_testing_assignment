import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../Models/IngredientModel.dart';
import '../services/ingredients/IngredientService.dart';

class IngredientFormSheet extends StatefulWidget {
  final IngredientModel? existing;
  final List<String> branchIds;
  final IngredientService service;

  const IngredientFormSheet({
    super.key,
    required this.existing,
    required this.branchIds,
    required this.service,
  });

  @override
  State<IngredientFormSheet> createState() => _IngredientFormSheetState();
}

class _IngredientFormSheetState extends State<IngredientFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _costCtr = TextEditingController();
  final _stockCtr = TextEditingController();
  final _minThresholdCtr = TextEditingController();
  final _shelfLifeCtr = TextEditingController();
  final _skuCtr = TextEditingController();
  final _barcodeCtr = TextEditingController();

  late String _category;
  late String _unit;
  late List<String> _allergenTags;
  late bool _isPerishable;
  late bool _isActive;
  File? _pickedImage;
  String? _existingImageUrl;
  bool _isLoading = false;
  final _imagePicker = ImagePicker();

  late List<String> _previousSupplierIds;
  late List<String> _supplierIds;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtr.text = e?.name ?? '';
    _costCtr.text = e != null ? e.costPerUnit.toString() : '';
    _stockCtr.text = e != null ? e.currentStock.toString() : '';
    _minThresholdCtr.text = e != null ? e.minStockThreshold.toString() : '';
    _shelfLifeCtr.text = e?.shelfLifeDays?.toString() ?? '';
    _skuCtr.text = e?.sku ?? '';
    _barcodeCtr.text = e?.barcode ?? '';

    // Fix for assertion error: value must be in items. 
    // If the database has an unknown value like "Burger", we fallback to "other".
    final catValue = e?.category ?? IngredientModel.categories.first;
    _category = IngredientModel.categories.contains(catValue) 
        ? catValue 
        : 'other';

    final unitValue = e?.unit ?? IngredientModel.units.first;
    _unit = IngredientModel.units.contains(unitValue) 
        ? unitValue 
        : 'pieces';

    _allergenTags = List.from(e?.allergenTags ?? []);
    _isPerishable = e?.isPerishable ?? false;
    _isActive = e?.isActive ?? true;
    _existingImageUrl = e?.imageUrl;
    _supplierIds = List.from(e?.supplierIds ?? []);
    _previousSupplierIds = List.from(e?.supplierIds ?? []);
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _costCtr.dispose();
    _stockCtr.dispose();
    _minThresholdCtr.dispose();
    _shelfLifeCtr.dispose();
    _skuCtr.dispose();
    _barcodeCtr.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xFile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xFile != null) {
      setState(() => _pickedImage = File(xFile.path));
    }
  }

  Future<String?> _uploadImage(String ingredientId) async {
    if (_pickedImage == null) return _existingImageUrl;
    final ref =
        FirebaseStorage.instance.ref().child('ingredients/$ingredientId.jpg');
    await ref.putFile(_pickedImage!);
    return await ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final String docId = widget.existing?.id ?? FirebaseFirestore.instance.collection('ingredients').doc().id;
      final String? finalImageUrl = await _uploadImage(docId);

      final now = DateTime.now();

      final i = IngredientModel(
        id: docId,
        name: _nameCtr.text.trim(),
        category: _category,
        unit: _unit,
        costPerUnit: double.parse(_costCtr.text.trim()),
        currentStock: double.parse(_stockCtr.text.trim()),
        minStockThreshold: double.parse(_minThresholdCtr.text.trim()),
        isPerishable: _isPerishable,
        shelfLifeDays: _isPerishable && _shelfLifeCtr.text.isNotEmpty
            ? int.parse(_shelfLifeCtr.text.trim())
            : null,
        allergenTags: _allergenTags,
        supplierIds: _supplierIds,
        branchIds: widget.existing?.branchIds ?? widget.branchIds,
        imageUrl: finalImageUrl,
        isActive: _isActive,
        sku: _skuCtr.text.trim(),
        barcode: _barcodeCtr.text.trim(),
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
      );

      if (widget.existing == null) {
        await widget.service.addIngredient(i);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingredient Added'), backgroundColor: Colors.green),
          );
        }
      } else {
        await widget.service.updateIngredient(i, _previousSupplierIds);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingredient Updated'), backgroundColor: Colors.green),
          );
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildPhotoField() {
    return GestureDetector(
      onTap: _pickImage,
      child: Center(
        child: CircleAvatar(
          radius: 40,
          backgroundColor: Colors.deepPurple.shade50,
          backgroundImage: _pickedImage != null
              ? FileImage(_pickedImage!)
              : (_existingImageUrl != null ? NetworkImage(_existingImageUrl!) : null) as ImageProvider?,
          child: _pickedImage == null && _existingImageUrl == null
              ? Icon(Icons.add_a_photo, size: 30, color: Colors.deepPurple.shade300)
              : null,
        ),
      ),
    );
  }

  void _toggleAllergen(String tag) {
    setState(() {
      if (_allergenTags.contains(tag)) {
        _allergenTags.remove(tag);
      } else {
        _allergenTags.add(tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null ? 'Add Ingredient' : 'Edit Ingredient',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              _buildPhotoField(),
              const SizedBox(height: 16),

              // Active Toggle (Only on Edit)
              if (widget.existing != null)
                SwitchListTile(
                  title: const Text('Active Ingredient', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: _isActive,
                  activeColor: Colors.deepPurple,
                  onChanged: (v) => setState(() => _isActive = v),
                ),

              // Name
              TextFormField(
                controller: _nameCtr,
                decoration: InputDecoration(
                  labelText: 'Ingredient Name *',
                  prefixIcon: const Icon(Icons.egg_alt_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _skuCtr,
                      decoration: InputDecoration(
                        labelText: 'SKU (Optional)',
                        prefixIcon: const Icon(Icons.code),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeCtr,
                      decoration: InputDecoration(
                        labelText: 'Barcode (Optional)',
                        prefixIcon: const Icon(Icons.qr_code_2),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Category & Unit Row
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _category,
                      decoration: InputDecoration(
                        labelText: 'Category *',
                        prefixIcon: const Icon(Icons.category_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: IngredientModel.categories.map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Text(IngredientModel.categoryLabel(c)),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      decoration: InputDecoration(
                        labelText: 'Unit *',
                        prefixIcon: const Icon(Icons.scale_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: IngredientModel.units.map((u) {
                        return DropdownMenuItem(value: u, child: Text(u));
                      }).toList(),
                      onChanged: (v) => setState(() => _unit = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Cost & Initial Stock & Min Threshold
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costCtr,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: InputDecoration(
                        labelText: 'Cost/Unit *',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stockCtr,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: InputDecoration(
                        labelText: widget.existing == null ? 'Initial Stock' : 'Current Stock',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minThresholdCtr,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: InputDecoration(
                        labelText: 'Min Alert',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Perishable handling
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Is Perishable?', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Requires expiration tracking (FIFO)'),
                value: _isPerishable,
                activeColor: Colors.orange,
                onChanged: (v) {
                  setState(() {
                    _isPerishable = v;
                    if (!v) _shelfLifeCtr.clear();
                  });
                },
              ),

              if (_isPerishable) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _shelfLifeCtr,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Expected Shelf Life (Days) *',
                    prefixIcon: const Icon(Icons.timer_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (_isPerishable && v!.trim().isEmpty) return 'Required for perishable';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 24),

              // Allergens Selection
              const Text('Allergen Tags', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: IngredientModel.allergens.map((tag) {
                  final isSelected = _allergenTags.contains(tag);
                  return ChoiceChip(
                    label: Text(IngredientModel.allergenLabel(tag)),
                    selected: isSelected,
                    onSelected: (_) => _toggleAllergen(tag),
                    selectedColor: Colors.red.shade100,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.red.shade900 : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              // Buttons
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              widget.existing == null ? 'Add' : 'Save Changes',
                              style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
