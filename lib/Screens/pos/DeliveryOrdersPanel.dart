// lib/Screens/pos/DeliveryOrdersPanel.dart
// Delivery Orders panel — streams Snoonu & Talabat orders from Firestore

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../constants.dart';
import '../../Widgets/BranchFilterService.dart';
import '../../Widgets/OrderUIComponents.dart';
import '../../Widgets/PrintingService.dart';
import '../../Widgets/TimeUtils.dart';
import '../../services/pos/pos_service.dart';
import '../../services/pos/pos_models.dart';

// ── Platform Filter ─────────────────────────────────────────────
enum DeliveryPlatform { all, snoonu, talabat, keta, takeaway, dineIn }

extension DeliveryPlatformExt on DeliveryPlatform {
  String get label {
    switch (this) {
      case DeliveryPlatform.all:
        return 'All';
      case DeliveryPlatform.snoonu:
        return 'Snoonu';
      case DeliveryPlatform.talabat:
        return 'Talabat';
      case DeliveryPlatform.keta:
        return 'Keta';
      case DeliveryPlatform.takeaway:
        return 'Takeaway';
      case DeliveryPlatform.dineIn:
        return 'Dine-in';
    }
  }

  Color get color {
    switch (this) {
      case DeliveryPlatform.all:
        return Colors.deepPurple;
      case DeliveryPlatform.snoonu:
        return const Color(0xFF00C853);
      case DeliveryPlatform.talabat:
        return const Color(0xFFFF6F00);
      case DeliveryPlatform.keta:
        return Colors.blueAccent;
      case DeliveryPlatform.takeaway:
        return Colors.brown;
      case DeliveryPlatform.dineIn:
        return Colors.indigo;
    }
  }

