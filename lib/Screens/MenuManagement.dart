import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'BranchManagement.dart';
import '../main.dart';
import '../utils/responsive_helper.dart'; // âœ… Added
import '../services/image_upload_service.dart';
import 'MenuManagementScreenLarge.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabSelection);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Responsive Switch
    if (MediaQuery.of(context).size.width >= 900) {
      return const MenuManagementScreenLarge();
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Inventory Management',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: () {
                if (_tabController.index == 0) {
                  _showAddCategoryDialog(context);
                } else {
                  _showAddMenuItemDialog(context);
                }
              },
              tooltip: _tabController.index == 0 ? 'Add Category' : 'Add Item',
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorColor: Colors.deepPurple,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.category_outlined), text: 'Categories'),
            Tab(icon: Icon(Icons.restaurant_menu_outlined), text: 'Menu Items'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Enhanced Search Section
          Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: _tabController.index == 0
                    ? 'Search categories by name...'
                    : 'Search menu items by name...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.deepPurple.shade300,
                  size: 24,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query.toLowerCase();
                });
              },
            ),
          ),
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CategoriesTab(searchQuery: _searchQuery),
                _MenuItemsTab(searchQuery: _searchQuery),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CategoryDialog(),
    );
  }

  void _showAddMenuItemDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _MenuItemDialog(),
    );
  }
}

class _CategoriesTab extends StatefulWidget {
  final String searchQuery;

  const _CategoriesTab({super.key, required this.searchQuery});

  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final db = FirebaseFirestore.instance;

    Query query;
    if (userScope.isSuperAdmin) {
      query = db.collection('menu_categories').orderBy('sortOrder');
    } else if (userScope.branchIds.isNotEmpty) {
      query = db
          .collection('menu_categories')
          .where('branchIds', arrayContainsAny: userScope.branchIds)
          .orderBy('sortOrder');
    } else {
      return const Center(child: Text("Error: User scope not loaded."));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading categories...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          // ✅ CRITICAL FIX: Improved error handling with retry
          debugPrint('Categories StreamBuilder error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to load categories',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection and try again',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}), // Trigger rebuild
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No categories found.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your first category to get started.',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final filteredDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final nameAr = (data['name_ar'] ?? '').toString().toLowerCase();
          return name.contains(widget.searchQuery) ||
              nameAr.contains(widget.searchQuery);
        }).toList();

