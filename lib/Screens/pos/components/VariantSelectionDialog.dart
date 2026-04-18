// lib/Screens/pos/components/VariantSelectionDialog.dart

import 'package:flutter/material.dart';
import '../../../../../constants.dart';
import '../../../../../services/pos/pos_models.dart';

class VariantSelectionDialog extends StatefulWidget {
  final String productName;
  final Map<String, dynamic> variants;

  const VariantSelectionDialog({
    super.key,
    required this.productName,
    required this.variants,
  });

  @override
  State<VariantSelectionDialog> createState() => _VariantSelectionDialogState();
}

class _VariantSelectionDialogState extends State<VariantSelectionDialog> {
  final Set<String> _selectedVariantIds = {};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Customize Your Dish',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.deepPurple,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        widget.productName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Select Add-ons',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: widget.variants.entries.map((entry) {
                    final variantId = entry.key;
                    final variantData = entry.value as Map<String, dynamic>;
                    final name = variantData['name'] ?? '';
                    final price =
                        (variantData['variantprice'] as num?)?.toDouble() ??
                            0.0;
                    final isSelected = _selectedVariantIds.contains(variantId);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedVariantIds.remove(variantId);
                            } else {
                              _selectedVariantIds.add(variantId);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.deepPurple.withValues(alpha: 0.05)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.deepPurple
                                  : Colors.grey.withValues(alpha: 0.2),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.deepPurple
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.deepPurple
                                        : Colors.grey.withValues(alpha: 0.5),
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? Icon(Icons.check,
                                        size: 14, color: Theme.of(context).cardColor)
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.deepPurple
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                '+ ${AppConstants.currencySymbol}${price.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.deepPurple
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  final List<PosAddon> selectedAddons = [];
                  for (final id in _selectedVariantIds) {
                    final data = widget.variants[id] as Map<String, dynamic>;
                    selectedAddons.add(PosAddon(
                      name: data['name'] ?? '',
                      price: (data['variantprice'] as num?)?.toDouble() ?? 0.0,
                    ));
                  }
                  Navigator.pop(context, selectedAddons);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Confirm Choices',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