  IconData get icon {
    switch (this) {
      case DeliveryPlatform.all:
        return Icons.delivery_dining;
      case DeliveryPlatform.snoonu:
        return Icons.electric_moped;
      case DeliveryPlatform.talabat:
        return Icons.moped;
      case DeliveryPlatform.keta:
        return Icons.shopping_bag;
      case DeliveryPlatform.takeaway:
        return Icons.takeout_dining;
      case DeliveryPlatform.dineIn:
        return Icons.restaurant;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// DeliveryOrdersPanel
// ═══════════════════════════════════════════════════════════════════
class DeliveryOrdersPanel extends StatefulWidget {
  final VoidCallback onSwitchToPos;
  const DeliveryOrdersPanel({super.key, required this.onSwitchToPos});

  @override
  State<DeliveryOrdersPanel> createState() => _DeliveryOrdersPanelState();
}

class _DeliveryOrdersPanelState extends State<DeliveryOrdersPanel>
    with SingleTickerProviderStateMixin {
  DeliveryPlatform _selectedPlatform = DeliveryPlatform.all;
  String? _selectedOrderId;
  DocumentSnapshot? _selectedOrderDoc;
  late final TabController _tabController;
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: DeliveryPlatform.values.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedPlatform = DeliveryPlatform.values[_tabController.index];
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildPlatformTabs(),
        Expanded(
          child: Row(
            children: [
              // Left side: Orders list (40% width)
              Expanded(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: _buildOrdersList(),
                ),
              ),
              // Right side: Order Details (60% width)
              Expanded(
                flex: 6,
                child: _buildOrderDetailView(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderDetailView() {
    if (_selectedOrderId == null || _selectedOrderDoc == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Select an order to view details',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return _OrderDetailView(
      order: _selectedOrderDoc!,
      onSwitchToPos: widget.onSwitchToPos,
      onClose: () => setState(() {
        _selectedOrderId = null;
        _selectedOrderDoc = null;
      }),
    );
  }

  // ── Platform Tabs ──────────────────────────────────────────────
  Widget _buildPlatformTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ...DeliveryPlatform.values.map((platform) {
            final isSelected = _selectedPlatform == platform;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedPlatform = platform);
                    _tabController.animateTo(platform.index);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? platform.color.withOpacity(0.12)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? platform.color
                            : Colors.grey.withOpacity(0.2),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(platform.icon,
                            size: 18,
                            color: isSelected
                                ? platform.color
                                : Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          platform.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? platform.color
                                : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Layout Toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLayoutToggleButton(
                  icon: Icons.list_rounded,
                  isSelected: !_isGridView,
                  onTap: () => setState(() => _isGridView = false),
                ),
                _buildLayoutToggleButton(
                  icon: Icons.grid_view_rounded,
                  isSelected: _isGridView,
                  onTap: () => setState(() => _isGridView = true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutToggleButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: isSelected ? Colors.deepPurple : Colors.grey[400],
        ),
      ),
    );
  }

  // ── Orders List ────────────────────────────────────────────────
  Widget _buildOrdersList() {
    final userScope = Provider.of<UserScopeService>(context);
    final branchFilter = Provider.of<BranchFilterService>(context);
    final effectiveBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);

    if (effectiveBranchIds.isEmpty) {
      return _buildEmptyState('No branch selected', Icons.store_outlined);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _getDeliveryOrdersStream(effectiveBranchIds),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }

        // Client-side filter: remove terminal (completed) orders
        final orders = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _isActiveOrder(data);
        }).toList();

        if (orders.isEmpty) {
          return _buildEmptyState(
            'No active ${_selectedPlatform == DeliveryPlatform.all ? 'delivery' : _selectedPlatform.label} orders',
            Icons.delivery_dining_outlined,
          );
        }

        if (_isGridView) {
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9, // Slightly taller for better fit
            ),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;
              final isSelected = _selectedOrderId == doc.id;

              return InkWell(
                onTap: () => setState(() {
                  _selectedOrderId = doc.id;
                  _selectedOrderDoc = doc;
                }),
                child: _DeliveryOrderGridCard(
                  orderId: doc.id,
                  data: data,
                  isSelected: isSelected,
                ),
              );
            },
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final doc = orders[index];
            final data = doc.data() as Map<String, dynamic>;
            final isSelected = _selectedOrderId == doc.id;

            return InkWell(
              onTap: () => setState(() {
                _selectedOrderId = doc.id;
                _selectedOrderDoc = doc;
              }),
              child: _DeliveryOrderCard(
                orderId: doc.id,
                data: data,
                branchIds: effectiveBranchIds,
                isSelected: isSelected,
              ),
            );
          },
        );
      },
    );
  }

  // ── Firestore Stream ───────────────────────────────────────────
  // NOTE: Firestore does NOT allow combining 'whereIn' with 'whereNotIn'
  // in a single query. So we fetch all orders for the platform source(s)
  // and filter out terminal statuses client-side.
  Stream<QuerySnapshot> _getDeliveryOrdersStream(List<String> branchIds) {
    Query query = FirebaseFirestore.instance
        .collection(AppConstants.collectionOrders)
        .where('branchIds', arrayContainsAny: branchIds);

    // Filter by order category
    switch (_selectedPlatform) {
      case DeliveryPlatform.snoonu:
        query = query.where('source', isEqualTo: 'snoonu');
        break;
      case DeliveryPlatform.talabat:
        query = query.where('source', isEqualTo: 'talabat');
        break;
      case DeliveryPlatform.keta:
        query = query.where('source', isEqualTo: 'keta');
        break;
      case DeliveryPlatform.takeaway:
        query = query.where('Order_type', isEqualTo: AppConstants.orderTypeTakeaway);
        break;
      case DeliveryPlatform.dineIn:
        query = query.where('Order_type', isEqualTo: AppConstants.orderTypeDineIn);
        break;
      case DeliveryPlatform.all:
      default:
        // By default, if "All" is selected in this specific panel, we might want 
        // to show all ACTIVE orders across these categories.
        // But the previous logic was specifically for delivery aggregators.
        // User wants "all on going orders of snoonu, keta, talabat, takeaway and dine"
        break;
    }

    // Performance optimization: Only fetch tickets from current business day to avoid lag when showing paid orders
    final startOfShift = TimeUtils.getBusinessStartTimestamp();
    query = query
        .where('timestamp', isGreaterThanOrEqualTo: startOfShift)
        .orderBy('timestamp', descending: true);

    return query.snapshots();
  }

  /// Filter out terminal (completed) orders client-side
  static const _terminalStatuses = {
    'delivered',
    'cancelled',
    'paid',
    'collected',
  };

  bool _isActiveOrder(Map<String, dynamic> data) {
    final status = (data['status']?.toString() ?? '').toLowerCase();
    final orderType = (data['Order_type'] ?? '').toString();
    final source = (data['source'] ?? '').toString().toLowerCase();

    // Client-side filter for "All" view to include user's requested types
    if (_selectedPlatform == DeliveryPlatform.all) {
      final isRequestedSource = ['snoonu', 'talabat', 'keta'].contains(source);
      final isRequestedType = [AppConstants.orderTypeDineIn, AppConstants.orderTypeTakeaway].contains(orderType);
      if (!isRequestedSource && !isRequestedType) return false;
    }

    // Show paid/collected orders in the list even though they are terminal statuses
    if (status == AppConstants.statusPaid || status == AppConstants.statusCollected) {
      return true;
    }

    return !AppConstants.isTerminalStatus(status);
  }

  // ── Loading State ──────────────────────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _selectedPlatform.color,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading orders...',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────────
  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Delivery orders from Snoonu & Talabat\nwill appear here in real-time',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  // ── Error State ────────────────────────────────────────────────
  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 40, color: Colors.red[400]),
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to load orders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Delivery Order Card
// ═══════════════════════════════════════════════════════════════════
class _DeliveryOrderCard extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final List<String> branchIds;
  final bool isSelected;

  const _DeliveryOrderCard({
    required this.orderId,
    required this.data,
    required this.branchIds,
    this.isSelected = false,
  });

  @override
  State<_DeliveryOrderCard> createState() => _DeliveryOrderCardState();
}

