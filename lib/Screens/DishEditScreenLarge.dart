import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' as intl;
import 'package:timeago/timeago.dart' as timeago;
import '../main.dart';
import 'MenuManagementWidgets.dart';
import 'BranchManagement.dart';
import '../services/ingredients/RecipeService.dart';
import '../Models/RecipeModel.dart';
import '../Models/IngredientModel.dart';
import '../services/ingredients/IngredientService.dart';

class DishEditScreenLarge extends StatefulWidget {
  final DocumentSnapshot? doc;
  const DishEditScreenLarge({super.key, this.doc});

  @override
  State<DishEditScreenLarge> createState() => _DishEditScreenLargeState();
}

class _DishEditScreenLargeState extends State<DishEditScreenLarge> {
  final _formKey = GlobalKey<FormState>();

  late final RecipeService _recipeService;
  late final IngredientService _ingredientService;

  // ── Controllers ──────────────────────────────────────────────
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

  // ── Toggles ──────────────────────────────────────────────────
  late bool _isAvailable;
  late bool _isPopular;
  late bool _isOutOfStock;
  late bool _isHealthy;
  late bool _isSpicy;
  late bool _isVeg;
  int _preparationTime = 15;
  String? _selectedCategoryId;
  late List<String> _selectedBranchIds;
  DateTime? _discountExpiryDate;
  bool _isLoading = false;

  static const List<int> _prepTimeOptions = [
    5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60
  ];

  final List<Map<String, dynamic>> _variants = [];
  final Map<String, bool> _tags = {
    'Vegan': false,
    'Gluten-Free': false,
    'Vegetarian': false,
    'Spicy': false,
    'Healthy': false,
  };

  // ── Recipe Linking ─────────────────────────────────────────────
  bool _loadingRecipes = true;
  List<Map<String, dynamic>> _allRecipes = [];

  String? _linkedRecipeId;
  String? _linkedRecipeName;
  int? _linkedPrepTimeMinutes;
  double _foodCostPct = 0.0;
  List<String> _linkedAllergens = [];

  // Integrated Recipe Editor state
  List<RecipeIngredientLine> _ingredientLines = [];
  List<String> _instructions = [''];
  double _liveRecipeCost = 0.0;
  List<IngredientModel> _allIngredients = [];
  bool _loadingIngredients = true;
  final Map<int, TextEditingController> _ingredientQtyControllers = {};

  bool get _isEdit => widget.doc != null;

  List<double> _weeklySalesData = List.filled(7, 0.0);
  bool _isLoadingSales = false;

  Future<void> _fetchWeeklySales() async {
    if (widget.doc == null) return;
    setState(() => _isLoadingSales = true);
    try {
      final now = DateTime.now();
      // start of day 6 days ago
      final weekAgoDate = now.subtract(const Duration(days: 6));
      final weekAgo = DateTime(weekAgoDate.year, weekAgoDate.month, weekAgoDate.day);
      
      final snap = await FirebaseFirestore.instance.collection('orders')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo))
          .get();
      
      final sales = List.filled(7, 0.0);
      for (var doc in snap.docs) {
        final data = doc.data();
        final items = data['items'] as List<dynamic>? ?? [];
        if (data['timestamp'] == null) continue;
        final createdAt = (data['timestamp'] as Timestamp).toDate();
        final daysAgo = now.difference(DateTime(createdAt.year, createdAt.month, createdAt.day)).inDays;
        
        if (daysAgo >= 0 && daysAgo < 7) {
          for (var item in items) {
            if (item['menuItemId'] == widget.doc!.id) {
              final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
              final idx = 6 - daysAgo; // 6 is today, 0 is 6 days ago
              sales[idx] += qty;
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _weeklySalesData = sales;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sales: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSales = false);
    }
  }


  // Keep original data for diff detection
  Map<String, dynamic> _originalData = {};

  // ── Helpers ──────────────────────────────────────────────────
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
    _originalData = Map<String, dynamic>.from(data);

    _recipeService = RecipeService();
    _ingredientService = IngredientService();

    _loadIngredients();

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
    _caloriesController = TextEditingController(
        text: (data['calories'] as num?)?.toString() ?? '');

    final expiryTimestamp = data['discountExpiryDate'] as Timestamp?;
    _discountExpiryDate = expiryTimestamp?.toDate();

    _isAvailable = data['isAvailable'] ?? true;
    _isPopular = data['isPopular'] ?? false;
    _isHealthy = data['tags']?['Healthy'] ?? false;
    _isSpicy = data['tags']?['Spicy'] ?? false;
    _isVeg = data['isVeg'] ?? false;
    _preparationTime = (data['preparationTime'] as num?)?.toInt() ?? 15;
    _selectedCategoryId = data['categoryId'];
    _selectedBranchIds = List<String>.from(data['branchIds'] ?? []);
    _linkedAllergens = List<String>.from(data['allergenWarnings'] ?? []);

    final variantsData = data['variants'] as Map<String, dynamic>? ?? {};
    _variants.addAll(variantsData.entries.map((entry) => {
          'id': entry.key,
          'name': entry.value['name'] ?? '',
          'variantprice':
              (entry.value['variantprice'] as num?)?.toDouble() ?? 0.0,
        }));

    final tagsData = data['tags'] as Map<String, dynamic>? ?? {};
    _tags.forEach((key, _) {
      _tags[key] = tagsData[key] ?? false;
    });

    final userScope = context.read<UserScopeService>();
    final currentBranch = userScope.branchIds.isNotEmpty ? userScope.branchIds.first : '';
    final outOfStockBranches =
        List<String>.from(data['outOfStockBranches'] ?? []);
    _isOutOfStock =
        currentBranch.isNotEmpty && outOfStockBranches.contains(currentBranch);

    // Load existing recipe link
    _linkedRecipeId = data['recipeId'] as String?;

    // Fetch all recipes async for the picker
    // NOTE: We avoid .orderBy('name') to prevent needing a composite Firestore index.
    // Sort client-side instead.
    _fetchAllRecipes();

    if (_linkedRecipeId != null) {
      _loadLinkedRecipeDetails(_linkedRecipeId!);
    }

    _fetchWeeklySales();
  }