        if (filteredDocs.isEmpty && widget.searchQuery.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No categories match your search.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try a different search term.',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        // âœ… RESPONSIVE CATEGORIES GRID
        if (ResponsiveHelper.isTablet(context) ||
            ResponsiveHelper.isDesktop(context)) {
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: ResponsiveHelper.isDesktop(context) ? 4 : 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) {
              final category = filteredDocs[index];
              return _CategoryCard(
                category: category,
                onEdit: () => _showEditCategoryDialog(context, category),
                onDelete: () => _deleteCategory(context, category),
              );
            },
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: filteredDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final category = filteredDocs[index];
            return _CategoryCard(
              category: category,
              onEdit: () => _showEditCategoryDialog(context, category),
              onDelete: () => _deleteCategory(context, category),
            );
          },
        );
      },
    );
  }

  void _showEditCategoryDialog(
      BuildContext context, QueryDocumentSnapshot category) {
    showDialog(
      context: context,
      builder: (context) => _CategoryDialog(doc: category),
    );
  }

  Future<void> _deleteCategory(
      BuildContext context, QueryDocumentSnapshot category) async {
    final shouldDelete = await _confirmDelete(context, 'category');
    if (shouldDelete) {
      try {
        await category.reference.delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Category deleted successfully.'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to delete: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context, String itemType) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 28),
                const SizedBox(width: 12),
                Text('Delete ${itemType.capitalize()}?',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Are you sure you want to delete this $itemType? This action cannot be undone.',
              style: const TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Delete',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _CategoryCard extends StatelessWidget {
  final QueryDocumentSnapshot category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryCard({
    super.key,
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final data = category.data() as Map<String, dynamic>;
    final isActive = data['isActive'] ?? false;
    final imageUrl = data['imageUrl'] as String? ?? '';
    final name = data['name'] ?? 'Unnamed Category';
    final nameAr = data['name_ar'] as String? ?? '';
    final sortOrder = data['sortOrder'] ?? '0';
    final branchIds = List<String>.from(data['branchIds'] ?? []);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showCategoryDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.deepPurple.withOpacity(0.1),
                    ),
                    child: imageUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(Icons.category_rounded,
                                      color: Colors.deepPurple, size: 32),
                            ),
                          )
                        : Icon(Icons.category_rounded,
                            color: Colors.deepPurple, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (nameAr.isNotEmpty)
                                    Text(
                                      nameAr,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                        color: Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.rtl,
                                    ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: isActive,
                                onChanged: (value) async {
                                  await category.reference
                                      .update({'isActive': value});
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Category status updated to ${value ? "Active" : "Inactive"}!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                },
                                activeColor: Colors.green,
                                inactiveThumbColor: Colors.red,
                                inactiveTrackColor: Colors.red.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sort Order: $sortOrder',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Branches: ${branchIds.length}',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive
                            ? Colors.green.withOpacity(0.3)
                            : Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 16,
                          color: isActive ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isActive ? 'ACTIVE' : 'INACTIVE',
                          style: TextStyle(
                            color: isActive ? Colors.green : Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View Details'),
                      onPressed: () => _showCategoryDetails(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        side: BorderSide(
                            color: Colors.deepPurple.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                    onPressed: onEdit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red),
                      onPressed: onDelete,
                      tooltip: 'Delete Category',
                      padding: const EdgeInsets.all(12),
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

  void _showCategoryDetails(BuildContext context) {
    final data = category.data() as Map<String, dynamic>;
    final imageUrl = data['imageUrl'] as String?;
    final branchIds = data['branchIds'];
    final branchIdsText =
        branchIds != null && branchIds is List && branchIds.isNotEmpty
            ? branchIds.map((id) => id.toString()).join(', ')
            : 'Not assigned';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  gradient: LinearGradient(
                    colors: [
                      Colors.deepPurple.shade400,
                      Colors.deepPurple.shade600,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    if (imageUrl?.isNotEmpty == true)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20)),
                          child: Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildDefaultHeader(),
                          ),
                        ),
                      )
                    else
                      _buildDefaultHeader(),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 20,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['name'] ?? 'Category Details',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (data['name_ar'] != null &&
                              data['name_ar'].isNotEmpty)
                            Text(
                              data['name_ar'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.rtl,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: (data['isActive'] == true
                                      ? Colors.green
                                      : Colors.red)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (data['isActive'] == true
                                        ? Colors.green
                                        : Colors.red)
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  data['isActive'] == true
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: data['isActive'] == true
                                      ? Colors.green
                                      : Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  data['isActive'] == true
                                      ? 'ACTIVE'
                                      : 'INACTIVE',
                                  style: TextStyle(
                                    color: data['isActive'] == true
                                        ? Colors.green
                                        : Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'ID: ${category.id}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildEnhancedDetailSection(
                        'Configuration',
                        Icons.settings_outlined,
                        [
                          _buildEnhancedDetailRow(
                            Icons.sort_rounded,
                            'Sort Order',
                            (data['sortOrder'] ?? 0).toString(),
                          ),
                          _buildEnhancedDetailRow(
                            Icons.business_outlined,
                            'Branch IDs',
                            branchIdsText,
                            color: (branchIds != null &&
                                    branchIds is List &&
                                    branchIds.isNotEmpty)
                                ? Colors.blue
                                : Colors.grey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (imageUrl?.isNotEmpty == true) ...[
                        _buildEnhancedDetailSection(
                          'Media',
                          Icons.image_outlined,
                          [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Image URL:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    imageUrl!,
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit Category'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.deepPurple,
                                side: BorderSide(
                                    color: Colors.deepPurple.withOpacity(0.5)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                onDelete();
                              },
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade400,
            Colors.deepPurple.shade600,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Center(
        child: Icon(
          Icons.category_rounded,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }

  Widget _buildEnhancedDetailSection(
      String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: Colors.deepPurple,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedDetailRow(IconData icon, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? Colors.deepPurple.shade400),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: color ?? Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItemsTab extends StatefulWidget {
  final String searchQuery;

  const _MenuItemsTab({super.key, required this.searchQuery});

  @override
  State<_MenuItemsTab> createState() => _MenuItemsTabState();
}

class _MenuItemsTabState extends State<_MenuItemsTab> {
  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final db = FirebaseFirestore.instance;

    Query query;
    if (userScope.isSuperAdmin) {
      query = db.collection('menu_items').orderBy('sortOrder');
    } else if (userScope.branchIds.isNotEmpty) {
      query = db
          .collection('menu_items')
          .where('branchIds', arrayContainsAny: userScope.branchIds)
          .orderBy('sortOrder');
    } else {
      return const Center(child: Text("Error: User scope not loaded."));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading menu items...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          // ✅ CRITICAL FIX: Improved error handling with retry
          debugPrint('MenuItems StreamBuilder error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to load menu items',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection and try again',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}), // Trigger rebuild
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fastfood, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No menu items found.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your first menu item to get started.',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final filteredDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final nameAr = (data['name_ar'] ?? '').toString().toLowerCase();
          return name.contains(widget.searchQuery) ||
              nameAr.contains(widget.searchQuery);
        }).toList();

        if (filteredDocs.isEmpty && widget.searchQuery.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No menu items match your search.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try a different search term.',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        // âœ… RESPONSIVE MENU ITEMS GRID
        if (ResponsiveHelper.isTablet(context) ||
            ResponsiveHelper.isDesktop(context)) {
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: ResponsiveHelper.isDesktop(context) ? 4 : 3,
              crossAxisSpacing: 16,
              mainAxisSpacing:
                  16, // Adjusted specifically for menu item cards with images
              childAspectRatio: 0.75,
            ),
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) {
              final item = filteredDocs[index];
              return _MenuItemCard(
                item: item,
                onEdit: () => _showEditMenuItemDialog(context, item),
                onDelete: () => _deleteMenuItem(context, item),
              );
            },
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: filteredDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final item = filteredDocs[index];
            return _MenuItemCard(
              item: item,
              onEdit: () => _showEditMenuItemDialog(context, item),
              onDelete: () => _deleteMenuItem(context, item),
            );
          },
        );
      },
    );
  }

  void _showEditMenuItemDialog(
      BuildContext context, QueryDocumentSnapshot item) {
    showDialog(
      context: context,
      builder: (context) => _MenuItemDialog(doc: item),
    );
  }

  Future<void> _deleteMenuItem(
      BuildContext context, QueryDocumentSnapshot item) async {
    final shouldDelete = await _confirmDelete(context, 'menu item');
    if (shouldDelete) {
      try {
        await item.reference.delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Menu item deleted successfully.'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to delete: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context, String itemType) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 28),
                const SizedBox(width: 12),
                Text('Delete ${itemType.capitalize()}?',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Are you sure you want to delete this $itemType? This action cannot be undone.',
              style: const TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Delete',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _MenuItemCard extends StatelessWidget {
  final QueryDocumentSnapshot item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MenuItemCard({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final data = item.data() as Map<String, dynamic>;
    final isAvailable = data['isAvailable'] ?? false;
    final isPopular = data['isPopular'] ?? false;
    final imageUrl = data['imageUrl'] as String?;
    final name = data['name'] ?? 'Unnamed Item';
    final nameAr = data['name_ar'] as String? ?? '';
    final description = data['description'] ?? 'No description';
    final descriptionAr = data['description_ar'] as String? ?? '';
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final discountedPrice = (data['discountedPrice'] as num?)?.toDouble();
    final bool hasDiscount = discountedPrice != null && discountedPrice > 0;
    final variants = data['variants'] as Map? ?? {};
    final tags = data['tags'] as Map? ?? {};

    final outOfStockBranches =
        List<String>.from(data['outOfStockBranches'] ?? []);
    final userScope = context.read<UserScopeService>();
    final isOutOfStock = userScope.branchIds.isNotEmpty &&
        outOfStockBranches.any((b) => userScope.branchIds.contains(b));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showMenuItemDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.amber.withOpacity(0.1),
                    ),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                Icons.fastfood_rounded,
                                color: Colors.amber.shade600,
                                size: 40,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.fastfood_rounded,
                            color: Colors.amber.shade600,
                            size: 40,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (nameAr.isNotEmpty)
                                    Text(
                                      nameAr,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                        color: Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.rtl,
                                    ),
                                ],
                              ),
                            ),
                            if (isPopular)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Colors.amber.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'POPULAR',
                                      style: TextStyle(
                                        color: Colors.amber.shade700,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (descriptionAr.isNotEmpty)
                          Text(
                            descriptionAr,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
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
                            if (hasDiscount) ...[
                              const SizedBox(width: 8),
                              Text(
                                'QAR ${price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (variants.isNotEmpty || tags.isNotEmpty)
                const SizedBox(height: 16),
              if (variants.isNotEmpty || tags.isNotEmpty)
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.start,
                  children: [
                    // Combined list for display
                    ...[
                      if (variants.isNotEmpty)
                        {
                          'label':
                              '${variants.length} ${variants.length > 1 ? "Variants" : "Variant"}',
                          'type': 'variant'
                        },
                      ...tags.entries
                          .where((e) => e.value == true)
                          .map((e) => {'label': e.key, 'type': 'tag'}),
                    ].take(3).map((item) {
                      final isVariant = item['type'] == 'variant';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isVariant
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.deepPurple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: isVariant
                                  ? Colors.blue.withOpacity(0.2)
                                  : Colors.deepPurple.withOpacity(0.2)),
                        ),
                        child: Text(
                          item['label'] as String,
                          style: TextStyle(
                            color: isVariant
                                ? Colors.blue.shade700
                                : Colors.deepPurple.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }),
                    // Remaining count indicator
                    if ((variants.isNotEmpty ? 1 : 0) +
                            tags.entries.where((e) => e.value == true).length >
                        3)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: Text(
                          '+${((variants.isNotEmpty ? 1 : 0) + tags.entries.where((e) => e.value == true).length) - 3}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (isOutOfStock)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.orange.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2,
                                size: 12, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'OUT OF STOCK',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    // Invisible dummy switch for balancing centering
                    IgnorePointer(
                      child: Opacity(
                        opacity: 0.0,
                        child: Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: isAvailable,
                            onChanged:
                                (v) {}, // Dummy callback for size matching
                            activeColor: Colors.transparent,
                            inactiveThumbColor: Colors.transparent,
                            inactiveTrackColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isAvailable
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isAvailable
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.red.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAvailable
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 16,
                                color: isAvailable ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isAvailable ? 'AVAILABLE' : 'UNAVAILABLE',
                                style: TextStyle(
                                  color:
                                      isAvailable ? Colors.green : Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: isAvailable,
                        onChanged: (value) async {
                          await item.reference.update({'isAvailable': value});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Item ${value ? 'activated' : 'deactivated'}!',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                        activeColor: Colors.green,
                        inactiveThumbColor: Colors.red,
                        inactiveTrackColor: Colors.red.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                    onPressed: () => _showMenuItemDetails(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side:
                          BorderSide(color: Colors.deepPurple.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                    onPressed: onEdit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red),
                      onPressed: onDelete,
                      tooltip: 'Delete Menu Item',
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(),
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

  void _showMenuItemDetails(BuildContext context) {
    final data = item.data() as Map<String, dynamic>;
    final imageUrl = data['imageUrl'] as String?;
    final variants = (data['variants'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v as Map<String, dynamic>)) ??
        {};
    final tags = (data['tags'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v as bool)) ??
        {};
    final estimatedTime = data['EstimatedTime'] as String?;
    final branchIds = data['branchIds'];
    final branchIdsText =
        branchIds != null && branchIds is List && branchIds.isNotEmpty
            ? branchIds.map((id) => id.toString()).join(', ')
            : 'Not assigned';

    final outOfStockBranches =
        List<String>.from(data['outOfStockBranches'] ?? []);
    final userScope = context.read<UserScopeService>();
    final isOutOfStock = userScope.branchIds.isNotEmpty &&
        outOfStockBranches.any((b) => userScope.branchIds.contains(b));
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.shade400,
                      Colors.amber.shade600,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    if (imageUrl?.isNotEmpty == true)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20)),
                          child: Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildDefaultMenuHeader(),
                          ),
                        ),
                      )
                    else
                      _buildDefaultMenuHeader(),
                    if (data['isPopular'] == true)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withOpacity(0.3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.star, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'POPULAR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (isOutOfStock)
                      Positioned(
                        top: 16,
                        left: data['isPopular'] == true ? 100 : 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.inventory_2,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'OUT OF STOCK',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.7),
                              Colors.transparent,
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    data['name'] ?? 'Menu Item Details',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (data['name_ar'] != null &&
                                      data['name_ar'].isNotEmpty)
                                    Text(
                                      data['name_ar'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.rtl,
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'QAR ${(data['price'] as num? ?? 0.0).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: (data['isAvailable'] == true
                                      ? Colors.green
                                      : Colors.red)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (data['isAvailable'] == true
                                        ? Colors.green
                                        : Colors.red)
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  data['isAvailable'] == true
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: data['isAvailable'] == true
                                      ? Colors.green
                                      : Colors.red,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  data['isAvailable'] == true
                                      ? 'AVAILABLE'
                                      : 'UNAVAILABLE',
                                  style: TextStyle(
                                    color: data['isAvailable'] == true
                                        ? Colors.green
                                        : Colors.red,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'ID: ${item.id}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (data['description']?.isNotEmpty == true) ...[
                        Text(
                          data['description'],
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildEnhancedMenuDetailSection(
                        'Basic Information',
                        Icons.info_outline,
                        [
                          if (estimatedTime?.isNotEmpty == true)
                            _buildEnhancedMenuDetailRow(
                              Icons.timer_outlined,
                              'Estimated Time',
                              '$estimatedTime mins',
                              color: Colors.orange,
                            ),
                          _buildEnhancedMenuDetailRow(
                            Icons.category_outlined,
                            'Category ID',
                            data['categoryId'] ?? 'Uncategorized',
                            color: Colors.blue,
                          ),
                          _buildEnhancedMenuDetailRow(
                            Icons.business_outlined,
                            'Branch IDs',
                            branchIdsText,
                            color: (branchIds != null &&
                                    branchIds is List &&
                                    branchIds.isNotEmpty)
                                ? Colors.blue
                                : Colors.grey,
                          ),
                          _buildEnhancedMenuDetailRow(
                            Icons.inventory_2,
                            'Stock Status',
                            isOutOfStock ? 'Out of Stock' : 'In Stock',
                            color: isOutOfStock ? Colors.orange : Colors.green,
                          ),
                        ],
                      ),
                      if (variants.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildEnhancedMenuDetailSection(
                          'Variants',
                          Icons.tune_outlined,
                          [
                            ...variants.entries.map((variant) {
                              final variantName =
                                  variant.value['name'] as String? ??
                                      'Unnamed Variant';
                              final variantPrice =
                                  (variant.value['variantprice'] as num? ?? 0.0)
                                      .toStringAsFixed(2);
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.blue.withOpacity(0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.label_outline,
                                        size: 16, color: Colors.blue.shade600),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(variantName,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w500))),
                                    Text(
                                      '+QAR $variantPrice',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildEnhancedMenuDetailSection(
                          'Tags',
                          Icons.local_offer_outlined,
                          [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: tags.entries.map((entry) {
                                final isActive = entry.value == true;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Colors.deepPurple.withOpacity(0.1)
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isActive
                                          ? Colors.deepPurple.withOpacity(0.3)
                                          : Colors.grey.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.deepPurple.shade700
                                          : Colors.grey[600],
                                      fontSize: 12,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                onEdit();
                              },
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit Item'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.deepPurple,
                                side: BorderSide(
                                    color: Colors.deepPurple.withOpacity(0.5)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                onDelete();
                              },
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultMenuHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.shade400,
            Colors.amber.shade600,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Center(
        child: Icon(
          Icons.fastfood_rounded,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }

  Widget _buildEnhancedMenuDetailSection(
      String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: Colors.deepPurple,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedMenuDetailRow(IconData icon, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? Colors.deepPurple.shade400),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: color ?? Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

class _CategoryDialog extends StatefulWidget {
  final DocumentSnapshot? doc;
  const _CategoryDialog({this.doc});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _nameArController;
  late TextEditingController _imageUrlController;
  late TextEditingController _sortOrderController;
  late bool _isActive;
  late List<String> _selectedBranchIds;
  bool _isLoading = false;

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() as Map<String, dynamic>? ?? {};

    _nameController = TextEditingController(text: data['name'] ?? '');
    _nameArController = TextEditingController(text: data['name_ar'] ?? '');
    _imageUrlController = TextEditingController(text: data['imageUrl'] ?? '');
    _sortOrderController =
        TextEditingController(text: (data['sortOrder'] ?? 0).toString());
    _isActive = data['isActive'] ?? true;
    _selectedBranchIds = List<String>.from(data['branchIds'] ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameArController.dispose();
    _imageUrlController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _saveCategory() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    final userScope = context.read<UserScopeService>();
    final db = FirebaseFirestore.instance;

    final String name = _nameController.text.trim();
    final String nameAr = _nameArController.text.trim();
    List<String> branchIdsToSave;

    if (userScope.isSuperAdmin) {
      branchIdsToSave = _selectedBranchIds;
      if (branchIdsToSave.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Super Admins must select at least one branch.')),
        );
        setState(() => _isLoading = false);
        return;
      }
    } else {
      // ✅ CRITICAL FIX: Safe null handling for branchId
      final branchId = userScope.branchIds.isNotEmpty ? userScope.branchIds.first : null;
      if (branchId == null) {
        if (!mounted) return;
        _showError('No branch assigned. Please contact administrator.');
        setState(() => _isLoading = false);
        return;
      }
      branchIdsToSave = [branchId];
    }

    final data = {
      'name': name,
      'name_ar': nameAr,
      'imageUrl': _imageUrlController.text.trim(),
      'isActive': _isActive,
      'branchIds': branchIdsToSave,
      'sortOrder': int.tryParse(_sortOrderController.text) ?? 0,
    };

    try {
      if (_isEdit) {
        await db.collection('menu_categories').doc(widget.doc!.id).update(data);
      } else {
        await db.collection('menu_categories').add(data);
      }

      if (mounted) {
        _showSuccess('Category ${_isEdit ? 'updated' : 'added'} successfully!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showError('Error saving category: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
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

  Future<String?> pickAndUploadWebP({
    required BuildContext context,
    required String storageFolder,
    int quality = 90,
    int minWidth = 800,
    int minHeight = 800,
  }) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: minWidth.toDouble(),
        maxHeight: minHeight.toDouble(),
        imageQuality: quality,
      );

      if (image == null) return null;

      if (!mounted) return null;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Uploading image...'),
            ],
          ),
        ),
      );

      final String downloadUrl = await _convertAndUploadImage(
        image.path,
        storageFolder,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }

      return downloadUrl;
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<String> _convertAndUploadImage(
    String imagePath,
    String storageFolder,
  ) async {
    try {
      final File imageFile = File(imagePath);
      final String fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${imageFile.uri.pathSegments.last}';
      final String storagePath = '$storageFolder/$fileName';

      final Reference storageRef =
          FirebaseStorage.instance.ref().child(storagePath);
      final UploadTask uploadTask = storageRef.putFile(imageFile);

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to process image: $e');
    }
  }

  Future<void> _uploadMenuImage() async {
    final url = await pickAndUploadWebP(
      context: context,
      storageFolder: 'menu_categories',
      quality: 90,
      minWidth: 800,
      minHeight: 800,
    );
    if (url != null) {
      setState(() => _imageUrlController.text = url);
      _showSuccess('Image uploaded successfully!');
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.deepPurple,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final isSuperAdmin = userScope.isSuperAdmin;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEdit ? 'Edit Category' : 'Add Category',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSectionHeader(
                        'Basic Information', Icons.info_outline),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Category Name *',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (val) =>
                          val!.isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameArController,
                      decoration: const InputDecoration(
                        labelText: 'Category Name (Arabic)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      textDirection: TextDirection.rtl,
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sortOrderController,
                      decoration: const InputDecoration(
                        labelText: 'Sort Order',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        helperText: 'Lower numbers appear first',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    _buildSectionHeader('Media', Icons.image),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _imageUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Image URL',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _uploadMenuImage,
                          icon: const Icon(Icons.cloud_upload, size: 18),
                          label: const Text('Upload'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(height: 12),
                    if (isSuperAdmin)
                      MultiBranchSelector(
                        selectedIds: _selectedBranchIds,
                        onChanged: (selected) {
                          setState(() => _selectedBranchIds = selected);
                        },
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[100]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.business,
                                color: Colors.blue[600], size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auto-assigned Branch',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                  Text(
                                    userScope.branchIds.isNotEmpty ? userScope.branchIds.first : 'Not assigned',
                                    style: TextStyle(
                                      color: Colors.blue[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Status', Icons.power_settings_new),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Active Category',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          _isActive
                              ? 'Category is visible to customers'
                              : 'Category is hidden from customers',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        value: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                        activeColor: Colors.green,
                        secondary: Icon(
                          _isActive
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: _isActive ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveCategory,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(_isEdit ? 'Update Category' : 'Add Category'),
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

class _MenuItemDialog extends StatefulWidget {
  final DocumentSnapshot? doc;
  const _MenuItemDialog({this.doc});

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final RecipeService _recipeService;
  late final IngredientService _ingredientService;
  late TextEditingController _nameController;
  late TextEditingController _nameArController;
  late TextEditingController _descController;
  late TextEditingController _descArController;
  late TextEditingController _priceController;
  late TextEditingController _imageUrlController;
  late TextEditingController _estimatedTimeController;
  late TextEditingController _sortOrderController;
  late TextEditingController _discountedPriceController;
  late TextEditingController _caloriesController;
  late bool _isAvailable;
  late bool _isPopular;
  late bool _isOutOfStock;
  late bool _isHealthy;
  late bool _isSpicy;
  late bool _isVeg;
  int _preparationTime = 15;
  String? _selectedCategoryId;
  late List<String> _selectedBranchIds;
  bool _isLoading = false;

  // Recipe link state
  String? _linkedRecipeId;
  String? _linkedRecipeName;
  int? _linkedPrepTimeMinutes;
  List<String> _linkedAllergens = [];
  double _foodCostPct = 0.0;
  List<Map<String, dynamic>> _allRecipes = [];
  bool _loadingRecipes = true;

  // Integrated Recipe Editor state
  List<RecipeIngredientLine> _ingredientLines = [];
  List<String> _instructions = [''];
  double _liveRecipeCost = 0.0;
  List<IngredientModel> _allIngredients = [];
  bool _loadingIngredients = true;

  // Preparation time options in 5-minute intervals
  static const List<int> _prepTimeOptions = [
    5,
    10,
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
    55,
    60
  ];

  final List<Map<String, dynamic>> _variants = [];
  final Map<String, bool> _tags = {
    'Vegan': false,
    'Gluten-Free': false,
    'Vegetarian': false,
    'Spicy': false,
    'Healthy': false,
  };

  bool get _isEdit => widget.doc != null;

  String _getStringFromDynamic(dynamic value, [String defaultValue = '']) {
    if (value == null) return defaultValue;
    if (value is String) return value;
    if (value is num) return value.toString();
    return defaultValue;
  }

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() as Map<String, dynamic>? ?? {};

    _nameController = TextEditingController(text: data['name'] ?? '');
    _nameArController = TextEditingController(text: data['name_ar'] ?? '');
    _descController = TextEditingController(text: data['description'] ?? '');
    _descArController =
        TextEditingController(text: data['description_ar'] ?? '');
    _priceController =
        TextEditingController(text: (data['price'] as num?)?.toString() ?? '');
    _imageUrlController = TextEditingController(text: data['imageUrl'] ?? '');
    _discountedPriceController = TextEditingController(
        text: (data['discountedPrice'] as num?)?.toString() ?? '');
    _estimatedTimeController = TextEditingController(
        text: _getStringFromDynamic(data['EstimatedTime'], '25-35'));
    _sortOrderController = TextEditingController(
        text: _getStringFromDynamic(data['sortOrder'], '0'));

    _isAvailable = data['isAvailable'] ?? true;
    _isPopular = data['isPopular'] ?? false;
    _isHealthy = data['tags']?['Healthy'] ?? false;
    _isSpicy = data['tags']?['Spicy'] ?? false;
    _isVeg = data['isVeg'] ?? false;
    _preparationTime = (data['preparationTime'] as num?)?.toInt() ?? 15;
    _caloriesController = TextEditingController(
        text: (data['calories'] as num?)?.toString() ?? '');
    _selectedCategoryId = data['categoryId'];
    _selectedBranchIds = List<String>.from(data['branchIds'] ?? []);

    final variantsData = data['variants'] as Map<String, dynamic>? ?? {};
    _variants.addAll(variantsData.entries.map((entry) => {
          'id': entry.key,
          'name': entry.value['name'] ?? '',
          'variantprice':
              (entry.value['variantprice'] as num?)?.toDouble() ?? 0.0,
        }));

    final tagsData = data['tags'] as Map<String, dynamic>? ?? {};
    _tags.forEach((key, value) {
      _tags[key] = tagsData[key] ?? false;
    });

    final userScope = context.read<UserScopeService>();
    final currentBranch = userScope.branchIds.isNotEmpty ? userScope.branchIds.first : null;
    final outOfStockBranches =
        List<String>.from(data['outOfStockBranches'] ?? []);
    _isOutOfStock =
        currentBranch != null && outOfStockBranches.contains(currentBranch);

    // Load existing recipe link
    _linkedRecipeId = data['recipeId'] as String?;

    // Fetch all recipes async for the picker
    FirebaseFirestore.instance
        .collection('recipes')
        .where('isActive', isEqualTo: true)
        .orderBy('name')
        .get()
        .then((snap) {
      if (!mounted) return;
      final recipes = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      setState(() {
        _allRecipes = recipes;
        _loadingRecipes = false;
        // Auto-fill from existing linked recipe
        if (_linkedRecipeId != null) {
          _applyRecipeLink(
              recipes.firstWhere((r) => r['id'] == _linkedRecipeId,
                  orElse: () => {}),
              currentPrice: double.tryParse(_priceController.text) ?? 0.0);
        }
      });
    }).catchError((_) {
      if (mounted) setState(() => _loadingRecipes = false);
    });

    if (_linkedRecipeId != null) {
      _loadLinkedRecipeDetails(_linkedRecipeId!);
    }
  }

  Future<void> _loadIngredients() async {
    final userScope = context.read<UserScopeService>();
    final branchIds = userScope.branchIds;
    _ingredientService.streamAllIngredients(branchIds).listen((snap) {
      if (mounted) {
        setState(() {
          _allIngredients = snap;
          _loadingIngredients = false;
        });
        _recalcLiveRecipeCost();
      }
    });
  }

  Future<void> _loadLinkedRecipeDetails(String recipeId) async {
    try {
      final recipe = await _recipeService.getRecipe(recipeId);
      if (recipe != null && mounted) {
        setState(() {
          _ingredientLines = List.from(recipe.ingredients);
          _instructions = recipe.instructions.isNotEmpty 
              ? List.from(recipe.instructions) 
              : [''];
          _recalcLiveRecipeCost();
        });
      }
    } catch (e) {
      debugPrint('Error loading recipe details: $e');
    }
  }

  void _recalcLiveRecipeCost() {
    double cost = 0.0;
    for (final line in _ingredientLines) {
      final ingredient = _allIngredients.where((i) => i.id == line.ingredientId).firstOrNull;
      if (ingredient != null) {
        cost += ingredient.costPerUnit * line.quantity;
      }
    }
    setState(() {
      _liveRecipeCost = cost;
      final currentPrice = double.tryParse(_priceController.text) ?? 0.0;
      _foodCostPct = (currentPrice > 0 && cost > 0) ? (cost / currentPrice) * 100 : 0.0;
    });
  }

  void _applyRecipeLink(Map<String, dynamic> recipe,
      {double currentPrice = 0.0}) {
    if (recipe.isEmpty) return;
    final cost = (recipe['totalCost'] as num?)?.toDouble() ?? 0.0;
    // allergenWarnings is stored on the recipe's ingredients — we use tag hints
    // from ingredient allergenTags that were baked into the recipe ingredients list
    final allergens = List<String>.from(recipe['allergenTags'] ?? []);
    final prepMins = (recipe['prepTimeMinutes'] as num?)?.toInt();
    setState(() {
      _linkedRecipeId = recipe['id'] as String?;
      _linkedRecipeName = recipe['name'] as String?;
      _linkedPrepTimeMinutes = prepMins;
      _linkedAllergens = allergens;
      _foodCostPct =
          (currentPrice > 0 && cost > 0) ? (cost / currentPrice) * 100 : 0.0;
      // Auto-fill prep time in the dropdown if available
      if (prepMins != null) _preparationTime = prepMins.clamp(5, 60);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameArController.dispose();
    _descController.dispose();
    _descArController.dispose();
    _priceController.dispose();
    _imageUrlController.dispose();
    _estimatedTimeController.dispose();
    _sortOrderController.dispose();
    _discountedPriceController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  Future<void> _saveMenuItem() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    final userScope = context.read<UserScopeService>();
    final db = FirebaseFirestore.instance;

    List<String> branchIdsToSave;
    if (userScope.isSuperAdmin) {
      branchIdsToSave = _selectedBranchIds;
      if (branchIdsToSave.isEmpty) {
        if (!mounted) return;
        _showError('Please select at least one branch');
        setState(() => _isLoading = false);
        return;
      }
    } else {
      // ✅ CRITICAL FIX: Safe null handling for branchId
      final branchId = userScope.branchIds.isNotEmpty ? userScope.branchIds.first : null;
      if (branchId == null) {
        if (!mounted) return;
        _showError('No branch assigned. Please contact administrator.');
        setState(() => _isLoading = false);
        return;
      }
      branchIdsToSave = [branchId];
    }

    final Map<String, Map<String, dynamic>> variantsMap = {};
    for (var variant in _variants) {
      if (variant['name'].toString().isNotEmpty) {
        variantsMap[variant['id']] = {
          'name': variant['name'],
          'variantprice': variant['variantprice'],
        };
      }
    }

    final double? discountedPrice =
        double.tryParse(_discountedPriceController.text);

    // âœ… CRITICAL FIX: Prepare the base data map
    // We do NOT include 'outOfStockBranches' here for edits to avoid the race condition.
    final data = {
      'name': _nameController.text.trim(),
      'name_ar': _nameArController.text.trim(),
      'description': _descController.text.trim(),
      'description_ar': _descArController.text.trim(),
      'price': double.tryParse(_priceController.text) ?? 0.0,
      'discountedPrice': (discountedPrice != null && discountedPrice > 0)
          ? discountedPrice
          : null,
      'imageUrl': _imageUrlController.text.trim(),
      'EstimatedTime': _estimatedTimeController.text.trim(),
      'sortOrder': int.tryParse(_sortOrderController.text) ?? 0,
      'isAvailable': _isAvailable,
      'isPopular': _isPopular,
      'isVeg': _isVeg,
      'calories': int.tryParse(_caloriesController.text.trim()),
      'preparationTime': _preparationTime,
      'categoryId': _selectedCategoryId,
      'branchIds': branchIdsToSave,
      'tags': _tags,
      'variants': variantsMap.isNotEmpty ? variantsMap : null,
      'lastUpdated': FieldValue.serverTimestamp(),
      // Recipe link fields
      'recipeId': _linkedRecipeId,
      'prepTimeMinutes': _preparationTime,
      'allergenWarnings': _linkedAllergens,
      'foodCostPercentage': _foodCostPct > 0 ? _foodCostPct : null,
    };

    try {
      // ── Handle Recipe saving/updating ──
      String? finalRecipeId = _linkedRecipeId;
      if (_ingredientLines.isNotEmpty || _instructions.any((s) => s.trim().isNotEmpty)) {
        final cleanInstructions = _instructions.where((s) => s.trim().isNotEmpty).toList();
        final cleanIngredients = _ingredientLines.where((l) => l.ingredientId.isNotEmpty).toList();

        if (cleanInstructions.isNotEmpty || cleanIngredients.isNotEmpty) {
          if (finalRecipeId != null) {
            final existingRecipe = await _recipeService.getRecipe(finalRecipeId);
            if (existingRecipe != null) {
              final updatedRecipe = existingRecipe.copyWith(
                branchIds: branchIdsToSave,
                name: _nameController.text.trim(),
                description: _descController.text.trim(),
                ingredients: cleanIngredients,
                totalCost: _liveRecipeCost,
                instructions: cleanInstructions,
                prepTimeMinutes: _preparationTime,
                linkedMenuItemId: widget.doc?.id,
                linkedMenuItemName: _nameController.text.trim(),
                updatedAt: DateTime.now(),
              );
              await _recipeService.updateRecipe(updatedRecipe);
            }
          } else {
            final newRecipeId = db.collection('recipes').doc().id;
            final newRecipe = RecipeModel(
              id: newRecipeId,
              branchIds: branchIdsToSave,
              name: _nameController.text.trim(),
              description: _descController.text.trim(),
              ingredients: cleanIngredients,
              totalCost: _liveRecipeCost,
              instructions: cleanInstructions,
              prepTimeMinutes: _preparationTime,
              yield_: '',
              servingSize: '',
              difficultyLevel: 'medium',
              categoryTags: [],
              allergenTags: [],
              photoUrls: [],
              linkedMenuItemId: widget.doc?.id,
              linkedMenuItemName: _nameController.text.trim(),
              isActive: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            await _recipeService.addRecipe(newRecipe);
            finalRecipeId = newRecipeId;
          }
        }
      }

      data['recipeId'] = finalRecipeId;

      if (_isEdit) {
        // âœ… CRITICAL FIX: Atomic Stock Updates
        // If we are editing and have a valid branch context, we add atomic operations
        // to the update map instead of overwriting the whole array.
        if (userScope.branchIds.isNotEmpty) {
          if (_isOutOfStock) {
            data['outOfStockBranches'] =
                FieldValue.arrayUnion([userScope.branchIds.first]);
          } else {
            data['outOfStockBranches'] =
                FieldValue.arrayRemove([userScope.branchIds.first]);
          }
        }

        await db.collection('menu_items').doc(widget.doc!.id).update(data);
        _showSuccess('Menu item updated successfully!');
      } else {
        // For CREATE, we use the list logic because there is no document to race against.
        // If we are creating as a specific branch admin (and marking it OOS immediately):
        final branchId = userScope.branchIds.isNotEmpty ? userScope.branchIds.first : null;
        if (_isOutOfStock && branchId != null) {
          data['outOfStockBranches'] = [branchId];
        } else {
          data['outOfStockBranches'] = [];
        }

        await db.collection('menu_items').add(data);
        _showSuccess('Menu item added successfully!');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Error saving menu item: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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

  Future<String?> pickAndUploadWebP({
    required BuildContext context,
    required String storageFolder,
    int quality = 90,
    int minWidth = 800,
    int minHeight = 800,
  }) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: minWidth.toDouble(),
        maxHeight: minHeight.toDouble(),
        imageQuality: quality,
      );

      if (image == null) return null;

      if (!mounted) return null;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Uploading image...'),
            ],
          ),
        ),
      );

      final String downloadUrl = await _convertAndUploadImage(
        image.path,
        storageFolder,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }

      return downloadUrl;
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<String> _convertAndUploadImage(
    String imagePath,
    String storageFolder,
  ) async {
    try {
      final File imageFile = File(imagePath);
      final String fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${imageFile.uri.pathSegments.last}';
      final String storagePath = '$storageFolder/$fileName';

      final Reference storageRef =
          FirebaseStorage.instance.ref().child(storagePath);
      final UploadTask uploadTask = storageRef.putFile(imageFile);

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to process image: $e');
    }
  }

  Future<void> _uploadMenuImage() async {
    final url = await pickAndUploadWebP(
      context: context,
      storageFolder: 'menu_items',
      quality: 90,
      minWidth: 1200,
      minHeight: 1200,
    );
    if (url != null) {
      if (!mounted) return;
      setState(() => _imageUrlController.text = url);
      _showSuccess('Image uploaded successfully!');
    }
  }
  Widget _sectionLabel(String label) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
              color: Colors.deepPurple, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
      ],
    );
  }

  Widget _buildIngredientTable() {
    if (_ingredientLines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400, size: 32),
            const SizedBox(height: 12),
            Text('No ingredients added yet.', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return Column(
      children: List.generate(_ingredientLines.length, (idx) {
        return _buildIngredientRow(idx, _ingredientLines[idx]);
      }),
    );
  }

  Widget _buildIngredientRow(int idx, RecipeIngredientLine line) {
    final selectedIngredient = _allIngredients.where((i) => i.id == line.ingredientId).firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), shape: BoxShape.circle),
                child: Text('${idx + 1}', style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: line.ingredientId.isNotEmpty ? line.ingredientId : null,
                  hint: const Text('Select Ingredient', style: TextStyle(fontSize: 13)),
                  isExpanded: true,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  items: _allIngredients.map((i) => DropdownMenuItem(
                    value: i.id,
                    child: Text(i.name, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (newId) {
                    if (newId == null) return;
                    final ing = _allIngredients.where((i) => i.id == newId).firstOrNull;
                    if (ing == null) return;
                    setState(() {
                      _ingredientLines[idx] = line.copyWith(
                        ingredientId: newId,
                        ingredientName: ing.name,
                        unit: ing.unit,
                      );
                      _recalcLiveRecipeCost();
                    });
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () {
                  setState(() {
                    _ingredientLines.removeAt(idx);
                    _recalcLiveRecipeCost();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 40),
              SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: line.quantity > 0 ? line.quantity.toString() : '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final qty = double.tryParse(v) ?? 0;
                    setState(() {
                      _ingredientLines[idx] = line.copyWith(quantity: qty);
                      _recalcLiveRecipeCost();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Text(selectedIngredient?.unit ?? line.unit, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsList() {
    return Column(
      children: List.generate(_instructions.length, (idx) {
        return _buildInstructionRow(idx, _instructions[idx], key: ValueKey('step_$idx'));
      }),
    );
  }

  Widget _buildInstructionRow(int idx, String text, {required Key key}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26, height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), shape: BoxShape.circle),
            child: Text('${idx + 1}', style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: text,
              maxLines: null,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Describe this step...',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) => _instructions[idx] = v,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.grey, size: 18),
            onPressed: () => setState(() => _instructions.removeAt(idx)),
          ),
        ],
      ),
    );
  }

  final List<Map<String, dynamic>> _commonAllergens = [
    {'label': 'Dairy', 'icon': Icons.water_drop, 'color': Colors.blue},
    {'label': 'Eggs', 'icon': Icons.egg, 'color': Colors.orangeAccent},
    {'label': 'Gluten', 'icon': Icons.local_pizza, 'color': Colors.amber},
    {'label': 'Nuts', 'icon': Icons.cookie, 'color': Colors.brown},
    {'label': 'Soy', 'icon': Icons.grass, 'color': Colors.green},
    {'label': 'Fish', 'icon': Icons.set_meal, 'color': Colors.teal},
    {'label': 'Shellfish', 'icon': Icons.bug_report, 'color': Colors.redAccent},
  ];

  void _showAllergenDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Edit Allergen Profile'),
              content: SizedBox(
                width: 400,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _commonAllergens.map((alg) {
                    final label = alg['label'] as String;
                    final isSelected = _linkedAllergens.contains(label);
                    return FilterChip(
                      selected: isSelected,
                      label: Text(label),
                      avatar: Icon(alg['icon'] as IconData, color: alg['color'] as Color, size: 16),
                      onSelected: (val) {
                        setStateDialog(() {
                          if (val) {
                            _linkedAllergens.add(label);
                          } else {
                            _linkedAllergens.remove(label);
                          }
                        });
                        setState(() {}); // update main screen
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAllergenProfileCard() {
    final activeAllergens = _commonAllergens.where((a) => _linkedAllergens.contains(a['label'])).toList();
    
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Allergen Profile', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
              IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.deepPurple), onPressed: _showAllergenDialog),
            ],
          ),
          const SizedBox(height: 12),
          if (activeAllergens.isEmpty)
             const Text('No allergens selected.', style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            Wrap(
              spacing: 8, runSpacing: 8,
              children: activeAllergens.map((a) => Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a['icon'] as IconData, color: a['color'] as Color, size: 14),
                    const SizedBox(width: 6),
                    Text(a['label'] as String, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildInventoryForecastCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           const Text('Inventory Forecast', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
           const SizedBox(height: 12),
           const Text('Link a recipe and maintain ingredient stock to enable forecasting.', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildWeeklySalesCard() {
    final heights = [0.4, 0.35, 0.55, 0.60, 0.85, 1.0, 0.90];
    final labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weekly Sales', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    child: FractionallySizedBox(
                      heightFactor: heights[i],
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(heights[i] > 0.8 ? 1.0 : heights[i] > 0.5 ? 0.6 : 0.2),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2))
                        ),
                      ),
                    ),
                  )
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: labels.map((l) => Expanded(child: Center(child: Text(l, style: const TextStyle(color: Colors.grey, fontSize: 10))))).toList(),
          )
        ],
      )
    );
  }

  void _showMultiSelect() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Branches'),
        content: SizedBox(
          width: double.maxFinite,
          child: MultiBranchSelector(
            selectedIds: _selectedBranchIds,
            onChanged: (selected) {
              if (!mounted) return;
              setState(() => _selectedBranchIds = selected);
              Navigator.of(context).pop();
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _addVariant() {
    if (!mounted) return;
    setState(() {
      _variants.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': '',
        'variantprice': 0.0,
      });
    });
  }

  void _updateVariant(int index, Map<String, dynamic> updatedVariant) {
    if (!mounted) return;
    setState(() {
      _variants[index] = updatedVariant;
    });
  }

  void _removeVariant(int index) {
    if (!mounted) return;
    setState(() {
      _variants.removeAt(index);
    });
  }

  Widget _buildVariantField(Map<String, dynamic> variant, int index) {
    final nameController = TextEditingController(text: variant['name'] ?? '');
    final priceController = TextEditingController(
        text: (variant['variantprice'] as num?)?.toStringAsFixed(2) ?? '0.00');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.label_outline,
                    size: 20, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text(
                  'Variant ${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.deepPurple,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  onPressed: () => _removeVariant(index),
                  tooltip: 'Remove Variant',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Variant Name *',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a name';
                }
                return null;
              },
              onChanged: (value) {
                variant['name'] = value;
                _updateVariant(index, variant);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: priceController,
              decoration: const InputDecoration(
                labelText: 'Additional Price *',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                prefixText: 'QAR ',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a price';
                }
                if (double.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }
                return null;
              },
              onChanged: (value) {
                variant['variantprice'] = double.tryParse(value) ?? 0.0;
                _updateVariant(index, variant);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.deepPurple,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow(
      String title, bool value, IconData icon, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Row(
          children: [
            Icon(icon,
                size: 20, color: value ? Colors.deepPurple : Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: value ? Colors.deepPurple : Colors.grey[800],
              ),
            ),
          ],
        ),
        value: value,
        onChanged: onChanged,
        activeColor: Colors.deepPurple,
      ),
    );
  }

  Widget _buildRecipeInfoRow(IconData icon, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? Colors.deepPurple.shade400),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  color: color ?? Colors.deepPurple.shade700,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _showRecipePickerDialog() async {
    String localSearch = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Link Recipe',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search recipes…',
                    prefixIcon:
                        Icon(Icons.search, color: Colors.deepPurple.shade300),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.deepPurple, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      setLocal(() => localSearch = v.toLowerCase()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Builder(builder: (_) {
                    final filtered = _allRecipes.where((r) {
                      final name = r['name']?.toString().toLowerCase() ?? '';
                      return localSearch.isEmpty || name.contains(localSearch);
                    }).toList();
                    if (filtered.isEmpty) {
                      return const Center(
                          child: Text('No recipes found',
                              style: TextStyle(color: Colors.grey)));
                    }
                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final recipe = filtered[i];
                        final isSelected = recipe['id'] == _linkedRecipeId;
                        return ListTile(
                          dense: true,
                          title: Text(recipe['name'] ?? '',
                              style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.deepPurple
                                      : Colors.black87)),
                          subtitle: Text(
                            'Cost: QAR ${((recipe['totalCost'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle,
                                  color: Colors.deepPurple)
                              : null,
                          onTap: () {
                            _applyRecipeLink(recipe,
                                currentPrice:
                                    double.tryParse(_priceController.text) ??
                                        0.0);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final isSuperAdmin = userScope.isSuperAdmin;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEdit ? 'Edit Menu Item' : 'Add Menu Item',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSectionHeader(
                        'Basic Information', Icons.info_outline),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Item Name *',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (val) =>
                          val!.isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameArController,
                      decoration: const InputDecoration(
                        labelText: 'Item Name (Arabic)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      textDirection: TextDirection.rtl,
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descArController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (Arabic)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _priceController,
                            decoration: const InputDecoration(
                              labelText: 'Price (QAR) *',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixText: 'QAR ',
                            ),
                            keyboardType:
                                TextInputType.numberWithOptions(decimal: true),
                            validator: (val) =>
                                val!.isEmpty ? 'Price is required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _discountedPriceController,
                            decoration: const InputDecoration(
                              labelText: 'Discounted Price',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixText: 'QAR ',
                              helperText: 'Optional',
                            ),
                            keyboardType:
                                TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Calories and Preparation Time in one row
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _caloriesController,
                            decoration: const InputDecoration(
                              labelText: 'Calories',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              suffixText: 'kcal',
                              helperText: 'Optional',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _preparationTime,
                            decoration: const InputDecoration(
                              labelText: 'Prep Time *',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: _prepTimeOptions.map((time) {
                              return DropdownMenuItem<int>(
                                value: time,
                                child: Text('$time mins'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _preparationTime = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _estimatedTimeController,
                            decoration: const InputDecoration(
                              labelText: 'Est. Delivery Time',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              suffixText: 'mins',
                              helperText: 'e.g., 25-35',
                            ),
                            keyboardType: TextInputType.text,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _sortOrderController,
                            decoration: const InputDecoration(
                              labelText: 'Sort Order',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              helperText: 'Lower = first',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Category', Icons.category),
                    const SizedBox(height: 12),
                    _CategoryDropdown(
                      selectedId: _selectedCategoryId,
                      userScope: userScope,
                      onChanged: (id) =>
                          setState(() => _selectedCategoryId = id),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Media', Icons.image),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _imageUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Image URL',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _uploadMenuImage,
                          icon: const Icon(Icons.cloud_upload, size: 18),
                          label: const Text('Upload'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Branch Assignment', Icons.business),
                    const SizedBox(height: 12),
                    if (isSuperAdmin)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.business,
                                    color: Colors.deepPurple, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'Select Branches',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_selectedBranchIds.length} selected',
                                  style: TextStyle(
                                    color: Colors.deepPurple,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _showMultiSelect,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                minimumSize: const Size(double.infinity, 44),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.business_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Choose Branches'),
                                ],
                              ),
                            ),
                            if (_selectedBranchIds.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _selectedBranchIds.map((branchId) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.deepPurple.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: Colors.deepPurple
                                              .withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      branchId,
                                      style: const TextStyle(
                                        color: Colors.deepPurple,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[100]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.business,
                                color: Colors.blue[600], size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auto-assigned Branch',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                  Text(
                                    userScope.branchIds.isNotEmpty ? userScope.branchIds.first : 'Not assigned',
                                    style: TextStyle(
                                      color: Colors.blue[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Variants', Icons.tune),
                    const SizedBox(height: 12),
                    ..._variants.asMap().entries.map((entry) {
                      return _buildVariantField(entry.value, entry.key);
                    }).toList(),
                    if (_variants.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: const Center(
                          child: Text(
                            'No variants added',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _addVariant,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Variant'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Tags & Attributes', Icons.local_offer),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        children: [
                          // Veg/Non-Veg Toggle with visual indicator
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isVeg
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _isVeg ? Colors.green : Colors.red,
                                width: 1.5,
                              ),
                            ),
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color:
                                            _isVeg ? Colors.green : Colors.red,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _isVeg
                                              ? Colors.green
                                              : Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _isVeg ? 'Vegetarian' : 'Non-Vegetarian',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _isVeg
                                          ? Colors.green[700]
                                          : Colors.red[700],
                                    ),
                                  ),
                                ],
                              ),
                              value: _isVeg,
                              onChanged: (val) {
                                setState(() {
                                  _isVeg = val;
                                  _tags['Vegetarian'] = val;
                                });
                              },
                              activeColor: Colors.green,
                              inactiveTrackColor: Colors.red.withOpacity(0.3),
                            ),
                          ),
                          _buildToggleRow(
                              'Healthy Item', _isHealthy, Icons.fitness_center,
                              (val) {
                            setState(() {
                              _isHealthy = val;
                              _tags['Healthy'] = val;
                            });
                          }),
                          _buildToggleRow('Spicy Item', _isSpicy,
                              Icons.local_fire_department, (val) {
                            setState(() {
                              _isSpicy = val;
                              _tags['Spicy'] = val;
                            });
                          }),
                          _buildToggleRow(
                              'Popular Item',
                              _isPopular,
                              Icons.star,
                              (val) => setState(() => _isPopular = val)),
                          _buildToggleRow(
                              'Available',
                              _isAvailable,
                              Icons.check_circle,
                              (val) => setState(() => _isAvailable = val)),
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isOutOfStock
                                  ? Colors.orange[50]
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _isOutOfStock
                                    ? Colors.orange
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2,
                                    color: _isOutOfStock
                                        ? Colors.orange
                                        : Colors.grey[600],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Out of Stock',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: _isOutOfStock
                                                ? Colors.orange
                                                : Colors.grey[800],
                                          ),
                                        ),
                                        Text(
                                          _isOutOfStock
                                              ? 'This item will be hidden from ${userScope.branchIds.isNotEmpty ? userScope.branchIds.first : "current branch"}'
                                              : 'Item is available for order',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _isOutOfStock
                                                ? Colors.orange[700]
                                                : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              value: _isOutOfStock,
                              onChanged: (val) =>
                                  setState(() => _isOutOfStock = val),
                              activeColor: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── RECIPE & INGREDIENTS SECTION ─────────────────────────────
              const Divider(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader('Recipe & Ingredients', Icons.restaurant_menu),
                  TextButton.icon(
                    onPressed: _loadingRecipes ? null : () => _showRecipePickerDialog(),
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Link Existing', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              if (_linkedRecipeName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.shade100),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.link, color: Colors.deepPurple, size: 16),
                        const SizedBox(width: 8),
                        const Text('Linked to: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Expanded(child: Text(_linkedRecipeName!, style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.bold))),
                        IconButton(
                          icon: const Icon(Icons.link_off, size: 16, color: Colors.red),
                          onPressed: () => setState(() {
                            _linkedRecipeId = null;
                            _linkedRecipeName = null;
                            _ingredientLines = [];
                            _instructions = [''];
                            _recalcLiveRecipeCost();
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              
              const SizedBox(height: 16),
              _sectionLabel('Ingredients'),
              const SizedBox(height: 12),
              _loadingIngredients 
                ? const Center(child: CircularProgressIndicator())
                : _buildIngredientTable(),
              
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _ingredientLines.add(const RecipeIngredientLine(
                      ingredientId: '',
                      ingredientName: '',
                      quantity: 1,
                      unit: '',
                    ));
                  });
                },
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add Ingredient', style: TextStyle(fontSize: 13)),
              ),

              const SizedBox(height: 24),
              _sectionLabel('Preparation Steps'),
              const SizedBox(height: 12),
              _buildInstructionsList(),
              
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() => _instructions.add('')),
                icon: const Icon(Icons.add_task, size: 18),
                label: const Text('Add Step', style: TextStyle(fontSize: 13)),
              ),
              
              if (_foodCostPct > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _foodCostPct > 35 ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _foodCostPct > 35 ? Colors.red.shade100 : Colors.green.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.analytics_outlined, size: 18, color: _foodCostPct > 35 ? Colors.red : Colors.green),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Est. Food Cost', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          Text('${_foodCostPct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _foodCostPct > 35 ? Colors.red : Colors.green)),
                        ],
                      ),
                      const Spacer(),
                      Text('Margin: ${(100 - _foodCostPct).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              _buildAllergenProfileCard(),
              _buildInventoryForecastCard(),
              _buildWeeklySalesCard(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveMenuItem,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(_isEdit ? 'Update Item' : 'Add Item'),
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

class _CategoryDropdown extends StatelessWidget {
  final String? selectedId;
  final UserScopeService userScope;
  final ValueChanged<String?> onChanged;

  const _CategoryDropdown({
    required this.selectedId,
    required this.userScope,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Query query;
    if (userScope.isSuperAdmin) {
      query = FirebaseFirestore.instance.collection('menu_categories');
    } else {
      query = FirebaseFirestore.instance
          .collection('menu_categories')
          .where('branchIds', arrayContainsAny: userScope.branchIds);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return DropdownMenuItem<String>(
            value: doc.id,
            child: Text(data['name'] ?? '...'),
          );
        }).toList();

        return DropdownButtonFormField<String>(
          value: selectedId,
          decoration: const InputDecoration(
            labelText: 'Category *',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          items: [
            const DropdownMenuItem(
                value: null, child: Text('Select a category')),
            ...items,
          ],
          onChanged: onChanged,
          validator: (val) => val == null ? 'Category is required' : null,
        );
      },
    );
  }
}
