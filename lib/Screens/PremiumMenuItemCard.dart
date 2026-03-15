import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // UserScopeService

class PremiumMenuItemCard extends StatelessWidget {
  final QueryDocumentSnapshot item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const PremiumMenuItemCard({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final data = item.data() as Map<String, dynamic>;
    final imageUrl = data['imageUrl'] as String?;
    final name = data['name'] ?? 'Unnamed Item';
    final nameAr = data['name_ar'] as String? ?? '';
    final description = data['description'] ?? 'No description';
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final discountedPrice = (data['discountedPrice'] as num?)?.toDouble();
    final discountExpiryTimestamp = data['discountExpiryDate'] as Timestamp?;
    final discountExpiryDate = discountExpiryTimestamp?.toDate();

    // Smart Reversion Logic: Check if discount is still valid
    final bool isDiscountValid = discountedPrice != null &&
        discountedPrice > 0 &&
        (discountExpiryDate == null ||
            DateTime.now().isBefore(discountExpiryDate));

    final bool hasDiscount = isDiscountValid;
    final isPopular = data['isPopular'] ?? false;
    final variants = data['variants'] as Map? ?? {};
    final tags = data['tags'] as Map? ?? {};

    final outOfStockBranches =
        List<String>.from(data['outOfStockBranches'] ?? []);
    final userScope = context.read<UserScopeService>();
    final isOutOfStock = userScope.branchIds.isNotEmpty &&
        outOfStockBranches.any((b) => userScope.branchIds.contains(b));
    // Combine variant/tag count for a clean summary
    final int variantCount = variants.length;
    final int tagCount = tags.entries.where((e) => e.value == true).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior:
          Clip.antiAlias, // Ensures clean rounded corners for the image
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. IMAGE SECTION (Fixed Height)
          Stack(
            children: [
              Container(
                height: 160,
                width: double.infinity,
                color: Colors.grey[100],
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
              // Overlays
              if (isPopular)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.star, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text('POPULAR',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              if (isOutOfStock)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.inventory_2_outlined,
                            size: 12, color: Colors.red),
                        SizedBox(width: 4),
                        Text('NO STOCK',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // 2. CONTENT SECTION
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (nameAr.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        nameAr,
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontFamily: 'NotoSansArabic',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Description
                  Text(
                    description,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[600], height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const Spacer(),

                  // Meta Info (Tags/Variants)
                  if (variantCount > 0 || tagCount > 0)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tagCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: tags.entries
                                  .where((e) => e.value == true)
                                  .map((e) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _getTagColor(e.key)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: _getTagColor(e.key)
                                                  .withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          e.key,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _getTagColor(e.key),
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        if (variantCount > 0)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$variantCount Options',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                      ],
                    ),

                  // 3. FOOTER (Price & Actions)
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasDiscount)
                            Text(
                              'QAR ${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          Text(
                            'QAR ${(hasDiscount ? discountedPrice : price).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: hasDiscount
                                  ? Colors.green
                                  : Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Actions
                      Row(
                        children: [
                          _ActionButton(
                            icon: Icons.edit_outlined,
                            color: Colors.deepPurple,
                            onTap: onEdit,
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: Icons.delete_outline,
                            color: Colors.red,
                            onTap: onDelete,
                          ),
                        ],
                      )
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.amber.shade50,
      child: Center(
        child: Icon(Icons.fastfood, color: Colors.amber.shade200, size: 48),
      ),
    );
  }

  Color _getTagColor(String tag) {
    switch (tag) {
      case 'Healthy':
        return Colors.green;
      case 'Vegetarian':
        return Colors.teal;
      case 'Vegan':
        return Colors.green.shade700;
      case 'Spicy':
        return Colors.red;
      case 'Popular':
        return Colors.amber;
      default:
        return Colors.deepPurple;
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
