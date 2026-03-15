import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../main.dart';
import '../../Models/RecipeModel.dart';
import '../../Models/IngredientModel.dart';
import '../../services/ingredients/RecipeService.dart';
import '../../services/ingredients/IngredientService.dart';
import '../../Widgets/BranchFilterService.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  late final RecipeService _recipeService;
  bool _serviceInitialized = false;
  String _searchQuery = '';
  bool _isRecalculating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _recipeService = Provider.of<RecipeService>(context, listen: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final branchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context, userScope, branchIds),
          Expanded(
            child: StreamBuilder<List<RecipeModel>>(
              stream: _recipeService.streamRecipes(branchIds),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.deepPurple),
                  );
                }
                if (snapshot.hasError) {
                  return _buildError(snapshot.error.toString());
                }
                final all = snapshot.data ?? [];
                final filtered = _searchQuery.isEmpty
                    ? all
                    : all
                        .where(
                            (r) => r.name.toLowerCase().contains(_searchQuery))
                        .toList();
                if (filtered.isEmpty) return _buildEmpty();
                return _buildList(filtered, userScope, branchIds);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, userScope, branchIds),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Recipe'),
        elevation: 4,
      ),
    );
  }

  // ─── HEADER (search + Recalculate All Costs) ───────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // Search
          TextField(
            decoration: InputDecoration(
              hintText: 'Search recipes…',
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon:
                  Icon(Icons.search_rounded, color: Colors.deepPurple.shade300),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
          const SizedBox(height: 10),
          // Recalculate All Costs button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isRecalculating
                  ? null
                  : () => _recalculateAll(context, branchIds),
              icon: _isRecalculating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.deepPurple),
                    )
                  : const Icon(Icons.calculate_outlined, size: 18),
              label: Text(
                _isRecalculating ? 'Recalculating…' : 'Recalculate All Costs',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                side: const BorderSide(color: Colors.deepPurple),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── RECALCULATE ───────────────────────────────────────────────────────────

  Future<void> _recalculateAll(
      BuildContext context, List<String> branchIds) async {
    setState(() => _isRecalculating = true);
    try {
      final count = await _recipeService.recalculateAllCosts(branchIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ Updated costs for $count recipe(s).'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isRecalculating = false);
    }
  }

  // ─── LIST ──────────────────────────────────────────────────────────────────

  Widget _buildList(
    List<RecipeModel> recipes,
    UserScopeService userScope,
    List<String> branchIds,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: recipes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _RecipeCard(
        recipe: recipes[i],
        onEdit: () =>
            _openForm(ctx, userScope, branchIds, existing: recipes[i]),
        onDelete: () => _confirmDelete(ctx, recipes[i]),
      ),
    );
  }

  // ─── FORM OPENER ───────────────────────────────────────────────────────────

  void _openForm(
    BuildContext context,
    UserScopeService userScope,
    List<String> branchIds, {
    RecipeModel? existing,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecipeFormSheet(
        existing: existing,
        branchIds: branchIds,
        service: _recipeService,
      ),
    );
  }

  // ─── DELETE ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(BuildContext ctx, RecipeModel recipe) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Recipe?'),
        content: Text(
            '"${recipe.name}" will be deactivated and hidden from all screens.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && ctx.mounted) {
      try {
        await _recipeService.deleteRecipe(recipe.id);
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('"${recipe.name}" deleted.'),
            backgroundColor: Colors.green,
          ));
        }
      } catch (e) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  // ─── EMPTY / ERROR ─────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No recipes found' : 'No recipes yet',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search.'
                : 'Tap + to add your first recipe.',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Failed to load recipes',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(msg,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECIPE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _RecipeCard extends StatelessWidget {
  final RecipeModel recipe;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RecipeCard({
    required this.recipe,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Thumbnail
                _buildThumbnail(r),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _difficultyChip(r.difficultyLevel),
                          const SizedBox(width: 8),
                          if (r.prepTimeMinutes > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined,
                                    size: 13, color: Colors.grey[500]),
                                const SizedBox(width: 3),
                                Text('${r.prepTimeMinutes} min',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[600])),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.blender_outlined,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Text('${r.ingredients.length} ingredient(s)',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                          const Spacer(),
                          // Total cost badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Text(
                              'QAR ${r.totalCost.toStringAsFixed(2)}',
                              style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      // Category tags
                      if (r.categoryTags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          children:
                              r.categoryTags.map((t) => _tagChip(t)).toList(),
                        ),
                      ],
                      // Linked menu item
                      if (r.linkedMenuItemName != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restaurant_menu_outlined,
                                size: 12, color: Colors.deepPurple.shade400),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                r.linkedMenuItemName!,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.deepPurple.shade600,
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Actions
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 20, color: Colors.deepPurple),
                      onPressed: onEdit,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 20, color: Colors.red.shade400),
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(RecipeModel r) {
    final url = r.photoUrls.firstOrNull;
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.deepPurple.withOpacity(0.08),
        image: url != null
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: url == null
          ? const Icon(Icons.menu_book_outlined,
              color: Colors.deepPurple, size: 28)
          : null,
    );
  }

  Widget _difficultyChip(String level) {
    final colors = {
      'easy': [Colors.green.shade50, Colors.green.shade700],
      'medium': [Colors.orange.shade50, Colors.orange.shade700],
      'hard': [Colors.red.shade50, Colors.red.shade700],
    };
    final c = colors[level] ?? [Colors.grey.shade100, Colors.grey.shade700];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20)),
      child: Text(RecipeModel.difficultyLabel(level),
          style: TextStyle(
              color: c[1], fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _tagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(20)),
      child: Text(tag,
          style: TextStyle(
              color: Colors.deepPurple.shade700,
              fontSize: 10,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADD / EDIT FORM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _RecipeFormSheet extends StatefulWidget {
  final RecipeModel? existing;
  final List<String> branchIds;
  final RecipeService service;

  const _RecipeFormSheet({
    required this.existing,
    required this.branchIds,
    required this.service,
  });

  @override
  State<_RecipeFormSheet> createState() => _RecipeFormSheetState();
}

class _RecipeFormSheetState extends State<_RecipeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _descCtr = TextEditingController();
  final _prepTimeCtr = TextEditingController();
  final _yieldCtr = TextEditingController();
  final _servingSizeCtr = TextEditingController();

  late String _difficultyLevel;
  late List<String> _categoryTags;
  late List<RecipeIngredientLine> _ingredientLines;
  late List<String> _instructions;
  late bool _isActive;

  List<File> _newPhotos = [];
  List<String> _existingPhotoUrls = [];
  bool _isLoading = false;
  double _liveCost = 0.0;

  String? _linkedMenuItemId;
  String? _linkedMenuItemName;

  // For menu item search
  List<Map<String, dynamic>> _allMenuItems = [];
  bool _loadingMenuItems = true;

  List<IngredientModel> _allIngredients = [];
  bool _loadingIngredients = true;
  late final IngredientService _ingredientService;
  bool _serviceInitialized = false;

  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtr.text = e?.name ?? '';
    _descCtr.text = e?.description ?? '';
    _prepTimeCtr.text = e?.prepTimeMinutes.toString() ?? '';
    _yieldCtr.text = e?.yield_ ?? '';
    _servingSizeCtr.text = e?.servingSize ?? '';
    _difficultyLevel = e?.difficultyLevel ?? 'easy';
    _categoryTags = List.from(e?.categoryTags ?? []);
    _ingredientLines = List.from(e?.ingredients ?? []);
    _instructions =
        List.from(e?.instructions.isNotEmpty == true ? e!.instructions : ['']);
    _isActive = e?.isActive ?? true;
    _existingPhotoUrls = List.from(e?.photoUrls ?? []);
    _liveCost = e?.totalCost ?? 0.0;
    _linkedMenuItemId = e?.linkedMenuItemId;
    _linkedMenuItemName = e?.linkedMenuItemName;

    _loadMenuItems();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      _serviceInitialized = true;
      _ingredientService =
          Provider.of<IngredientService>(context, listen: false);
      _loadIngredients();
    }
  }

  Future<void> _loadIngredients() async {
    final stream = _ingredientService.streamAllIngredients(widget.branchIds);
    final snap = await stream.first;
    if (mounted) {
      setState(() {
        _allIngredients = snap;
        _loadingIngredients = false;
      });
      _recalcLiveCost();
    }
  }

  Future<void> _loadMenuItems() async {
    try {
      // Fetch menu items - no branch filter needed (admin sees all)
      final snap = await FirebaseFirestore.instance
          .collection('menu_items')
          .orderBy('name')
          .get();
      if (mounted) {
        setState(() {
          _allMenuItems =
              snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _loadingMenuItems = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMenuItems = false);
    }
  }

  void _recalcLiveCost() {
    double cost = 0.0;
    for (final line in _ingredientLines) {
      final ingredient =
          _allIngredients.where((i) => i.id == line.ingredientId).firstOrNull;
      if (ingredient != null) {
        cost += ingredient.costPerUnit * line.quantity;
      }
    }
    setState(() => _liveCost = cost);
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _descCtr.dispose();
    _prepTimeCtr.dispose();
    _yieldCtr.dispose();
    _servingSizeCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            // Header + live cost
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_outlined,
                        color: Colors.deepPurple, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Edit Recipe' : 'Add Recipe',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                        Text(
                          'Total cost: QAR ${_liveCost.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _sectionLabel('Basic Info'),
                    const SizedBox(height: 12),
                    // Photos
                    _buildPhotoRow(),
                    const SizedBox(height: 16),
                    _buildTextInput(_nameCtr, 'Recipe Name',
                        required: true, icon: Icons.label_outline),
                    const SizedBox(height: 12),
                    _buildTextInput(_descCtr, 'Description',
                        maxLines: 3, icon: Icons.description_outlined),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextInput(
                            _prepTimeCtr,
                            'Prep Time (min)',
                            icon: Icons.timer_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSelector(
                            label: 'Difficulty',
                            value: _difficultyLevel,
                            items: RecipeModel.difficultyLevels,
                            labelFn: RecipeModel.difficultyLabel,
                            onChanged: (v) =>
                                setState(() => _difficultyLevel = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextInput(_yieldCtr, 'Yield',
                              hint: 'e.g. 4 portions',
                              icon: Icons.bar_chart_outlined),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextInput(
                              _servingSizeCtr, 'Serving Size',
                              hint: 'e.g. 250g', icon: Icons.scale_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // ── LINKED MENU ITEM ────────────────────────────────────
                    _sectionLabel('Linked Menu Item'),
                    const SizedBox(height: 8),
                    _buildMenuItemPicker(),
                    const SizedBox(height: 20),
                    // Category tags
                    _sectionLabel('Category Tags'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: RecipeModel.categoryTagOptions.map((tag) {
                        final selected = _categoryTags.contains(tag);
                        return FilterChip(
                          label: Text(tag,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: selected
                                      ? Colors.white
                                      : Colors.grey[700],
                                  fontWeight: FontWeight.w600)),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (v) => setState(() => v
                              ? _categoryTags.add(tag)
                              : _categoryTags.remove(tag)),
                          color: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.deepPurple;
                            }
                            return Colors.grey[100];
                          }),
                          side: BorderSide(
                            color: selected
                                ? Colors.deepPurple.shade300
                                : Colors.grey.shade300,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── INGREDIENTS TABLE ───────────────────────────────────
                    Row(
                      children: [
                        _sectionLabel('Ingredients'),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _ingredientLines.add(
                                const RecipeIngredientLine(
                                  ingredientId: '',
                                  ingredientName: '',
                                  quantity: 1,
                                  unit: '',
                                ),
                              );
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Row'),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.deepPurple),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _loadingIngredients
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Colors.deepPurple))
                        : _buildIngredientTable(),
                    // Live cost summary
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.attach_money,
                              color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          const Text('Total Recipe Cost:',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(
                            'QAR ${_liveCost.toStringAsFixed(2)}',
                            style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── INSTRUCTIONS ──────────────────────────────────────
                    Row(
                      children: [
                        _sectionLabel('Instructions'),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _instructions.add('')),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Step'),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.deepPurple),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildInstructionsList(),

                    if (widget.existing != null) ...[
                      const SizedBox(height: 20),
                      _sectionLabel('Status'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Active',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          value: _isActive,
                          activeColor: Colors.deepPurple,
                          onChanged: (v) => setState(() => _isActive = v),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    // Save
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                          shadowColor: Colors.deepPurple.withOpacity(0.4),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text(isEdit ? 'Save Changes' : 'Add Recipe',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── MENU ITEM PICKER ─────────────────────────────────────────────────────

  Widget _buildMenuItemPicker() {
    return InkWell(
      onTap: _loadingMenuItems ? null : () => _showMenuItemPickerDialog(),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _linkedMenuItemId != null
                ? Colors.deepPurple.withOpacity(0.5)
                : Colors.grey.shade300,
            width: _linkedMenuItemId != null ? 1.5 : 1,
          ),
          boxShadow: _linkedMenuItemId != null
              ? [
                  BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _linkedMenuItemId != null
                      ? Colors.deepPurple.withOpacity(0.3)
                      : Colors.grey.shade200,
                ),
              ),
              child: Icon(
                Icons.restaurant_menu_outlined,
                color: _linkedMenuItemId != null
                    ? Colors.deepPurple
                    : Colors.grey[500],
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _loadingMenuItems
                  ? const Text('Loading menu items…',
                      style: TextStyle(color: Colors.grey, fontSize: 14))
                  : Text(
                      _linkedMenuItemName ??
                          'Tap to link a menu item (optional)',
                      style: TextStyle(
                        color: _linkedMenuItemId != null
                            ? Colors.black87
                            : Colors.grey[500],
                        fontSize: 14,
                        fontWeight: _linkedMenuItemId != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
            ),
            if (_linkedMenuItemId != null)
              GestureDetector(
                onTap: () => setState(() {
                  _linkedMenuItemId = null;
                  _linkedMenuItemName = null;
                }),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.grey[200], shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 14, color: Colors.grey),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenuItemPickerDialog() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _MenuItemPickerSheet(
        items: _allMenuItems,
        currentId: _linkedMenuItemId,
        onSelect: (id, name) {
          setState(() {
            _linkedMenuItemId = id;
            _linkedMenuItemName = name;
          });
        },
      ),
    );
  }

  // ─── INGREDIENT TABLE ──────────────────────────────────────────────────────

  Widget _buildIngredientTable() {
    if (_ingredientLines.isEmpty) {
      return GestureDetector(
        onTap: () => setState(() => _ingredientLines.add(
              const RecipeIngredientLine(
                  ingredientId: '', ingredientName: '', quantity: 1, unit: ''),
            )),
        child: Container(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white),
          child: Text('Tap to add ingredients',
              style: TextStyle(color: Colors.grey[400])),
        ),
      );
    }
    return Column(
      children: List.generate(_ingredientLines.length, (idx) {
        final line = _ingredientLines[idx];
        return _buildIngredientRow(idx, line);
      }),
    );
  }

  Widget _buildIngredientRow(int idx, RecipeIngredientLine line) {
    final qtyCtrl = TextEditingController(
        text: line.quantity > 0 ? line.quantity.toString() : '');

    // Find selected ingredient
    final selectedIngredient =
        _allIngredients.where((i) => i.id == line.ingredientId).firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Step number
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Text('${idx + 1}',
                style: const TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(width: 10),
          // Ingredient dropdown
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: line.ingredientId.isNotEmpty ? line.ingredientId : null,
              hint: Text('Ingredient',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              isExpanded: true,
              focusColor: Colors.transparent,
              dropdownColor: Colors.white,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey[500], size: 18),
              decoration: InputDecoration(
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Colors.deepPurple, width: 1.5)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
              items: _allIngredients
                  .map((i) => DropdownMenuItem(
                        value: i.id,
                        child: Text(i.name,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (newId) {
                if (newId == null) return;
                final ing =
                    _allIngredients.where((i) => i.id == newId).firstOrNull;
                if (ing == null) return;
                setState(() {
                  _ingredientLines[idx] = line.copyWith(
                    ingredientId: newId,
                    ingredientName: ing.name,
                    unit: ing.unit,
                  );
                  _recalcLiveCost();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          // Quantity
          SizedBox(
            width: 64,
            child: TextFormField(
              controller: qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
              ],
              decoration: InputDecoration(
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Colors.deepPurple, width: 1.5)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) {
                final qty = double.tryParse(v) ?? 0;
                setState(() {
                  _ingredientLines[idx] = line.copyWith(quantity: qty);
                  _recalcLiveCost();
                });
              },
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          // Unit label
          Text(
            selectedIngredient?.unit ?? line.unit,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          // Remove
          IconButton(
            icon: Icon(Icons.remove_circle_outline,
                color: Colors.red.shade400, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _ingredientLines.removeAt(idx);
                _recalcLiveCost();
              });
            },
          ),
        ],
      ),
    );
  }

  // ─── INSTRUCTIONS LIST ─────────────────────────────────────────────────────

  Widget _buildInstructionsList() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _instructions.length,
      onReorder: (oldIdx, newIdx) {
        setState(() {
          if (newIdx > oldIdx) newIdx--;
          final item = _instructions.removeAt(oldIdx);
          _instructions.insert(newIdx, item);
        });
      },
      itemBuilder: (ctx, idx) {
        return _buildInstructionRow(idx, _instructions[idx],
            key: ValueKey(idx));
      },
    );
  }

  Widget _buildInstructionRow(int idx, String text, {required Key key}) {
    final ctr = TextEditingController(text: text);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Text('${idx + 1}',
                style: const TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 11)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: ctr,
              maxLines: null,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Describe this step…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) => _instructions[idx] = v,
            ),
          ),
          InkWell(
            onTap: () => setState(() => _instructions.removeAt(idx)),
            child: Icon(Icons.remove_circle_outline,
                color: Colors.red.shade400, size: 20),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
        ],
      ),
    );
  }

  // ─── PHOTOS ────────────────────────────────────────────────────────────────

  Widget _buildPhotoRow() {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Add button
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: 80,
              height: 80,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
                color: Colors.deepPurple.withOpacity(0.05),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      color: Colors.deepPurple.shade300, size: 28),
                  const SizedBox(height: 4),
                  Text('Add',
                      style: TextStyle(
                          color: Colors.deepPurple.shade400, fontSize: 11)),
                ],
              ),
            ),
          ),
          // Existing photos
          ..._existingPhotoUrls.asMap().entries.map((entry) {
            return Stack(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                        image: NetworkImage(entry.value), fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 12,
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _existingPhotoUrls.removeAt(entry.key)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ],
            );
          }),
          // New photos
          ..._newPhotos.asMap().entries.map((entry) {
            return Stack(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                        image: FileImage(entry.value), fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => setState(() => _newPhotos.removeAt(entry.key)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: Colors.deepPurple),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Colors.deepPurple),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked =
        await _imagePicker.pickImage(source: source, imageQuality: 70);
    if (picked != null && mounted) {
      setState(() => _newPhotos.add(File(picked.path)));
    }
  }

  // ─── SAVE ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ingredientLines
        .any((l) => l.ingredientId.isEmpty || l.quantity <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Please complete all ingredient rows or remove empty ones.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final isEdit = widget.existing != null;
      final id = widget.existing?.id ??
          FirebaseFirestore.instance.collection('recipes').doc().id;

      // Upload new photos
      final uploadedUrls = <String>[];
      for (int i = 0; i < _newPhotos.length; i++) {
        final ref =
            FirebaseStorage.instance.ref().child('recipes/$id/photo_$i.jpg');
        await ref.putFile(_newPhotos[i]);
        uploadedUrls.add(await ref.getDownloadURL());
      }

      final allPhotoUrls = [..._existingPhotoUrls, ...uploadedUrls];
      final cleanInstructions =
          _instructions.where((s) => s.trim().isNotEmpty).toList();
      final now = DateTime.now();

      final recipe = RecipeModel(
        id: id,
        branchIds: widget.branchIds,
        name: _nameCtr.text.trim(),
        description: _descCtr.text.trim(),
        ingredients:
            _ingredientLines.where((l) => l.ingredientId.isNotEmpty).toList(),
        totalCost: _liveCost,
        instructions: cleanInstructions,
        prepTimeMinutes: int.tryParse(_prepTimeCtr.text) ?? 0,
        yield_: _yieldCtr.text.trim(),
        servingSize: _servingSizeCtr.text.trim(),
        difficultyLevel: _difficultyLevel,
        categoryTags: _categoryTags,
        allergenTags: [], // Handle allergens separately if needed later, using empty list for now
        photoUrls: allPhotoUrls,
        linkedMenuItemId: _linkedMenuItemId,
        linkedMenuItemName: _linkedMenuItemName,
        isActive: _isActive,
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
      );

      if (isEdit) {
        await widget.service.updateRecipe(
          recipe,
          previousLinkedMenuItemId: widget.existing?.linkedMenuItemId,
        );
      } else {
        await widget.service.addRecipe(recipe);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isEdit ? 'Recipe updated!' : 'Recipe added!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────

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

  Widget _buildTextInput(
    TextEditingController ctr,
    String label, {
    String? hint,
    bool required = false,
    int maxLines = 1,
    IconData? icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: ctr,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.deepPurple.shade300, size: 20)
            : null,
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
          : null,
    );
  }

  Widget _buildSelector({
    required String label,
    required String value,
    required List<String> items,
    required String Function(String) labelFn,
    required void Function(String) onChanged,
    IconData? icon,
  }) {
    IconData valueIcon = Icons.label_outline;
    if (label == 'Difficulty') {
      valueIcon = _getDifficultyIcon(value);
    }

    return InkWell(
      onTap: () => _showPicker(label, value, items, labelFn, onChanged),
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey[50],
          prefixIcon: Icon(icon ?? valueIcon,
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

  IconData _getDifficultyIcon(String level) {
    switch (level) {
      case 'easy':
        return Icons.sentiment_satisfied_alt_outlined;
      case 'medium':
        return Icons.sentiment_neutral_outlined;
      case 'hard':
        return Icons.sentiment_very_dissatisfied_outlined;
      default:
        return Icons.bar_chart_outlined;
    }
  }

  void _showPicker(
    String title,
    String current,
    List<String> items,
    String Function(String) labelFn,
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
                  IconData itemIcon = Icons.label_outline;
                  if (title == 'Difficulty')
                    itemIcon = _getDifficultyIcon(item);

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
}

class _MenuItemPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String? currentId;
  final Function(String, String) onSelect;

  const _MenuItemPickerSheet({
    required this.items,
    required this.currentId,
    required this.onSelect,
  });

  @override
  State<_MenuItemPickerSheet> createState() => _MenuItemPickerSheetState();
}

class _MenuItemPickerSheetState extends State<_MenuItemPickerSheet> {
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
          const Text('Link Menu Item',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search menu items…',
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
                      final id = item['id'] as String;
                      final name = item['name'] as String;
                      final selected = id == widget.currentId;

                      return ListTile(
                        onTap: () {
                          widget.onSelect(id, name);
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
                            Icons.restaurant_menu_outlined,
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