  Future<void> _loadIngredients() async {
    final userScope = context.read<UserScopeService>();
    final branchIds = userScope.branchIds;
    // For ingredients, we usually fetch based on the first branch or a set of branches
    // Given the context of this app, we'll use the active branches
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

  Future<void> _fetchAllRecipes() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('recipes')
          .where('isActive', isEqualTo: true)
          .get();
      if (!mounted) return;
      final recipes = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      // Sort client-side by name to avoid needing a composite Firestore index
      recipes.sort((a, b) => (a['name']?.toString() ?? '').toLowerCase()
          .compareTo((b['name']?.toString() ?? '').toLowerCase()));
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
    } catch (e) {
      debugPrint('Error fetching recipes for picker: $e');
      if (mounted) setState(() => _loadingRecipes = false);
    }
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
    final allergens = List<String>.from(recipe['allergenTags'] ?? []);
    final prepMins = (recipe['prepTimeMinutes'] as num?)?.toInt();
    setState(() {
      _linkedRecipeId = recipe['id'] as String?;
      _linkedRecipeName = recipe['name'] as String?;
      _linkedPrepTimeMinutes = prepMins;
      _linkedAllergens = allergens;
      _foodCostPct =
          (currentPrice > 0 && cost > 0) ? (cost / currentPrice) * 100 : 0.0;
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
    for (var controller in _ingredientQtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ── Detect changed fields ────────────────────────────────────
  List<String> _getChangedFields() {
    final changes = <String>[];
    if (_nameController.text.trim() != (_originalData['name'] ?? '')) {
      changes.add('Name');
    }
    if (_nameArController.text.trim() != (_originalData['name_ar'] ?? '')) {
      changes.add('Name (Arabic)');
    }
    if (_descController.text.trim() != (_originalData['description'] ?? '')) {
      changes.add('Description');
    }
    if (_descArController.text.trim() !=
        (_originalData['description_ar'] ?? '')) {
      changes.add('Description (Arabic)');
    }
    final newPrice = double.tryParse(_priceController.text) ?? 0.0;
    final oldPrice = (_originalData['price'] as num?)?.toDouble() ?? 0.0;
    if (newPrice != oldPrice) changes.add('Price');

    final newDiscount = double.tryParse(_discountedPriceController.text);
    final oldDiscount =
        (_originalData['discountedPrice'] as num?)?.toDouble();
    if (newDiscount != oldDiscount) changes.add('Discounted Price');

    if (_imageUrlController.text.trim() !=
        (_originalData['imageUrl'] ?? '')) {
      changes.add('Image');
    }
    if (_selectedCategoryId != _originalData['categoryId']) {
      changes.add('Category');
    }
    if (_isAvailable != (_originalData['isAvailable'] ?? true)) {
      changes.add('Availability');
    }
    if (_isPopular != (_originalData['isPopular'] ?? false)) {
      changes.add('Popular');
    }
    if (_isVeg != (_originalData['isVeg'] ?? false)) changes.add('Veg/Non-Veg');
    if (_isHealthy != (_originalData['tags']?['Healthy'] ?? false)) {
      changes.add('Healthy');
    }
    if (_isSpicy != (_originalData['tags']?['Spicy'] ?? false)) {
      changes.add('Spicy');
    }
    final oldPrepTime =
        (_originalData['preparationTime'] as num?)?.toInt() ?? 15;
    if (_preparationTime != oldPrepTime) changes.add('Preparation Time');

    if (_estimatedTimeController.text.trim() !=
        _getStringFromDynamic(_originalData['EstimatedTime'], '25-35')) {
      changes.add('Est. Delivery Time');
    }
    final newSort = int.tryParse(_sortOrderController.text) ?? 0;
    final oldSort =
        (_originalData['sortOrder'] is num)
            ? (_originalData['sortOrder'] as num).toInt()
            : (int.tryParse(_originalData['sortOrder']?.toString() ?? '0') ??
                0);
    if (newSort != oldSort) changes.add('Sort Order');

    final newCalories = int.tryParse(_caloriesController.text.trim());
    final oldCalories = (_originalData['calories'] as num?)?.toInt();
    if (newCalories != oldCalories) changes.add('Calories');

    if (_linkedRecipeId != _originalData['recipeId']) changes.add('Linked Recipe');

    // If no specific change detected but something was saved, mark generic
    return changes;
  }

  // ── Save ─────────────────────────────────────────────────────
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
      final branchId = userScope.branchIds.isNotEmpty ? userScope.branchIds.first : '';
      if (branchId.isEmpty) {
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
      'discountExpiryDate': _discountExpiryDate != null
          ? Timestamp.fromDate(_discountExpiryDate!)
          : null,
      'lastUpdated': FieldValue.serverTimestamp(),
      'recipeId': _linkedRecipeId,
      'prepTimeMinutes': _preparationTime, // Use _preparationTime which might be updated by recipe
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
            // Update existing recipe
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
            // Create new recipe
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

      // Update data with finalRecipeId and possibly updated costs/allergens
      data['recipeId'] = finalRecipeId;
      // Re-fetch allergens from recipe service if needed, or use local state
      // The recipe service updateRecipe/addRecipe already infers allergens
      // For now, we'll stick to the current data map.

      String docId;
      final changedFields = _isEdit ? _getChangedFields() : ['Created'];

      if (_isEdit) {
        docId = widget.doc!.id;
        if (userScope.branchIds.isNotEmpty) {
          if (_isOutOfStock) {
            data['outOfStockBranches'] =
                FieldValue.arrayUnion([userScope.branchIds.first]);
          } else {
            data['outOfStockBranches'] =
                FieldValue.arrayRemove([userScope.branchIds.first]);
          }
        }
        await db.collection('menu_items').doc(docId).update(data);
      } else {
        final branchId = userScope.branchIds.isNotEmpty ? userScope.branchIds.first : '';
        if (_isOutOfStock && branchId.isNotEmpty) {
          data['outOfStockBranches'] = [branchId];
        } else {
          data['outOfStockBranches'] = [];
        }
        final docRef = await db.collection('menu_items').add(data);
        docId = docRef.id;
      }



      // Write edit history log
      if (changedFields.isNotEmpty) {
        await db
            .collection('menu_items')
            .doc(docId)
            .collection('edit_history')
            .add({
          'editedBy': userScope.userIdentifier,
          'editedAt': FieldValue.serverTimestamp(),
          'changedFields': changedFields,
        });
      }

      _showSuccess(_isEdit
          ? 'Menu item updated successfully!'
          : 'Menu item added successfully!');
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

  // ── Image upload ─────────────────────────────────────────────
  Future<void> _uploadMenuImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (image == null) return;

      if (!mounted) return;
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

      final File imageFile = File(image.path);
      final String fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${imageFile.uri.pathSegments.last}';
      final Reference storageRef =
          FirebaseStorage.instance.ref().child('menu_items/$fileName');
      final TaskSnapshot snapshot = await storageRef.putFile(imageFile);
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _imageUrlController.text = downloadUrl);
        _showSuccess('Image uploaded successfully!');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showError('Failed to upload image: $e');
      }
    }
  }

