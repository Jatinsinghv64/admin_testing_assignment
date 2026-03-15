import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import 'MenuManagementWidgets.dart';
import 'PremiumMenuItemCard.dart';
import 'DishEditScreenLarge.dart';
import '../Widgets/BranchFilterService.dart';

class MenuManagementScreenLarge extends StatefulWidget {
  const MenuManagementScreenLarge({super.key});

  @override
  State<MenuManagementScreenLarge> createState() =>
      _MenuManagementScreenLargeState();
}

class _MenuManagementScreenLargeState extends State<MenuManagementScreenLarge> {
  String? _selectedCategoryId;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Light background for contrast
      body: Row(
        children: [
          // LEFT PANE: CATEGORIES
          SizedBox(
            width: 350, // Fixed width for categories
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Column(
                children: [
                  _buildCategoriesHeader(),
                  Expanded(
                    child: _CategoriesList(
                      selectedCategoryId: _selectedCategoryId,
                      onCategorySelected: (id) =>
                          setState(() => _selectedCategoryId = id),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // RIGHT PANE: MENU ITEMS
          Expanded(
            child: Column(
              children: [
                _buildMenuItemsHeader(),
                Expanded(
                  child: _selectedCategoryId == null
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.restaurant_menu,
                                  size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('Select a category to view items',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 18)),
                            ],
                          ),
                        )
                      : _MenuItemsGrid(
                          categoryId: _selectedCategoryId!,
                          searchQuery: _searchQuery,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.02),
                offset: const Offset(0, 2),
                blurRadius: 4)
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Categories',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.deepPurple),
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => const CategoryDialog(),
                ),
                tooltip: 'Add Category',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItemsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.02),
                offset: const Offset(0, 2),
                blurRadius: 4)
          ]),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search items...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(width: 16),
          if (_selectedCategoryId != null)
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DishEditScreenLarge(),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoriesList extends StatelessWidget {
  final String? selectedCategoryId;
  final ValueChanged<String> onCategorySelected;

  const _CategoriesList({
    required this.selectedCategoryId,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    Query query = FirebaseFirestore.instance.collection('menu_categories');

    if (filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        query = query.where('branchIds', arrayContains: filterBranchIds.first);
      } else {
        query = query.where('branchIds', arrayContainsAny: filterBranchIds);
      }
    }
    query = query.orderBy('sortOrder');

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No categories found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final isSelected = doc.id == selectedCategoryId;

            // Simplified Card for List View
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => onCategorySelected(doc.id),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color:
                          isSelected ? Colors.deepPurple.shade50 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isSelected ? Colors.deepPurple : Colors.grey[200]!,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? []
                          : [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2))
                            ]),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            image: data['imageUrl'] != null &&
                                    data['imageUrl'].toString().isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(data['imageUrl']),
                                    fit: BoxFit.cover)
                                : null),
                        child: data['imageUrl'] == null ||
                                data['imageUrl'].toString().isEmpty
                            ? const Icon(Icons.category,
                                size: 20, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['name'] ?? 'Unnamed',
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isSelected
                                    ? Colors.deepPurple
                                    : Colors.black87,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${data['branchIds']?.length ?? 0} Branches',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            )
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        color: Colors.grey,
                        onPressed: () => showDialog(
                          context: context,
                          builder: (ctx) => CategoryDialog(doc: doc),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MenuItemsGrid extends StatelessWidget {
  final String categoryId;
  final String searchQuery;

  const _MenuItemsGrid({
    required this.categoryId,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    Query query = FirebaseFirestore.instance.collection('menu_items')
        .where('categoryId', isEqualTo: categoryId);

    if (filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        query = query.where('branchIds', arrayContains: filterBranchIds.first);
      } else {
        query = query.where('branchIds', arrayContainsAny: filterBranchIds);
      }
    }

    // Note: Firestore doesn't support multiple array-contains or complex ordering with inequality easily.
    // The original code sorted by sortOrder locally or in query if possible.
    // If I add orderBy('sortOrder') it might require composite index.
    // I'll stick to client-side sorting for simplicity if data set is small-ish,
    // OR just use default order. The original code used snapshots and then sort in memory.

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snapshot.data!.docs;

        // Client-side filtering for search
        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['name'] as String? ?? '').toLowerCase();
            final desc = (data['description'] as String? ?? '').toLowerCase();
            return name.contains(q) || desc.contains(q);
          }).toList();
        }

        // Client-side sorting
        docs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final sortA = (dataA['sortOrder'] as num?)?.toInt() ?? 0;
          final sortB = (dataB['sortOrder'] as num?)?.toInt() ?? 0;
          return sortA.compareTo(sortB);
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isNotEmpty
                      ? 'No items found matching "$searchQuery"'
                      : 'No items in this category',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }

// ... inside _MenuItemsGrid ...

        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent:
                300, // Reduced slightly to fit more columns if space permits
            mainAxisExtent:
                440, // INCREASED to fit all tags and variants without overflow
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            return PremiumMenuItemCard(
              item: doc,
              onEdit: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DishEditScreenLarge(doc: doc),
                ),
              ),
              onDelete: () => _deleteItem(context, doc),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteItem(BuildContext context, DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await doc.reference.delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Item deleted'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