class _DeliveryOrderCardState extends State<_DeliveryOrderCard> {
  bool _isUpdating = false;

  String get _source =>
      (widget.data['source']?.toString() ?? 'unknown').toLowerCase();
  String get _status =>
      widget.data['status']?.toString() ?? AppConstants.statusPending;

  Color get _platformColor {
    if (_source == 'snoonu') return const Color(0xFF00C853);
    if (_source == 'talabat') return const Color(0xFFFF6F00);
    return Colors.grey;
  }

  String get _platformLabel {
    if (_source == 'snoonu') return 'SNOONU';
    if (_source == 'talabat') return 'TALABAT';
    return _source.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final orderNumber =
        OrderNumberHelper.getDisplayNumber(widget.data, orderId: widget.orderId);
    final customerName =
        widget.data['customerName']?.toString() ?? 'Customer';
    final totalAmount = (widget.data['totalAmount'] ?? 0).toDouble();
    final timestamp = widget.data['timestamp'];
    final tableNum = widget.data['tableNumber']?.toString() ?? widget.data['tableName']?.toString();
    final orderType = widget.data['Order_type']?.toString() ?? 'delivery';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isSelected ? Colors.deepPurple.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isSelected ? Colors.deepPurple : Colors.grey.withOpacity(0.12),
          width: widget.isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Left: Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '#$orderNumber',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (tableNum != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'T-$tableNum',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _buildPaymentTag(widget.data['isPaid'] == true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  customerName,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Right: Status & Price
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${AppConstants.currencySymbol}${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
              ),
              const SizedBox(height: 4),
              _buildStatusBadge(),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildStatusBadge() {
    final displayText = AppConstants.getStatusDisplayText(_status);
    Color badgeColor;
    switch (_status) {
      case AppConstants.statusPending:
        badgeColor = Colors.orange;
        break;
      case AppConstants.statusPreparing:
        badgeColor = Colors.blue;
        break;
      case AppConstants.statusPrepared:
      case 'ready':
        badgeColor = Colors.green;
        break;
      case AppConstants.statusRiderAssigned:
      case AppConstants.statusPickedUp:
      case AppConstants.statusPickedUpLegacy:
        badgeColor = Colors.teal;
        break;
      case AppConstants.statusPaid:
      case AppConstants.statusCollected:
        badgeColor = Colors.deepPurple;
        break;
      default:
        badgeColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: badgeColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildPaymentTag(bool isPaid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPaid ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPaid ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPaid ? Icons.check_circle : Icons.pending_outlined,
            size: 10,
            color: isPaid ? Colors.green : Colors.orange[800],
          ),
          const SizedBox(width: 4),
          Text(
            isPaid ? 'PAID' : 'UNPAID',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isPaid ? Colors.green : Colors.orange[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    String label;
    Color color;
    IconData icon;
    String? nextStatus;

    switch (_status) {
      case AppConstants.statusPending:
        label = 'Accept';
        color = Colors.green;
        icon = Icons.check_circle_outline;
        nextStatus = AppConstants.statusPreparing;
        break;
      case AppConstants.statusPreparing:
        label = 'Mark Ready';
        color = Colors.blue;
        icon = Icons.kitchen;
        nextStatus = AppConstants.statusPrepared;
        break;
      case AppConstants.statusPrepared:
      case 'ready':
        label = 'Picked Up';
        color = Colors.teal;
        icon = Icons.delivery_dining;
        nextStatus = AppConstants.statusPickedUp;
        break;
      default:
        // No action available for other statuses
        return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      width: double.infinity, // Ensure it fills available width
      child: ElevatedButton.icon(
        onPressed: _isUpdating ? null : () => _updateOrderStatus(nextStatus!),
        icon: _isUpdating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          _isUpdating ? 'Updating...' : label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Future<void> _updateOrderStatus(String newStatus) async {
    if (_isUpdating) return; // Debounce

    setState(() => _isUpdating = true);

    try {
      final updates = <String, dynamic>{
        'status': newStatus,
        'timestamps.$newStatus': FieldValue.serverTimestamp(),
      };

      // Add preparing timestamp when accepting
      if (newStatus == AppConstants.statusPreparing) {
        updates['preparingAt'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc(widget.orderId)
          .update(updates)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order #${OrderNumberHelper.getDisplayNumber(widget.data, orderId: widget.orderId)} → ${AppConstants.getStatusDisplayText(newStatus)}',
            ),
            backgroundColor: Colors.green[600],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// _OrderDetailView
// ═══════════════════════════════════════════════════════════════════
class _OrderDetailView extends StatefulWidget {
  final DocumentSnapshot order;
  final VoidCallback onClose;
  final VoidCallback onSwitchToPos;

  const _OrderDetailView({
    required this.order,
    required this.onClose,
    required this.onSwitchToPos,
  });

  @override
  State<_OrderDetailView> createState() => _OrderDetailViewState();
}

class _OrderDetailViewState extends State<_OrderDetailView> {
  bool _isUpdating = false;

  String get _status => (widget.order.data() as Map<String, dynamic>?)?['status']?.toString() ?? 'pending';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc(widget.order.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final doc = snapshot.data!;
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final orderNum = OrderNumberHelper.getDisplayNumber(data, orderId: doc.id);
        final status = data['status']?.toString() ?? 'pending';
        final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
        final total = (data['totalAmount'] as num? ?? 0).toDouble();
        final orderType = (data['Order_type'] ?? 'delivery').toString();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(left: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(context, orderNum),
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusBanner(status, orderType),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Items'),
                      const SizedBox(height: 12),
                      ...items.map((item) => _buildItemRow(item)),
                      const Divider(height: 40),
                      _buildTotalRow(total),
                    ],
                  ),
                ),
              ),
              // Footer actions
              _buildFooter(context, doc, data),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, String orderNum) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Text(
            'Order #$orderNum',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 28),
            color: Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(String status, String orderType) {
    final color = StatusUtils.getColor(status);
    final text = StatusUtils.getDisplayText(status, orderType: orderType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT STATUS',
                  style: TextStyle(
                    color: color.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.grey[400],
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? 'Item';
    final qty = item['quantity'] ?? 1;
    final total = (item['total'] ?? 0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text('Qty: $qty', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          Text(
            '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(double total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'TOTAL AMOUNT',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, DocumentSnapshot doc, Map<String, dynamic> data) {
    String? nextStatus;
    String statusLabel = '';
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check;

    final status = (data['status']?.toString() ?? 'pending').toLowerCase();
    final orderType = (data['Order_type'] ?? '').toString();
    final source = (data['source'] ?? '').toString().toLowerCase();

    // Check if it's an ongoing dine-in or takeaway order that is NOT paid
    final isPaid = data['isPaid'] == true;
    final isOngoing = (orderType == AppConstants.orderTypeDineIn ||
            orderType == AppConstants.orderTypeTakeaway) &&
        !AppConstants.isTerminalStatus(status) &&
        !isPaid;

    // Aggregators usually don't have "LOAD ORDER" as they flow to KDS/Rider assignment
    final isAggregator = ['snoonu', 'talabat', 'keta'].contains(source);
    final showLoadOrder = isOngoing && !isAggregator;

    if (data['status'] == AppConstants.statusPending) {
      nextStatus = AppConstants.statusPreparing;
      statusLabel = 'ACCEPT ORDER';
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (data['status'] == AppConstants.statusPreparing) {
      nextStatus = AppConstants.statusPrepared;
      statusLabel = 'MARK AS READY';
      statusColor = Colors.blue;
      statusIcon = Icons.kitchen;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nextStatus != null) ...[
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 64),
              child: ElevatedButton.icon(
                onPressed: _isUpdating
                    ? null
                    : () => _updateOrderStatus(nextStatus!),
                icon: _isUpdating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(statusIcon, size: 28),
                label: Text(statusLabel,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: statusColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              // Load Order
              if (showLoadOrder) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleLoadOrder(context, doc),
                    icon: const Icon(Icons.open_in_new, size: 28),
                    label: const Text('LOAD ORDER',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              // Print Actions
              _actionIconButton(
                icon: Icons.print,
                tooltip: 'Print KOT',
                onTap: () => PrintingService.printKOT(context, doc),
                size: 60,
              ),
              const SizedBox(width: 12),
              _actionIconButton(
                icon: Icons.receipt_long,
                tooltip: 'Print Invoice',
                onTap: () => PrintingService.printReceipt(context, doc),
                color: Colors.green,
                size: 60,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateOrderStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final updates = <String, dynamic>{
        'status': newStatus,
        'timestamps.$newStatus': FieldValue.serverTimestamp(),
      };
      if (newStatus == AppConstants.statusPreparing) {
        updates['preparingAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance
          .collection(AppConstants.collectionOrders)
          .doc(widget.order.id)
          .update(updates);
    } catch (e) {
      debugPrint('Error updating order: $e');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Widget _actionIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = Colors.blue,
    double size = 48,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size,
            height: size,
            child: Icon(icon, color: color, size: size * 0.5),
          ),
        ),
      ),
    );
  }

  void _handleLoadOrder(BuildContext context, DocumentSnapshot doc) async {
    final pos = Provider.of<PosService>(context, listen: false);
    // 1. Load data into service using the LATEST snapshot from stream
    await pos.loadExistingOrder(doc);
    
    // 2. Switch PosScreen view mode to 'pos'
    widget.onSwitchToPos();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order loaded into cart')),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Delivery Order Grid Card
// ═══════════════════════════════════════════════════════════════════
class _DeliveryOrderGridCard extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final bool isSelected;

  const _DeliveryOrderGridCard({
    required this.orderId,
    required this.data,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final orderNumber = OrderNumberHelper.getDisplayNumber(data, orderId: orderId);
    final customerName = data['customerName']?.toString() ?? 'Customer';
    final totalAmount = (data['totalAmount'] ?? 0).toDouble();
    final tableNum = data['tableNumber']?.toString() ?? data['tableName']?.toString();
    final source = (data['source']?.toString() ?? 'unknown').toLowerCase();
    final status = data['status']?.toString() ?? AppConstants.statusPending;

    return Container(
      padding: const EdgeInsets.all(10), // Reduced padding
      decoration: BoxDecoration(
        color: isSelected ? Colors.deepPurple.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? Colors.deepPurple : Colors.grey.withOpacity(0.12),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.deepPurple.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '#$orderNumber',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              _buildSourceIcon(source),
            ],
          ),
          const SizedBox(height: 6),
          _buildPaymentTag(data['isPaid'] == true),
          const SizedBox(height: 6),
          if (tableNum != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'TABLE $tableNum',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ),
          Text(
            customerName,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            '${AppConstants.currencySymbol}${totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          _buildStatusBadge(status),
        ],
      ),
    );
  }

  Widget _buildSourceIcon(String source) {
    IconData iconData;
    Color color;

    if (source == 'snoonu') {
      iconData = Icons.electric_moped;
      color = const Color(0xFF00C853);
    } else if (source == 'talabat') {
      iconData = Icons.moped;
      color = const Color(0xFFFF6F00);
    } else if (source == 'keta') {
      iconData = Icons.shopping_bag;
      color = Colors.blueAccent;
    } else {
      iconData = Icons.restaurant;
      color = Colors.grey;
    }

    return Icon(iconData, size: 16, color: color);
  }

  Widget _buildStatusBadge(String status) {
    final displayText = AppConstants.getStatusDisplayText(status);
    Color badgeColor;
    switch (status) {
      case AppConstants.statusPending:
        badgeColor = Colors.orange;
        break;
      case AppConstants.statusPreparing:
        badgeColor = Colors.blue;
        break;
      case AppConstants.statusPrepared:
      case 'ready':
        badgeColor = Colors.green;
        break;
      case AppConstants.statusPaid:
      case AppConstants.statusCollected:
        badgeColor = Colors.deepPurple;
        break;
      default:
        badgeColor = Colors.teal;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          displayText,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: badgeColor,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentTag(bool isPaid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPaid ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPaid ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPaid ? Icons.check_circle : Icons.pending_outlined,
            size: 10,
            color: isPaid ? Colors.green : Colors.orange[800],
          ),
          const SizedBox(width: 4),
          Text(
            isPaid ? 'PAID' : 'UNPAID',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isPaid ? Colors.green : Colors.orange[800],
            ),
          ),
        ],
      ),
    );
  }
}