  // ── Variant helpers ──────────────────────────────────────────
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

  void _removeVariant(int index) {
    if (!mounted) return;
    setState(() => _variants.removeAt(index));
  }

  // ── Branch select ────────────────────────────────────────────
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

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final isSuperAdmin = userScope.isSuperAdmin;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // ── Header bar ──────────────────────────────────────
          _buildHeader(),
          // ── Body ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
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
                              _buildBasicDetailsCard(),
                              const SizedBox(height: 20),
                              _buildRecipeLinkCard(),
                              const SizedBox(height: 20),
                              _buildVariantsCard(),
                              const SizedBox(height: 20),
                              _buildTagsCard(),
                              const SizedBox(height: 20),
                              if (_isEdit) _buildEditHistoryCard(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        // RIGHT COLUMN (1/3)
                        Expanded(
                          flex: 1,
                          child: Column(
                            children: [
                              _buildRightInfoSidebar(),
                              const SizedBox(height: 20),
                              _buildGalleryCard(),
                              const SizedBox(height: 20),
                              _buildAvailabilityCard(),
                              if (isSuperAdmin) ...[
                                const SizedBox(height: 20),
                                _buildBranchAssignmentCard(),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeader() {
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
            tooltip: 'Back to menu',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isEdit
                          ? (_nameController.text.isNotEmpty
                              ? _nameController.text
                              : 'Edit Dish')
                          : 'New Dish',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isEdit
                            ? Colors.green.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isEdit
                              ? Colors.green.shade200
                              : Colors.blue.shade200,
                        ),
                      ),
                      child: Text(
                        _isEdit ? 'Editing' : 'New',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isEdit
                              ? Colors.green.shade700
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isEdit)
                  Text(
                    'ID: ${widget.doc!.id}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontFamily: 'monospace',
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
            onPressed: _isLoading ? null : _saveMenuItem,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_isEdit ? 'Save Changes' : 'Create Dish'),
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
  //  BASIC DETAILS
  // ══════════════════════════════════════════════════════════════
  Widget _buildBasicDetailsCard() {
    final userScope = context.watch<UserScopeService>();
    return _card(
      icon: Icons.edit_note_rounded,
      title: 'Basic Details',
      child: Column(
        children: [
          // Name row
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _nameController,
                  label: 'Dish Name *',
                  validator: (v) => v!.isEmpty ? 'Name is required' : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  controller: _nameArController,
                  label: 'Dish Name (Arabic)',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Category + Price
          Row(
            children: [
              Expanded(
                child: CategoryDropdown(
                  selectedId: _selectedCategoryId,
                  userScope: userScope,
                  onChanged: (id) =>
                      setState(() => _selectedCategoryId = id),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  controller: _priceController,
                  label: 'Price (QAR) *',
                  prefixText: 'QAR ',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => v!.isEmpty ? 'Price is required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Discounted price + Calories
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _discountedPriceController,
                  label: 'Discounted Price',
                  prefixText: 'QAR ',
                  helperText: 'Optional',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  controller: _caloriesController,
                  label: 'Calories',
                  suffixText: 'kcal',
                  helperText: 'Optional',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          // Discount expiry date
          if (_discountedPriceController.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDiscountExpiryRow(),
          ],
          const SizedBox(height: 16),
          // Prep time + Est delivery
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _preparationTime,
                  decoration: const InputDecoration(
                    labelText: 'Prep Time *',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: _prepTimeOptions.map((t) {
                    return DropdownMenuItem(value: t, child: Text('$t mins'));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _preparationTime = v);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  controller: _estimatedTimeController,
                  label: 'Est. Delivery Time',
                  suffixText: 'mins',
                  helperText: 'e.g., 25-35',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  controller: _sortOrderController,
                  label: 'Sort Order',
                  helperText: 'Lower = first',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Description
          _textField(
            controller: _descController,
            label: 'Description',
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _descArController,
            label: 'Description (Arabic)',
            maxLines: 3,
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountExpiryRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_note, color: Colors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Discount Expiry Date',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(
                  _discountExpiryDate == null
                      ? 'No expiry set (Always active)'
                      : 'Expires: ${intl.DateFormat('MMM dd, yyyy').format(_discountExpiryDate!)}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _discountExpiryDate ??
                    DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() => _discountExpiryDate = picked);
              }
            },
            icon: const Icon(Icons.calendar_today, size: 16),
            label:
                Text(_discountExpiryDate == null ? 'Set' : 'Change'),
          ),
          if (_discountExpiryDate != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 16, color: Colors.red),
              onPressed: () =>
                  setState(() => _discountExpiryDate = null),
            ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  VARIANTS
  // ══════════════════════════════════════════════════════════════
  Widget _buildVariantsCard() {
    return _card(
      icon: Icons.tune_rounded,
      title: 'Variants',
      trailing: TextButton.icon(
        onPressed: _addVariant,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Variant'),
        style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
      ),
      child: Column(
        children: [
          if (_variants.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: const Center(
                child: Text('No variants added',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ..._variants.asMap().entries.map((entry) {
              final i = entry.key;
              final v = entry.value;
              final nameCtrl =
                  TextEditingController(text: v['name'] ?? '');
              final priceCtrl = TextEditingController(
                  text:
                      (v['variantprice'] as num?)?.toStringAsFixed(2) ??
                          '0.00');
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.label_outline,
                        size: 20, color: Colors.deepPurple.shade400),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Variant Name',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        onChanged: (val) => _variants[i]['name'] = val,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: priceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Extra Price',
                          border: OutlineInputBorder(),
                          prefixText: 'QAR ',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (val) => _variants[i]['variantprice'] =
                            double.tryParse(val) ?? 0.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: () => _removeVariant(i),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  TAGS & ATTRIBUTES
  // ══════════════════════════════════════════════════════════════
  Widget _buildTagsCard() {
    return _card(
      icon: Icons.local_offer_rounded,
      title: 'Tags & Attributes',
      child: Column(
        children: [
          // Veg / Non-veg toggle
          _vegToggle(),
          const Divider(height: 24),
          _toggleRow('Healthy', _isHealthy, Icons.fitness_center, (val) {
            setState(() {
              _isHealthy = val;
              _tags['Healthy'] = val;
            });
          }),
          _toggleRow('Spicy', _isSpicy, Icons.local_fire_department, (val) {
            setState(() {
              _isSpicy = val;
              _tags['Spicy'] = val;
            });
          }),
          _toggleRow('Popular', _isPopular, Icons.star, (val) {
            setState(() => _isPopular = val);
          }),
        ],
      ),
    );
  }

  Widget _vegToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isVeg
            ? Colors.green.withOpacity(0.08)
            : Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isVeg ? Colors.green : Colors.red),
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
                  color: _isVeg ? Colors.green : Colors.red,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _isVeg ? Colors.green : Colors.red,
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
                color: _isVeg ? Colors.green[700] : Colors.red[700],
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
    );
  }

  Widget _toggleRow(
      String title, bool value, IconData icon, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon, color: Colors.deepPurple.shade300, size: 22),
        title:
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        value: value,
        onChanged: onChanged,
        activeColor: Colors.deepPurple,
      ),
    );
  }



  // ══════════════════════════════════════════════════════════════
  //  GALLERY (right column)
  // ══════════════════════════════════════════════════════════════
  Widget _buildGalleryCard() {
    final hasImage = _imageUrlController.text.isNotEmpty;

    return _card(
      icon: Icons.image_rounded,
      title: 'Dish Image',
      child: Column(
        children: [
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.grey[300]!,
                style: hasImage ? BorderStyle.solid : BorderStyle.none,
              ),
              image: hasImage
                  ? DecorationImage(
                      image: NetworkImage(_imageUrlController.text),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasImage
                ? null
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 36, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No image',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _uploadMenuImage,
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  AVAILABILITY (right column)
  // ══════════════════════════════════════════════════════════════
  Widget _buildAvailabilityCard() {
    final userScope = context.watch<UserScopeService>();

    return _card(
      icon: Icons.storefront_rounded,
      title: 'Availability',
      child: Column(
        children: [
          _toggleRow('Available for Order', _isAvailable,
              Icons.check_circle_outline, (val) {
            setState(() => _isAvailable = val);
          }),
          const Divider(height: 16),
          // Out of stock toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _isOutOfStock ? Colors.orange[50] : Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _isOutOfStock ? Colors.orange : Colors.grey[300]!),
            ),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Icon(Icons.inventory_2,
                      color:
                          _isOutOfStock ? Colors.orange : Colors.grey[600],
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                              ? 'Hidden from ${userScope.branchIds.isNotEmpty ? userScope.branchIds.first : "current branch"}'
                              : 'Item is available',
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
              onChanged: (val) => setState(() => _isOutOfStock = val),
              activeColor: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  BRANCH ASSIGNMENT (right column, super admin only)
  // ══════════════════════════════════════════════════════════════
  Widget _buildBranchAssignmentCard() {
    return _card(
      icon: Icons.business_rounded,
      title: 'Branch Assignment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${_selectedBranchIds.length} branch(es) selected',
                  style: TextStyle(
                      color: Colors.deepPurple, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _showMultiSelect,
            icon: const Icon(Icons.business_outlined, size: 18),
            label: const Text('Choose Branches'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          if (_selectedBranchIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedBranchIds.map((bid) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.deepPurple.withOpacity(0.3)),
                  ),
                  child: Text(bid,
                      style: const TextStyle(
                          color: Colors.deepPurple,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  EDIT HISTORY (left column, bottom)
  // ══════════════════════════════════════════════════════════════
  Widget _buildEditHistoryCard() {
    return _card(
      icon: Icons.history_rounded,
      title: 'Edit History',
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('menu_items')
            .doc(widget.doc!.id)
            .collection('edit_history')
            .orderBy('editedAt', descending: true)
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: const Center(
                child: Text('No edit history yet',
                    style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          final docs = snapshot.data!.docs;
          return Column(
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final editedBy = data['editedBy'] ?? 'Unknown';
              final changedFields =
                  List<String>.from(data['changedFields'] ?? []);
              final editedAt = data['editedAt'] as Timestamp?;
              final timeStr = editedAt != null
                  ? timeago.format(editedAt.toDate())
                  : 'just now';
              final dateStr = editedAt != null
                  ? intl.DateFormat('MMM dd, yyyy · hh:mm a')
                      .format(editedAt.toDate())
                  : '';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit,
                          size: 14, color: Colors.deepPurple),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87),
                              children: [
                                TextSpan(
                                  text: editedBy,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const TextSpan(text: ' changed '),
                                TextSpan(
                                  text: changedFields.join(', '),
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.deepPurple),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(timeStr,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.w500)),
                              if (dateStr.isNotEmpty) ...[
                                Text(' · ',
                                    style:
                                        TextStyle(color: Colors.grey[400])),
                                Text(dateStr,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[400])),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
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
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? prefixText,
    String? suffixText,
    String? helperText,
    TextInputType? keyboardType,
    TextDirection? textDirection,
    int maxLines = 1,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      textDirection: textDirection,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefixText,
        suffixText: suffixText,
        helperText: helperText,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  // ── HTML Dark Recipe Theme Colors (Adapted to App Theme) ──
  static const Color _rPrimary = Colors.deepPurple;
  static const Color _rBgDark = Colors.white;
  static const Color _rTextMain = Colors.black87; // Dark purple tinted background
  static const Color _rSurface = Color(0xFFFAFAFA); // Slightly lighter purple surface
  static const Color _rBorder = Color(0xFFEAEAEA); // Border color
  static const Color _rTextSubtle = Color(0xFF757575); // Subtle text

  Widget _buildRecipeLinkCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recipe & Ingredients',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadingRecipes ? null : _showRecipePickerDialog,
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Link Existing'),
                  ),
                  if (_linkedRecipeId != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _linkedRecipeId = null;
                          _linkedRecipeName = null;
                          _foodCostPct = 0.0;
                          _linkedAllergens = [];
                          _linkedPrepTimeMinutes = null;
                          _ingredientLines = [];
                          _instructions = [''];
                          _recalcLiveRecipeCost();
                        });
                      },
                      icon: const Icon(Icons.link_off, size: 18, color: Colors.red),
                      label: const Text('Unlink', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_linkedRecipeName != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, color: Colors.deepPurple, size: 20),
                  const SizedBox(width: 12),
                  const Text('Linked to: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(_linkedRecipeName!, style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          
          _sectionLabel('Ingredients'),
          const SizedBox(height: 12),
          _loadingIngredients 
            ? const Center(child: CircularProgressIndicator())
            : _buildIngredientTable(),
          
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
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
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text('Add Ingredient'),
            ),
          ),

          const Divider(height: 40),

          _sectionLabel('Preparation Steps'),
          const SizedBox(height: 12),
          _buildInstructionsList(),
          
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _instructions.add('')),
              icon: const Icon(Icons.add_task, size: 20),
              label: const Text('Add Step'),
            ),
          ),
        ],
      ),
    );
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
          border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
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
    // Get or create stable controller for this row
    final qtyCtrl = _ingredientQtyControllers.putIfAbsent(idx, () {
      final ctrl = TextEditingController(
          text: line.quantity > 0 ? line.quantity.toString() : '');
      return ctrl;
    });

    // Update text if it's different but not if user is actively typing a dot
    final currentText = qtyCtrl.text;
    final modelValue = line.quantity;
    final parsedValue = double.tryParse(currentText) ?? 0.0;

    if (modelValue != parsedValue && !currentText.endsWith('.')) {
      qtyCtrl.text = modelValue > 0 ? modelValue.toString() : '';
    }

    final selectedIngredient = _allIngredients.where((i) => i.id == line.ingredientId).firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), shape: BoxShape.circle),
            child: Text('${idx + 1}', style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
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
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Qty',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              onChanged: (v) {
                final qty = double.tryParse(v) ?? 0.0;
                setState(() {
                  _ingredientLines[idx] = line.copyWith(quantity: qty);
                  _recalcLiveRecipeCost();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(selectedIngredient?.unit ?? line.unit, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
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
    final ctr = TextEditingController(text: text);
    ctr.selection = TextSelection.fromPosition(TextPosition(offset: ctr.text.length));

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
              controller: ctr,
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

  Future<void> _showRecipePickerDialog() async {
    String localSearch = '';
    bool localLoading = _loadingRecipes;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Expanded(
                child: Text('Link Recipe', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              // Refresh button
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh recipes',
                onPressed: () async {
                  setLocal(() => localLoading = true);
                  await _fetchAllRecipes();
                  if (ctx.mounted) setLocal(() => localLoading = false);
                },
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 450,
            child: Column(
              children: [
                // Create New Recipe button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx); // close picker first
                      await _createNewRecipeInline();
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Create New Recipe'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side: const BorderSide(color: Colors.deepPurple),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Search
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search recipes...',
                    prefixIcon: Icon(Icons.search, color: Colors.deepPurple.shade300),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onChanged: (v) => setLocal(() => localSearch = v.toLowerCase()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: localLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                      : Builder(builder: (_) {
                    final filtered = _allRecipes.where((r) {
                      final name = r['name']?.toString().toLowerCase() ?? '';
                      return localSearch.isEmpty || name.contains(localSearch);
                    }).toList();
                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.menu_book_outlined, size: 40, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              _allRecipes.isEmpty
                                  ? 'No recipes found.\nCreate one using the button above.'
                                  : 'No matching recipes.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final recipe = filtered[i];
                        final isSelected = recipe['id'] == _linkedRecipeId;
                        final ingCount = (recipe['ingredients'] as List?)?.length ?? 0;
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.deepPurple.withOpacity(0.1)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.menu_book, size: 18,
                                color: isSelected ? Colors.deepPurple : Colors.grey),
                          ),
                          title: Text(recipe['name'] ?? '',
                              style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.deepPurple : Colors.black87)),
                          subtitle: Text(
                            '$ingCount ingredients · QAR ${((recipe['totalCost'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: Colors.deepPurple)
                              : null,
                          onTap: () {
                            _applyRecipeLink(recipe,
                                currentPrice: double.tryParse(_priceController.text) ?? 0.0);
                            // Also load the full recipe details (ingredients/instructions)
                            if (recipe['id'] != null) {
                              _loadLinkedRecipeDetails(recipe['id'] as String);
                            }
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

  /// Creates a new recipe inline from DishEditScreen, auto-naming it
  /// after the current dish and auto-linking it.
  Future<void> _createNewRecipeInline() async {
    final userScope = context.read<UserScopeService>();
    final branchIds = userScope.branchIds;
    final dishName = _nameController.text.trim();
    final newRecipeId = FirebaseFirestore.instance.collection('recipes').doc().id;

    final newRecipe = RecipeModel(
      id: newRecipeId,
      branchIds: branchIds,
      name: dishName.isNotEmpty ? '$dishName Recipe' : 'New Recipe',
      description: '',
      ingredients: [],
      totalCost: 0,
      instructions: [''],
      prepTimeMinutes: _preparationTime,
      yield_: '',
      servingSize: '',
      difficultyLevel: 'medium',
      categoryTags: [],
      allergenTags: [],
      photoUrls: [],
      linkedMenuItemId: widget.doc?.id,
      linkedMenuItemName: dishName,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await _recipeService.addRecipe(newRecipe);
      if (!mounted) return;
      setState(() {
        _linkedRecipeId = newRecipeId;
        _linkedRecipeName = newRecipe.name;
        _ingredientLines = [];
        _instructions = [''];
        _liveRecipeCost = 0;
        _foodCostPct = 0;
      });
      // Refresh recipes list so new recipe appears in picker
      await _fetchAllRecipes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${newRecipe.name}" created and linked! Add ingredients below.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error creating recipe: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _buildRightInfoSidebar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCostSummaryCard(),
          const SizedBox(height: 20),
          _buildAllergenProfileCard(),
          const SizedBox(height: 20),
          _buildInventoryForecastCard(),
          const SizedBox(height: 20),
          _buildWeeklySalesCard(),
        ],
      ),
    );
  }

  Widget _buildCostSummaryCard() {
    final sellingPrice = double.tryParse(_priceController.text) ?? 0.0;
    final dishCost = _liveRecipeCost;
    final margin = sellingPrice > 0 ? ((sellingPrice - dishCost) / sellingPrice) * 100 : 0.0;
    final foodCostPct = sellingPrice > 0 && dishCost > 0 ? (dishCost / sellingPrice) * 100 : 0.0;
    final hasRecipe = _ingredientLines.isNotEmpty;

    Color marginColor;
    String marginLabel;
    IconData marginIcon;
    if (margin >= 60) {
      marginColor = Colors.green;
      marginLabel = 'Healthy';
      marginIcon = Icons.trending_up_rounded;
    } else if (margin >= 40) {
      marginColor = Colors.orange;
      marginLabel = 'Moderate';
      marginIcon = Icons.trending_flat_rounded;
    } else {
      marginColor = Colors.red;
      marginLabel = margin > 0 ? 'Low' : 'N/A';
      marginIcon = margin > 0 ? Icons.trending_down_rounded : Icons.remove_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _rSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _rBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, color: _rPrimary, size: 18),
              const SizedBox(width: 8),
              const Text('Cost Analysis', style: TextStyle(color: _rTextMain, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasRecipe)
            const Text('Add recipe ingredients to see cost analysis.',
                style: TextStyle(color: _rTextSubtle, fontSize: 12))
          else ...[
            // Selling Price
            _costRow('Selling Price', 'QAR ${sellingPrice.toStringAsFixed(2)}', Colors.blue),
            const SizedBox(height: 10),
            // Dish Cost
            _costRow('Total Dish Cost', 'QAR ${dishCost.toStringAsFixed(2)}', Colors.deepOrange),
            const SizedBox(height: 10),
            // Food Cost %
            _costRow('Food Cost', '${foodCostPct.toStringAsFixed(1)}%', Colors.amber.shade700),
            const SizedBox(height: 14),
            // Margin Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: marginColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: marginColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(marginIcon, color: marginColor, size: 20),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Profit Margin', style: TextStyle(color: marginColor, fontSize: 11, fontWeight: FontWeight.w500)),
                      Text('${margin.toStringAsFixed(1)}%', style: TextStyle(color: marginColor, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: marginColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(marginLabel, style: TextStyle(color: marginColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _costRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: _rTextSubtle, fontSize: 12)),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
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
      decoration: BoxDecoration(color: _rSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _rBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Allergen Profile', style: TextStyle(color: _rTextMain, fontSize: 14, fontWeight: FontWeight.w600)),
              IconButton(icon: const Icon(Icons.edit, size: 16, color: _rPrimary), onPressed: _showAllergenDialog),
            ],
          ),
          const SizedBox(height: 16),
          if (activeAllergens.isEmpty)
             const Text('No allergens selected.', style: TextStyle(color: _rTextSubtle, fontSize: 13))
          else
            Wrap(
              spacing: 8, runSpacing: 8,
              children: activeAllergens.map((a) => Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: _rBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a['icon'] as IconData, color: a['color'] as Color, size: 16),
                    const SizedBox(width: 6),
                    Text(a['label'] as String, style: const TextStyle(color: _rTextSubtle, fontSize: 12)),
                  ],
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildInventoryForecastCard() {
    final hasRecipe = _ingredientLines.isNotEmpty;

    // Build forecast data
    int? maxServings;
    String? bottleneckName;
    final List<Map<String, dynamic>> forecastRows = [];

    if (hasRecipe && _allIngredients.isNotEmpty) {
      for (final line in _ingredientLines) {
        if (line.ingredientId.isEmpty || line.quantity <= 0) continue;
        final ingredient = _allIngredients.where((i) => i.id == line.ingredientId).firstOrNull;
        if (ingredient == null) continue;

        double recipeQty = line.quantity;
        // Convert units if needed
        if (line.unit.isNotEmpty && ingredient.unit.isNotEmpty && line.unit != ingredient.unit) {
          final converted = IngredientService.convertUnit(recipeQty, line.unit, ingredient.unit);
          if (converted != null) {
            recipeQty = converted;
          }
        }

        final int possible = recipeQty > 0 ? (ingredient.currentStock / recipeQty).floor() : 0;
        String status;
        Color statusColor;
        if (possible <= 0) {
          status = 'Out';
          statusColor = Colors.red;
        } else if (possible <= 5) {
          status = 'Low';
          statusColor = Colors.orange;
        } else {
          status = 'OK';
          statusColor = Colors.green;
        }

        forecastRows.add({
          'name': ingredient.name,
          'stock': ingredient.currentStock,
          'unit': ingredient.unit,
          'possible': possible,
          'status': status,
          'statusColor': statusColor,
        });

        if (maxServings == null || possible < maxServings) {
          maxServings = possible;
          bottleneckName = ingredient.name;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _rSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _rBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Inventory Forecast', style: TextStyle(color: _rTextMain, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (!hasRecipe)
            const Text('Add recipe ingredients to enable forecasting.', style: TextStyle(color: _rTextSubtle, fontSize: 12))
          else if (forecastRows.isEmpty)
            const Text('No valid ingredient data to forecast.', style: TextStyle(color: _rTextSubtle, fontSize: 12))
          else ...[
            // Max servings banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (maxServings != null && maxServings > 0 ? Colors.green : Colors.red).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (maxServings != null && maxServings > 0 ? Colors.green : Colors.red).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    maxServings != null && maxServings > 0 ? Icons.restaurant_rounded : Icons.warning_amber_rounded,
                    color: maxServings != null && maxServings > 0 ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Can make ${maxServings ?? 0} more servings',
                          style: TextStyle(
                            color: maxServings != null && maxServings > 0 ? Colors.green.shade800 : Colors.red.shade800,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (bottleneckName != null)
                          Text(
                            'Bottleneck: $bottleneckName',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Ingredient rows
            ...forecastRows.map((row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: row['statusColor'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row['name'] as String,
                      style: const TextStyle(fontSize: 12, color: _rTextMain),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(row['stock'] as double).toStringAsFixed(1)} ${row['unit']}',
                    style: const TextStyle(fontSize: 11, color: _rTextSubtle),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (row['statusColor'] as Color).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${row['possible']}x',
                      style: TextStyle(
                        color: row['statusColor'] as Color,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
  Widget _buildWeeklySalesCard() {
    final now = DateTime.now();
    final dayLabels = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[d.weekday - 1];
    });

    final maxSale = _weeklySalesData.fold<double>(0.0, (a, b) => a > b ? a : b);
    final totalSales = _weeklySalesData.fold<double>(0.0, (a, b) => a + b);
    final hasData = maxSale > 0;

    final heights = hasData
        ? _weeklySalesData.map((v) => maxSale > 0 ? (v / maxSale).clamp(0.05, 1.0) : 0.05).toList()
        : List.filled(7, 0.05);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _rSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _rBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Weekly Sales', style: TextStyle(color: _rTextMain, fontSize: 14, fontWeight: FontWeight.w600)),
              if (hasData)
                Text('${totalSales.toStringAsFixed(0)} sold', style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingSales)
            const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple)),
            )
          else if (!hasData && !_isEdit)
            const SizedBox(
              height: 100,
              child: Center(child: Text('Save the dish first to see sales data.', style: TextStyle(color: _rTextSubtle, fontSize: 12))),
            )
          else ...[
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final h = heights[i];
                  final qty = _weeklySalesData[i];
                  return Expanded(
                    child: Tooltip(
                      message: '${qty.toStringAsFixed(0)} sold',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: FractionallySizedBox(
                          heightFactor: h,
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _rPrimary.withOpacity(h > 0.8 ? 1.0 : h > 0.5 ? 0.6 : 0.25),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: dayLabels.map((l) => Expanded(child: Center(child: Text(l, style: const TextStyle(color: _rTextSubtle, fontSize: 10))))).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
