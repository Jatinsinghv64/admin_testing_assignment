// lib/Screens/pos/PosScreen.dart
// Main POS Screen — Odoo-style split-pane with category sidebar + product grid + cart
// Includes POS ↔ Delivery toggle in the header bar

import 'dart:async';
import 'dart:collection';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../constants.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../services/pos/pos_service.dart';
import '../../services/pos/pos_models.dart';
import '../../services/inventory/menu_item_stock_assessment_service.dart';
import '../../Widgets/PrintingService.dart';
import 'PosProductTile.dart';
import 'PosCartPanel.dart';
import 'pos_payment_dialog.dart';
import 'pos_register_dialog.dart';
import 'DeliveryOrdersPanel.dart';
import 'DineInFloorPlanPanel.dart';
import 'components/VariantSelectionDialog.dart';
import '../../services/pos/pos_register_service.dart';

enum PosViewMode { pos, delivery, dineIn }

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final MenuItemStockAssessmentService _stockAssessmentService =
      MenuItemStockAssessmentService();
  String? _selectedCategoryId; // null = All
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _isSubmittingOrder = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _kitchenCancellationSubscription;
  final Queue<_KitchenCancellationAlert> _kitchenCancellationQueue =
      Queue<_KitchenCancellationAlert>();
  final Set<String> _shownKitchenCancellationAlertIds = <String>{};
  String? _kitchenCancellationBranchId;
  bool _isKitchenCancellationWatcherPrimed = false;
  bool _isKitchenCancellationDialogOpen = false;
  bool _isProductTapping = false; // Guard to prevent duplicate popups on fast taps
  bool _isRegisterDialogOpen = false; // Guard to prevent duplicate register dialogs (open OR close)
  bool _optedOutRegisterOpen = false; // User cancelled register opening

  // ── POS ↔ Delivery ↔ Dine In Toggle ──
  PosViewMode _viewMode = PosViewMode.pos;

  // ── Register Session ──
  final PosRegisterService _registerService = PosRegisterService();
  PosRegisterSession? _currentRegisterSession;
  /// True until the first register stream event fires — prevents the POS
  /// from briefly flashing before we know whether the register is open.
  bool _isRegisterLoading = true;
  StreamSubscription<PosRegisterSession?>? _registerSubscription;
  String? _activePosRegisterBranchId; // branch the subscription is tied to

  // ── Stream Caching ──
  Stream<QuerySnapshot>? _categoryStream;
  List<String> _lastCategoryBranchIds = [];

  Stream<QuerySnapshot>? _productStream;
  String? _lastProductBranchId;
  String? _lastCategoryId;

  // ── Ingredient Stock Stream (real-time out-of-stock detection) ──
  Stream<Set<String>>? _ingredientStockStream;
  String? _lastStockBranchId;

  @override
  void dispose() {
    _registerSubscription?.cancel();
    _kitchenCancellationSubscription?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Register Subscription Lifecycle
  // Manages the Firestore stream for the active register session.
  // Called from didChangeDependencies — safe lifecycle hook, never from build.
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final branchFilter =
        Provider.of<BranchFilterService>(context, listen: false);
    final globalBranchId = branchFilter.selectedBranchId;
    final isSingleBranch = globalBranchId != null &&
        globalBranchId != BranchFilterService.allBranchesValue;

    if (isSingleBranch) {
      // Sync PosService active branch without a postFrameCallback
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final pos = context.read<PosService>();
        if (pos.activeBranchId != globalBranchId) {
          pos.setActiveBranch(globalBranchId);
        }
      });
      // Start (or reuse) the register subscription for this branch
      if (_activePosRegisterBranchId != globalBranchId) {
        _startRegisterSubscription(globalBranchId);
      }
    } else {
      // No specific branch — tear down subscription
      _cancelRegisterSubscription();
    }
  }

  void _startRegisterSubscription(String branchId) {
    _registerSubscription?.cancel();
    _activePosRegisterBranchId = branchId;
    // Reset state directly (build follows didChangeDependencies so no setState needed)
    _isRegisterLoading = true;
    _optedOutRegisterOpen = false;
    _currentRegisterSession = null;

    _registerSubscription =
        _registerService.streamOpenSession(branchId).listen(
      (session) {
        if (!mounted) return;
        final wasOpen = _currentRegisterSession != null;
        final sessionIdChanged = _currentRegisterSession?.id != session?.id;
        setState(() {
          _isRegisterLoading = false;
          _currentRegisterSession = session;
        });
        // Sync session ID to PosService
        if (sessionIdChanged) {
          context.read<PosService>().setRegisterSessionId(session?.id);
        }
        // If register closed unexpectedly, reset opt-out so overlay shows
        if (wasOpen && session == null) {
          setState(() => _optedOutRegisterOpen = false);
          return;
        }
        // Auto-show open register dialog when no session and user hasn't dismissed
        if (session == null && !_isRegisterDialogOpen && !_optedOutRegisterOpen) {
          final userScope = context.read<UserScopeService>();
          if (userScope.branchIds.length == 1) {
            _showOpenRegisterDialog(context);
          } else {
            // Multi-branch users see the overlay and click the button themselves
            setState(() => _optedOutRegisterOpen = true);
          }
        }
      },
      onError: (error) {
        debugPrint('⚠️ POS: Register stream error: $error');
        if (mounted) setState(() => _isRegisterLoading = false);
      },
    );
  }

  void _cancelRegisterSubscription() {
    _registerSubscription?.cancel();
    _registerSubscription = null;
    _activePosRegisterBranchId = null;
    // Direct field mutation is safe here because build() always follows
    _isRegisterLoading = true;
    _currentRegisterSession = null;
    _optedOutRegisterOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final selectedBranchId =
        context.watch<BranchFilterService>().selectedBranchId;
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();

    final watcherBranchId = selectedBranchId != null &&
            selectedBranchId != BranchFilterService.allBranchesValue
        ? selectedBranchId
        : null;
    _scheduleKitchenCancellationWatcher(watcherBranchId);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildPosHeader(context),
          Expanded(
            child: _buildBranchCheckWrapper(
              context,
              userScope,
              branchFilter,
              (activeBranchId) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                child: _buildCurrentView(context, activeBranchId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleKitchenCancellationWatcher(String? activeBranchId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configureKitchenCancellationWatcher(activeBranchId);
    });
  }

  void _configureKitchenCancellationWatcher(String? activeBranchId) {
    final alreadyConfigured = _kitchenCancellationBranchId == activeBranchId &&
        (activeBranchId == null || _kitchenCancellationSubscription != null);
    if (alreadyConfigured) return;

    _kitchenCancellationSubscription?.cancel();
    _kitchenCancellationSubscription = null;
    _kitchenCancellationBranchId = activeBranchId;
    _isKitchenCancellationWatcherPrimed = false;
    _shownKitchenCancellationAlertIds.clear();
    _kitchenCancellationQueue.clear();

    if (activeBranchId == null || activeBranchId.isEmpty) {
      return;
    }

    _kitchenCancellationSubscription = FirebaseFirestore.instance
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContains: activeBranchId)
        .where('source', isEqualTo: 'pos')
        .orderBy('cancelledAt', descending: true)
        .limit(20)
        .snapshots()
        .listen(
      _handleKitchenCancellationSnapshot,
      onError: (error) {
        debugPrint('⚠️ POS: Kitchen cancellation watcher failed: $error');
      },
    );
  }

  void _handleKitchenCancellationSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final matchingDocs = snapshot.docs.where((doc) {
      final data = doc.data();
      return PosService.isKitchenRejected(data) &&
          data['status'] == AppConstants.statusCancelled &&
          data['cancelledAt'] is Timestamp;
    }).toList();

    if (!_isKitchenCancellationWatcherPrimed) {
      _shownKitchenCancellationAlertIds
          .addAll(matchingDocs.map((doc) => doc.id));
      _isKitchenCancellationWatcherPrimed = true;
      return;
    }

    for (final doc in matchingDocs) {
      if (_shownKitchenCancellationAlertIds.contains(doc.id)) continue;
      _shownKitchenCancellationAlertIds.add(doc.id);
      _kitchenCancellationQueue.add(
        _KitchenCancellationAlert.fromOrder(doc.id, doc.data()),
      );
    }

    _processKitchenCancellationAlerts();
  }

  void _processKitchenCancellationAlerts() {
    if (!mounted ||
        _isKitchenCancellationDialogOpen ||
        _kitchenCancellationQueue.isEmpty) {
      return;
    }

    final alert = _kitchenCancellationQueue.removeFirst();
    _isKitchenCancellationDialogOpen = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red[700]),
            const SizedBox(width: 10),
            const Expanded(child: Text('Order Cancelled in Kitchen')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alert.orderLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Reason: ${alert.reason}',
              style: TextStyle(color: Colors.grey[800], height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    ).whenComplete(() {
      _isKitchenCancellationDialogOpen = false;
      _processKitchenCancellationAlerts();
    });
  }

  Widget _buildCurrentView(BuildContext context, String activeBranchId) {
    switch (_viewMode) {
      case PosViewMode.delivery:
        return DeliveryOrdersPanel(
          key: const ValueKey('delivery'),
          onSwitchToPos: () => setState(() => _viewMode = PosViewMode.pos),
        );
      case PosViewMode.dineIn:
        return DineInFloorPlanPanel(
          key: const ValueKey('dineIn'),
          onSwitchToPos: () {
            setState(() => _viewMode = PosViewMode.pos);
          },
        );
      case PosViewMode.pos:
        return _buildPosBody(context, activeBranchId);
    }
  }

  // ── POS Body (Split pane) ──────────────────────────────────────
  Widget _buildPosBody(BuildContext context, String activeBranchId) {
    final userScope = Provider.of<UserScopeService>(context);
    final branchFilter = Provider.of<BranchFilterService>(context);
    final effectiveBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);

    bool categoryBranchChanged =
        _lastCategoryBranchIds.length != effectiveBranchIds.length;
    if (!categoryBranchChanged) {
      for (int i = 0; i < effectiveBranchIds.length; i++) {
        if (_lastCategoryBranchIds[i] != effectiveBranchIds[i]) {
          categoryBranchChanged = true;
          break;
        }
      }
    }

    if (categoryBranchChanged || _categoryStream == null) {
      _lastCategoryBranchIds = List.from(effectiveBranchIds);
      if (effectiveBranchIds.isNotEmpty) {
        _categoryStream = FirebaseFirestore.instance
            .collection(AppConstants.collectionMenuCategories)
            .where('branchIds', arrayContainsAny: effectiveBranchIds)
            .snapshots();
      } else {
        _categoryStream = null;
      }
    }

    return StreamBuilder<QuerySnapshot>(
        stream: _categoryStream ?? const Stream.empty(),
        builder: (context, catSnapshot) {
          final rawCategories = catSnapshot.data?.docs ?? [];
          // Sort client-side to avoid complex composite index requirements
          final categories = List<QueryDocumentSnapshot>.from(rawCategories);
          categories.sort((a, b) {
            final nameA = (a.data() as Map<String, dynamic>)['name']?.toString() ?? '';
            final nameB = (b.data() as Map<String, dynamic>)['name']?.toString() ?? '';
            return nameA.toLowerCase().compareTo(nameB.toLowerCase());
          });

          final Map<String, String> categoryMap = {
            for (var doc in categories)
              doc.id:
                  (doc.data() as Map<String, dynamic>)['name']?.toString() ??
                      'Category'
          };

          return Row(
            key: const ValueKey('pos'),
            children: [
              // ── Left: Products Panel (65%) ──
              Expanded(
                flex: 65,
                child: Row(
                  children: [
                    _buildCategorySidebar(context, categories, activeBranchId),
                    const VerticalDivider(width: 1),
                    Expanded(
                        child: _buildProductGrid(
                            context, categoryMap, activeBranchId)),
                  ],
                ),
              ),
              // ── Right: Cart Panel (35%) ──
              const VerticalDivider(width: 1),
              Expanded(
                flex: 35,
                child: PosCartPanel(
                  onOrderSubmit: () => _submitOrder(context, activeBranchId),
                  onPaymentTap: () =>
                      _openPaymentDialog(context, activeBranchId),
                  isSubmittingOrder: _isSubmittingOrder,
                ),
              ),
            ],
          );
        });
  }

  // ── Branch Enforcement Wrapper ──────────────────────────────
  // Pure display function — no state mutations, no callbacks.
  // All register state is managed by the StreamSubscription in
  // _startRegisterSubscription / _cancelRegisterSubscription.
  Widget _buildBranchCheckWrapper(
    BuildContext context,
    UserScopeService userScope,
    BranchFilterService branchFilter,
    Widget Function(String activeBranchId) builder,
  ) {
    final globalBranchId = branchFilter.selectedBranchId;

    // ① No specific branch selected — must pick one first
    if (globalBranchId == null ||
        globalBranchId == BranchFilterService.allBranchesValue) {
      return _buildBranchSelectionRequired();
    }

    // ② Register check in progress — show spinner (prevents POS flash)
    if (_isRegisterLoading) {
      return _buildRegisterCheckingLoader();
    }

    // ③ Register is closed — show locked overlay
    if (_currentRegisterSession == null) {
      return _buildRegisterClosedOverlay();
    }

    // ④ Register is open — show POS
    return builder(globalBranchId);
  }

  Widget _buildBranchSelectionRequired() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront,
                    size: 56, color: Colors.orange),
              ),
              const SizedBox(height: 32),
              const Text(
                'Branch Selection Required',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'Point of Sale operations must be tied to a specific location for accurate inventory and reporting.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey[600], fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 32),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.deepPurple.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward,
                        color: Colors.deepPurple[700], size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Please select a specific branch from the dropdown in the top App Bar.',
                        style: TextStyle(
                            color: Colors.deepPurple[800],
                            fontWeight: FontWeight.w600,
                            fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterCheckingLoader() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.deepPurple,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Checking register status…',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterClosedOverlay() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline,
                    size: 56, color: Colors.orange),
              ),
              const SizedBox(height: 32),
              const Text(
                'Register is Closed',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'You must open the register to start taking orders and managing the POS system.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey[600], fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showOpenRegisterDialog(context),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Open Register Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── POS Header Bar with Toggle ─────────────────────────────────
  Widget _buildPosHeader(BuildContext context) {
    final branchFilter = context.watch<BranchFilterService>();
    final userScope = context.watch<UserScopeService>();
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    final isSpecificBranchSelected = filterBranchIds.length == 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── POS ↔ Delivery Toggle ──
          _buildViewToggle(),

          const SizedBox(width: 20),

          // ── Active Table Info & Duration ──
          if (_viewMode == PosViewMode.pos)
            Consumer<PosService>(
              builder: (context, pos, child) {
                if (pos.selectedTableId != null) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.deepPurple.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.table_bar,
                            size: 16, color: Colors.deepPurple),
                        const SizedBox(width: 8),
                        Text(
                          pos.selectedTableName ?? 'Table',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.deepPurple,
                          ),
                        ),
                        if (pos.tableOccupiedAt != null)
                          _OccupancyDurationWidget(
                            occupiedAt: pos.tableOccupiedAt!,
                            color: Colors.red[700],
                            fontSize: 13,
                          ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

          const Spacer(),

          // ── Search Bar (POS mode only) ──
          if (_viewMode == PosViewMode.pos)
            SizedBox(
              width: 300,
              height: 42,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (value) {
                  setState(() => _searchQuery = value.toLowerCase());
                },
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  prefixIcon:
                      Icon(Icons.search, color: Colors.grey[400], size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close,
                              color: Colors.grey[400], size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                            _searchFocus.unfocus();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.deepPurple, width: 1.5),
                  ),
                ),
              ),
            ),
          // ── Register Button ──
          if (_viewMode == PosViewMode.pos && isSpecificBranchSelected) ...[
            const SizedBox(width: 12),
            _buildRegisterButton(context),
          ],
        ],
      ),
    );
  }

  Widget _buildRegisterButton(BuildContext context) {
    final isOpen = _currentRegisterSession != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isOpen ? () => _showCloseRegisterDialog(context) : () => _showOpenRegisterDialog(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isOpen ? Colors.green.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isOpen ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: isOpen ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isOpen ? 'Register Open' : 'Open Register',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isOpen ? Colors.green[800] : Colors.red[800],
                ),
              ),
              if (isOpen) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock_open, size: 14, color: Colors.green[600]),
              ] else ...[
                const SizedBox(width: 6),
                Icon(Icons.lock, size: 14, color: Colors.red[600]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Register session check is now handled by StreamBuilder in _buildBranchCheckWrapper

  Future<void> _showOpenRegisterDialog(BuildContext context) async {
    if (_isRegisterDialogOpen) return;
    if (!mounted) return;
    _isRegisterDialogOpen = true;

    try {
      final branchFilter = context.read<BranchFilterService>();
      final userScope = context.read<UserScopeService>();
      final activeBranchId = branchFilter.selectedBranchId ??
          (userScope.branchIds.isNotEmpty ? userScope.branchIds.first : '');
      if (activeBranchId.isEmpty) {
        _isRegisterDialogOpen = false;
        return;
      }

      final branchName = branchFilter.branchNames[activeBranchId] ?? 'Branch';
      final result = await showDialog<dynamic>(
        context: context,
        barrierDismissible: true, // Allow clicking outside to dismiss (opts out)
        builder: (_) => PosRegisterOpeningDialog(
          branchId: activeBranchId,
          branchName: branchName,
          userEmail: userScope.userEmail,
          registerService: _registerService,
        ),
      );
      if (result is PosRegisterSession && mounted) {
        setState(() {
          _currentRegisterSession = result;
          _optedOutRegisterOpen = false;
        });
      } else if (result == 'cancel' && mounted) {
        setState(() {
          _optedOutRegisterOpen = true;
        });
      }
    } finally {
      // Only reset the guard if dialog was dismissed WITHOUT opening
      // (i.e. result was null). If opened, StreamBuilder will detect
      // the session and won't re-trigger.
      if (mounted) {
        _isRegisterDialogOpen = false;
      }
    }
  }

  Future<void> _showCloseRegisterDialog(BuildContext context) async {
    if (_currentRegisterSession == null) return;
    if (_isRegisterDialogOpen) return;

    // ✅ NEW: Prevent closing register from "All Branches" view
    final branchFilter = Provider.of<BranchFilterService>(context, listen: false);
    if (branchFilter.selectedBranchId == BranchFilterService.allBranchesValue) {
      if (mounted) {
        _showMenuItemBlockedDialog(
          context,
          title: 'Select a Branch First',
          message:
              'You are currently viewing "All Branches". Please select the specific branch associated with this register session before attemptimg to close it.',
        );
      }
      return;
    }

    // Capture session reference before any async gap
    final session = _currentRegisterSession!;
    final userScope = Provider.of<UserScopeService>(context, listen: false);
    final isSuperAdmin = userScope.isSuperAdmin;

    // ── Check if there are active ongoing orders that need completing ──
    List<String> activeOrderNumbers = [];
    try {
      activeOrderNumbers = await _registerService.getActiveOrderIds(session.branchIds.first);
    } catch (e) {
      debugPrint('Error checking ongoing orders: $e');
    }

    if (activeOrderNumbers.isNotEmpty && !isSuperAdmin) {
      if (!mounted) return;
      _showMenuItemBlockedDialog(
        context,
        title: 'Active Orders Remaining',
        message:
            'The register cannot be closed because of ongoing orders: ${activeOrderNumbers.join(", ")}.\n\nPlease complete, cancel, or settle these orders before closing.',
      );
      return;
    }

    _isRegisterDialogOpen = true;

    // Show loading overlay while computing session metrics
    late final OverlayEntry loadingOverlay;
    loadingOverlay = OverlayEntry(
      builder: (_) => Container(
        color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.54),
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
    Overlay.of(context).insert(loadingOverlay);

    double totalSales = 0.0;
    RegisterSessionMetrics? metrics;
    try {
      final results = await Future.wait([
        _registerService.getSessionSales(session.branchIds.first, session.openedAt),
        _registerService.computeSessionMetrics(session.branchIds.first, session.openedAt),
      ]);
      totalSales = results[0] as double;
      metrics = results[1] as RegisterSessionMetrics;
    } catch (e) {
      debugPrint('Error calculating sales: $e');
    } finally {
      loadingOverlay.remove();
    }

    if (!mounted) {
      _isRegisterDialogOpen = false;
      return;
    }

    final result = await showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PosRegisterClosingDialog(
        session: session,
        userEmail: context.read<UserScopeService>().userEmail,
        registerService: _registerService,
        totalSales: totalSales,
        metrics: metrics,
        isForceClosed: activeOrderNumbers.isNotEmpty,
        activeOrderCount: activeOrderNumbers.length,
        isSuperAdmin: isSuperAdmin,
      ),
    );
    if (result == true && mounted) {
      setState(() {
        _currentRegisterSession = null;
        // StreamBuilder will detect null session and re-show dialog
      });
      // Clear the registerSessionId on PosService
      final pos = context.read<PosService>();
      pos.setRegisterSessionId(null);
    }
    _isRegisterDialogOpen = false;
  }

  // ── Animated POS / Delivery / Dine In Toggle ───────────────────────────────
  Widget _buildViewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            label: 'POS',
            icon: Icons.point_of_sale,
            isSelected: _viewMode == PosViewMode.pos,
            color: Colors.deepPurple,
            onTap: () => setState(() => _viewMode = PosViewMode.pos),
          ),
          _buildToggleButton(
            label: 'Order',
            icon: Icons.receipt_long,
            isSelected: _viewMode == PosViewMode.delivery,
            color: const Color(0xFFFF6F00),
            onTap: () => setState(() => _viewMode = PosViewMode.delivery),
          ),
          _buildToggleButton(
            label: 'Floor',
            icon: Icons.table_bar,
            isSelected: _viewMode == PosViewMode.dineIn,
            color: Colors.teal,
            onTap: () => setState(() => _viewMode = PosViewMode.dineIn),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Category Sidebar ────────────────────────────────────────
  Color _getCategoryColor(String? name) {
    if (name == null) return Colors.deepPurple;
    final normalized = name.toLowerCase();
    if (normalized.contains('drink') ||
        normalized.contains('beverage') ||
        normalized.contains('juice') ||
        normalized.contains('water')) {
      return Colors.red[400]!;
    }
    if (normalized.contains('dessert') ||
        normalized.contains('sweet') ||
        normalized.contains('cake') ||
        normalized.contains('ice cream')) {
      return Colors.amber[600]!;
    }
    if (normalized.contains('starter') ||
        normalized.contains('appetizer') ||
        normalized.contains('snack')) {
      return Colors.teal[400]!;
    }
    if (normalized.contains('main') ||
        normalized.contains('food') ||
        normalized.contains('dish') ||
        normalized.contains('dinner')) {
      return Colors.blue[600]!;
    }
    if (normalized.contains('burger') ||
        normalized.contains('pizza') ||
        normalized.contains('fast food')) {
      return Colors.orange[700]!;
    }
    if (normalized.contains('vegan') ||
        normalized.contains('salad') ||
        normalized.contains('healthy')) {
      return Colors.green[600]!;
    }
    // Deterministic fallback based on name hash
    final hash = name.hashCode.abs();
    final colList = [
      Colors.deepPurple[400]!,
      Colors.indigo[400]!,
      Colors.cyan[600]!,
      Colors.pink[400]!,
      Colors.brown[400]!,
    ];
    return colList[hash % colList.length];
  }

  Widget _buildCategorySidebar(BuildContext context,
      List<QueryDocumentSnapshot> categories, String activeBranchId) {
    return Container(
      width: 130,
      color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.02) : Theme.of(context).cardColor,
      child: Column(
        children: [
          // "All" category
          _buildCategoryItem(
              null, 'All Items', Icons.apps_rounded, Colors.deepPurple),
          const Divider(height: 1),
          // Categories passed from parent
          Expanded(
            child: categories.isEmpty
                ? const Center(
                    child: Text(
                      'No categories',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  )
                : _buildCategoryList(categories),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList(List<QueryDocumentSnapshot> categories) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: categories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final catData = cat.data() as Map<String, dynamic>;
        final name = catData['name']?.toString() ?? 'Category';
        final color = _getCategoryColor(name);
        return _buildCategoryItem(cat.id, name, Icons.restaurant_menu, color);
      },
    );
  }

  Widget _buildCategoryItem(
      String? id, String name, IconData icon, Color color) {
    final isSelected = _selectedCategoryId == id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedCategoryId = id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color:
                isSelected ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.02),
            border: Border(
              left: BorderSide(
                color: isSelected ? color : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? color.withValues(alpha: 0.9) : Colors.grey[800],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Product Grid ──────────────────────────────────────────
  Widget _buildProductGrid(BuildContext context,
      Map<String, String> categoryMap, String activeBranchId) {
    if (_lastProductBranchId != activeBranchId ||
        _lastCategoryId != _selectedCategoryId ||
        _productStream == null) {
      _lastProductBranchId = activeBranchId;
      _lastCategoryId = _selectedCategoryId;

      Query query = FirebaseFirestore.instance
          .collection(AppConstants.collectionMenuItems);
      query = query.where('branchIds', arrayContains: activeBranchId);

      if (_selectedCategoryId != null) {
        query = query.where('categoryId', isEqualTo: _selectedCategoryId);
      }

      // ORDER BY 'name' removed to avoid composite index requirements with branchIds + categoryId filters.
      // We sort client-side in the StreamBuilder.
      _productStream = query.snapshots();
    }

    // Initialize ingredient stock stream for real-time out-of-stock detection
    if (_lastStockBranchId != activeBranchId || _ingredientStockStream == null) {
      _lastStockBranchId = activeBranchId;
      _ingredientStockStream = _stockAssessmentService
          .streamMenuItemStockStatuses(branchId: activeBranchId);
    }

    return StreamBuilder<Set<String>>(
      stream: _ingredientStockStream,
      builder: (context, stockSnapshot) {
        final ingredientOutOfStockIds = stockSnapshot.data ?? <String>{};

        return StreamBuilder<QuerySnapshot>(
      stream: _productStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                const SizedBox(height: 12),
                Text(
                  'Failed to load products',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _productStream = null;
                    });
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restaurant_menu, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No products found',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        var docs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);

        // Sort client-side consistently to avoid index-related query failures
        docs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final nameA = (dataA['name'] ?? '').toString().toLowerCase();
          final nameB = (dataB['name'] ?? '').toString().toLowerCase();
          return nameA.compareTo(nameB);
        });

        // Apply search filter client-side
        if (_searchQuery.isNotEmpty) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['name'] ?? '').toString().toLowerCase();
            return name.contains(_searchQuery);
          }).toList();
        }

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No results for "$_searchQuery"',
                  style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.6,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final name = data['name']?.toString() ?? 'Item';
            final price = (data['price'] ?? 0).toDouble();
            final imageUrl = data['imageUrl']?.toString();
            final isAvailable = data['isAvailable'] == true;
            final outOfStockBranches =
                List<String>.from(data['outOfStockBranches'] ?? const []);
            final isMarkedOutOfStock =
                outOfStockBranches.contains(activeBranchId);
            // Check if any ingredient is out of stock for this branch
            final isIngredientOutOfStock =
                ingredientOutOfStockIds.contains(doc.id);

            final catId = data['categoryId']?.toString();
            final catName =
                categoryMap[catId] ?? data['categoryName']?.toString();
            final chinColor = _getCategoryColor(catName);

            return PosProductTile(
              name: name,
              price: price,
              imageUrl: imageUrl,
              isAvailable: isAvailable && !isMarkedOutOfStock && !isIngredientOutOfStock,
              disableTapWhenUnavailable: false,
              unavailableLabel:
                  (isMarkedOutOfStock || isIngredientOutOfStock) ? 'Out of Stock' : 'Unavailable',
              chinColor: chinColor,
                onTap: () async {
                  if (_isProductTapping) return;
                  setState(() => _isProductTapping = true);
                  
                  try {
                    if (!isAvailable) {
                      await _showMenuItemBlockedDialog(
                        context,
                        title: 'Dish Unavailable',
                        message:
                            '"$name" is currently disabled in menu settings for this branch.',
                      );
                      return;
                    }

                    if (isMarkedOutOfStock) {
                      await _showMenuItemBlockedDialog(
                        context,
                        title: 'Out of Stock',
                        message:
                            '"$name" is marked out of stock for this branch. Restock its ingredients or update the dish availability before adding it.',
                      );
                      return;
                    }

                    if (isIngredientOutOfStock) {
                      await _showMenuItemBlockedDialog(
                        context,
                        title: 'Ingredient Out of Stock',
                        message:
                            '"$name" has one or more ingredients that are out of stock for this branch. Please restock the required ingredients before adding this dish.',
                      );
                      return;
                    }

                    // ── Fast-path: instant recipe check (no Firestore round-trip) ──
                    final recipeId = (data['recipeId'] ?? '').toString().trim();
                    if (recipeId.isEmpty) {
                      // No recipe linked — show warning instantly
                      final proceed = await showDialog<bool>(
                        context: this.context,
                        builder: (dialogContext) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          title: Row(children: [
                            Icon(Icons.link_off, color: Colors.orange[700]),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Recipe Not Integrated')),
                          ]),
                          content: Text(
                            '"$name" does not have a recipe linked. Inventory tracking will not work for this item. Do you want to add it anyway?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Add Anyway'),
                            ),
                          ],
                        ),
                      );
                      if (proceed != true || !mounted) return;
                    } else {
                      // ── Recipe exists: run full stock assessment ──
                      final assessment = await _stockAssessmentService.assessMenuItem(
                        menuItemId: doc.id,
                        menuItemName: name,
                        explicitRecipeId: recipeId,
                        branchId: activeBranchId,
                      );
                      if (!mounted) return;

                      final canProceed = await _confirmStockAssessmentForAdd(
                        context: this.context,
                        itemName: name,
                        assessment: assessment,
                      );
                      if (!canProceed || !mounted) return;
                    }

                    final pos = this.context.read<PosService>();
                    final variants = data['variants'] as Map<String, dynamic>?;

                    List<PosAddon> selectedAddons = [];
                    if (variants != null && variants.isNotEmpty) {
                      if (!mounted) return;
                      final result = await showDialog<List<PosAddon>>(
                        context: this.context,
                        builder: (ctx) => VariantSelectionDialog(
                          productName: name,
                          variants: variants,
                        ),
                      );
                      if (result == null) return; // User cancelled
                      selectedAddons = result;
                    }

                    pos.addItem(PosCartItem(
                      productId: doc.id,
                      name: name,
                      nameAr: (data['name_ar'] ?? data['nameAr'])?.toString(),
                      price: price,
                      imageUrl: imageUrl,
                      categoryId: catId,
                      categoryName: catName,
                      addons: selectedAddons,
                    ));
                  } finally {
                    if (mounted) setState(() => _isProductTapping = false);
                  }
                },
            );
          },
        );
      },
    );
      },
    );
  }

  Future<void> _showMenuItemBlockedDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[600]),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmStockAssessmentForAdd({
    required BuildContext context,
    required String itemName,
    required MenuItemStockAssessment assessment,
  }) async {
    if (!assessment.needsAttention) {
      return true;
    }

    final hasBlockingIssues = assessment.hasBlockingIssues;
    final hasLowStockIssues = assessment.hasLowStockIssues;
    final accentColor = hasBlockingIssues
        ? Colors.red
        : hasLowStockIssues
            ? Colors.orange
            : Colors.blue;
    final summaryColor = hasBlockingIssues
        ? Colors.red.shade700
        : hasLowStockIssues
            ? Colors.orange.shade800
            : Colors.blue.shade700;
    final title = hasBlockingIssues
        ? 'Out of Stock'
        : hasLowStockIssues
            ? 'Low Stock Warning'
            : 'Inventory Tracking Warning';
    final summary = hasBlockingIssues
        ? '"$itemName" uses ingredients that are currently out of stock.'
        : hasLowStockIssues
            ? '"$itemName" uses low-stock ingredients.'
            : '"$itemName" is not fully connected to inventory tracking.';
    final primaryLabel = hasBlockingIssues
        ? 'Close'
        : hasLowStockIssues
            ? 'Add Anyway'
            : 'Continue';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !hasBlockingIssues,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              hasBlockingIssues
                  ? Icons.cancel_rounded
                  : Icons.inventory_2_rounded,
              color: accentColor,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    summary,
                    style: TextStyle(
                      color: summaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (assessment.warnings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Warnings',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...assessment.warnings.map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(warning)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (assessment.ingredientIssues.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Affected Ingredients',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...assessment.ingredientIssues.map(
                    (issue) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: issue.isBlocking
                            ? Colors.red.withValues(alpha: 0.05)
                            : Colors.orange.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: issue.isBlocking
                              ? Colors.red.withValues(alpha: 0.18)
                              : Colors.orange.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  issue.ingredientName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.87),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: issue.isBlocking
                                      ? Colors.red.withValues(alpha: 0.12)
                                      : Colors.orange.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  issue.statusLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: issue.isBlocking
                                        ? Colors.red.shade700
                                        : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Available: ${issue.availableStock.toStringAsFixed(2)} ${issue.unit}  |  Need: ${issue.requiredStock.toStringAsFixed(2)} ${issue.unit}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Possible servings at current stock: ${issue.possibleServings}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                          if (issue.note?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              issue.note!,
                              style: TextStyle(
                                fontSize: 12,
                                color: issue.isBlocking
                                    ? Colors.red.shade700
                                    : Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (!hasBlockingIssues)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, !hasBlockingIssues),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
            ),
            child: Text(primaryLabel),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  // ── Actions ─────────────────────────────────────────────────
  Future<void> _submitOrder(BuildContext context, String activeBranchId) async {
    // ── REGISTER GUARD: Block orders when register is closed ──
    if (_currentRegisterSession == null) {
      if (mounted) {
        _showMenuItemBlockedDialog(
          context,
          title: 'Register Not Open',
          message:
              'You must open the register before submitting orders. This ensures accurate cash tracking and end-of-day reconciliation.',
        );
      }
      return;
    }

    final pos = context.read<PosService>();
    final userScope = context.read<UserScopeService>();

    if (pos.orderType == PosOrderType.dineIn && pos.selectedTableId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a table for dine-in orders'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isSubmittingOrder = true;
    });

    try {
      await pos.submitOrder(
        userScope: userScope,
        branchIds: [activeBranchId],
        initialStatus: AppConstants.statusPending,
      );

      if (mounted) {
        // Clear search and category filters upon success
        _searchController.clear();
        setState(() {
          _searchQuery = '';
          _selectedCategoryId = null;
          _searchFocus.unfocus();
        });

        // User requested: "after placing an order the receipt should not appear"
        // _printReceipt(orderId);
      }
    } catch (e) {
      final errorMessage = PosService.displayError(e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit order: $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingOrder = false;
        });
      }
    }
  }

  Future<void> _openPaymentDialog(
      BuildContext context, String activeBranchId) async {
    // ── REGISTER GUARD: Block payment when register is closed ──
    if (_currentRegisterSession == null) {
      if (mounted) {
        _showMenuItemBlockedDialog(
          context,
          title: 'Register Not Open',
          message:
              'You must open the register before processing payments. This ensures accurate cash tracking and end-of-day reconciliation.',
        );
      }
      return;
    }

    final pos = context.read<PosService>();

    if (pos.orderType == PosOrderType.dineIn && pos.selectedTableId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please select a table for dine-in orders before payment.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Use centralized state from PosService
    double existingTableTotal = pos.ongoingTotal;
    List<DocumentSnapshot> existingOrders = pos.ongoingOrders;

    if ((pos.total + existingTableTotal) <= 0.001) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No outstanding balance. Active table orders are already prepaid.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: pos,
        child: PosPaymentDialog(
          totalAmount: pos.total,
          branchIds: [activeBranchId],
          existingTableTotal: existingTableTotal,
          existingOrders: existingOrders,
          onPaymentComplete: (orderId) {
            if (orderId != null) {
              if (!context.mounted) return;
              // Clear search and category filters upon success
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedCategoryId = null;
                _searchFocus.unfocus();
              });

              // Prompt to print receipt
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (promptCtx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[600]),
                      const SizedBox(width: 10),
                      const Text('Payment Successful'),
                    ],
                  ),
                  content: const Text('Do you want to print the receipt?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(promptCtx),
                      child: const Text('No'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(promptCtx);
                        _printReceipt(orderId);
                      },
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Print Receipt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _printReceipt(String orderId) async {
    try {
      final orderDoc = await FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc(orderId)
          .get();

      if (orderDoc.exists && mounted) {
        await PrintingService.printReceipt(context, orderDoc);
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching order for receipt: $e');
    }
  }
}

class _KitchenCancellationAlert {
  final String orderId;
  final String orderLabel;
  final String reason;

  const _KitchenCancellationAlert({
    required this.orderId,
    required this.orderLabel,
    required this.reason,
  });

  factory _KitchenCancellationAlert.fromOrder(
    String orderId,
    Map<String, dynamic> data,
  ) {
    final dailyNumber = data['dailyOrderNumber']?.toString();
    final tableName = data['tableName']?.toString();
    final customerName = data['customerName']?.toString();
    final reason =
        (data['cancellationReason']?.toString().trim().isNotEmpty ?? false)
            ? data['cancellationReason'].toString().trim()
            : 'No reason provided';

    final labelBuffer = StringBuffer(
      dailyNumber != null && dailyNumber.isNotEmpty
          ? 'Order #$dailyNumber'
          : 'Order ${orderId.substring(0, orderId.length < 6 ? orderId.length : 6).toUpperCase()}',
    );

    if (tableName != null && tableName.isNotEmpty) {
      labelBuffer.write(' · $tableName');
    } else if (customerName != null && customerName.isNotEmpty) {
      labelBuffer.write(' · $customerName');
    }

    return _KitchenCancellationAlert(
      orderId: orderId,
      orderLabel: labelBuffer.toString(),
      reason: reason,
    );
  }
}

class _OccupancyDurationWidget extends StatelessWidget {
  final DateTime occupiedAt;
  final Color? color;
  final double? fontSize;

  const _OccupancyDurationWidget(
      {required this.occupiedAt, this.color, this.fontSize});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 30)),
      builder: (context, _) {
        final duration = DateTime.now().difference(occupiedAt);
        final minutes = duration.inMinutes;
        final hours = duration.inHours;
        final remainingMinutes = minutes % 60;
        final text =
            hours > 0 ? '${hours}h ${remainingMinutes}m' : '${minutes}m';
        return Text(
          ' ($text)',
          style: TextStyle(
            fontSize: fontSize ?? 12,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.red,
          ),
        );
      },
    );
  }
}
