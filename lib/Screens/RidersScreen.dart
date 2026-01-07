import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Widgets/AccessDeniedWidget.dart';
import '../Widgets/Permissions.dart';
import '../Widgets/ProfessionalErrorWidget.dart';
import '../main.dart';
import 'BranchManagement.dart';
import 'OrdersScreen.dart';
import '../Widgets/BranchFilterService.dart';


class RidersScreen extends StatefulWidget {
  const RidersScreen({super.key});

  @override
  State<RidersScreen> createState() => _RidersScreenState();
}

class _RidersScreenState extends State<RidersScreen> {
  String _filterStatus = 'all';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();

    // --- 1. UI Permission Check ---
    if (!userScope.can(Permissions.canManageRiders)) {
      return const AccessDeniedWidget(
        permission: 'Manage Riders',
      );
    }

    // --- 2. Build Branch-Scoped Query ---
    Query<Map<String, dynamic>> baseQuery =
    FirebaseFirestore.instance.collection('Drivers').orderBy('name');

    // Get branch IDs properly from filter service
    // Note: We need to access branchFilter here. Since it wasn't watched in original code, we should technically check if it's available or use userScope fallback.
    // However, for consistency, we should use BranchFilterService if possible.
    final branchFilter = context.watch<BranchFilterService>();
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    // Always filter by branches - SuperAdmin sees only their assigned branches
    if (filterBranchIds.isNotEmpty) {
       if (filterBranchIds.length == 1) {
         baseQuery = baseQuery.where('branchIds', arrayContains: filterBranchIds.first);
       } else {
         baseQuery = baseQuery.where('branchIds', arrayContainsAny: filterBranchIds);
       }
    } else if (userScope.branchIds.isNotEmpty) {
       // Fall back to user's assigned branches
       if (userScope.branchIds.length == 1) {
          baseQuery = baseQuery.where('branchIds', arrayContains: userScope.branchIds.first);
       } else {
          baseQuery = baseQuery.where('branchIds', arrayContainsAny: userScope.branchIds);
       }
    } else {
      // User with no branches - force empty result
       baseQuery = baseQuery.where(FieldPath.documentId, isEqualTo: 'force_empty_result');
    }

    // Assign query to scope-level variable if needed, or just use in _buildEnhancedDriversList
    // But wait, _buildEnhancedDriversList creates its OWN query. We should update THAT method.
    // And also the build method does perform a query check?
    // Looking at lines 36-47 in original file, it creates a 'query' local variable but it's not actually passed to _buildEnhancedDriversList?
    // Re-reading: The 'query' variable in build() seems UNUSED because _buildEnhancedDriversList creates a NEW query at line 199.
    // I should fix _buildEnhancedDriversList AND remove the redundant query in build() if it confusing.
    // Actually, let's just make sure the 'query' in build is valid for whatever (maybe debugging?).
    // But crucially, I must update _buildEnhancedDriversList.

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Drivers Management',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: () => _showDriverDialog(context, userScope),
              tooltip: 'Add New Driver',
            ),
          ),
        ],
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
                hintText: 'Search drivers by name or email...',
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
          _buildEnhancedStatusFilter(),
          Expanded(
            child: _buildEnhancedDriversList(userScope),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedStatusFilter() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildEnhancedFilterChip('All', 'all', Icons.people_outline, Colors.blue),
            _buildEnhancedFilterChip('Online', 'online', Icons.wifi_outlined, Colors.green),
            _buildEnhancedFilterChip('Offline', 'offline', Icons.wifi_off_outlined, Colors.grey),
            _buildEnhancedFilterChip('Available', 'available', Icons.check_circle_outline, Colors.teal),
            _buildEnhancedFilterChip('Busy', 'busy', Icons.cancel_outlined, Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedFilterChip(String label, String value, IconData icon, Color color) {
    final isSelected = _filterStatus == value;
    return Container(
      margin: const EdgeInsets.only(right: 12, bottom: 16),
      child: FilterChip(
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
        avatar: CircleAvatar(
          radius: 12,
          backgroundColor: isSelected
              ? Colors.white.withOpacity(0.2)
              : color.withOpacity(0.12),
          child: Icon(
            icon,
            size: 14,
            color: isSelected ? Colors.white : color,
          ),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 12,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _filterStatus = selected ? value : 'all';
          });
        },
        selectedColor: color,
        backgroundColor: color.withOpacity(0.1),
        elevation: isSelected ? 4 : 1,
        shadowColor: color.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: BorderSide(
            color: isSelected ? color : color.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildEnhancedDriversList(UserScopeService userScope) {
    final branchFilter = Provider.of<BranchFilterService>(context); // Listen to branch changes
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('Drivers');

    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);

    // Always filter by branches - SuperAdmin sees only their assigned branches
    if (filterBranchIds.isNotEmpty) {
        if (filterBranchIds.length == 1) {
          query = query.where('branchIds', arrayContains: filterBranchIds.first);
        } else {
          query = query.where('branchIds', arrayContainsAny: filterBranchIds);
        }
    } else if (userScope.branchIds.isNotEmpty) {
        // Fall back to user's assigned branches
         if (userScope.branchIds.length == 1) {
          query = query.where('branchIds', arrayContains: userScope.branchIds.first);
        } else {
          query = query.where('branchIds', arrayContainsAny: userScope.branchIds);
        }
    } else {
       // User with no branches - force empty result
        query = query.where(FieldPath.documentId, isEqualTo: 'force_empty_result');
    }

    // Apply status filters
    if (_filterStatus == 'online') {
      query = query.where('status', isEqualTo: 'online');
    } else if (_filterStatus == 'offline') {
      query = query.where('status', isEqualTo: 'offline');
    } else if (_filterStatus == 'available') {
      query = query.where('isAvailable', isEqualTo: true);
    } else if (_filterStatus == 'busy') {
      query = query.where('isAvailable', isEqualTo: false);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        // --- 3. Professional Error Handling ---
        if (snapshot.hasError) {
          debugPrint("RidersScreen Error: ${snapshot.error}");
          return ProfessionalErrorWidget(
            title: 'Could not load drivers',
            message: 'Permission denied or a Firestore index is missing. Please check your console.',
            icon: Icons.delivery_dining,
            onRetry: () => setState(() {}),
          );
        }

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
                  'Loading drivers...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        // Client-side search filtering
        final drivers = snapshot.data!.docs.where((doc) {
          final data = doc.data();
          final name = (data['name'] as String? ?? '').toLowerCase();
          final email = (data['email'] as String? ?? '').toLowerCase();
          return name.contains(_searchQuery) || email.contains(_searchQuery);
        }).toList();

        if (drivers.isEmpty && _searchQuery.isNotEmpty) {
          return _buildEmptyState(isSearch: true);
        }

        if (drivers.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: drivers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final driver = drivers[index];
            return EnhancedDriverCard(
              driver: driver,
              onTap: () => _showDriverDetails(context, driver),
              onEdit: () => _showDriverDialog(context, userScope, driverDoc: driver),
            );
          },
        );
      },
    );
  }

  /// Shows the Add/Edit Driver Dialog.
  void _showDriverDialog(
      BuildContext context,
      UserScopeService userScope, {
        DocumentSnapshot<Map<String, dynamic>>? driverDoc,
      }) {
    showDialog(
      context: context,
      builder: (context) => _DriverDialog(userScope: userScope, driverDoc: driverDoc),
    );
  }

  void _showDriverDetails(BuildContext context, DocumentSnapshot driver) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DriverDetailsBottomSheet(driver: driver),
    );
  }

  Widget _buildEmptyState({bool isSearch = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearch ? Icons.search_off : Icons.person_off_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            isSearch ? 'No Drivers Found' : 'No Drivers Created',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearch
                ? 'Try a different search term.'
                : 'Add your first driver to get started.',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Enhanced Driver Card with all features
class EnhancedDriverCard extends StatefulWidget {
  final DocumentSnapshot driver;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showActions;

  const EnhancedDriverCard({
    Key? key,
    required this.driver,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.showActions = true,
  }) : super(key: key);

  @override
  State<EnhancedDriverCard> createState() => _EnhancedDriverCardState();
}

class _EnhancedDriverCardState extends State<EnhancedDriverCard> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.driver.data() as Map<String, dynamic>;
    final driverInfo = DriverInfo.fromFirestore(data);

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                  spreadRadius: 0,
                ),
              ],
              border: Border.all(
                color: Colors.grey.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onTap ?? () => _showDriverDetails(context),
                onTapDown: (_) => _animationController.forward(),
                onTapUp: (_) => _animationController.reverse(),
                onTapCancel: () => _animationController.reverse(),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildDriverHeader(driverInfo),
                      if (_isExpanded) ...[
                        const SizedBox(height: 16),
                        _buildExpandedContent(driverInfo),
                      ],
                      if (widget.showActions) ...[
                        const SizedBox(height: 16),
                        _buildActionButtons(driverInfo),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriverHeader(DriverInfo driverInfo) {
    return Row(
      children: [
        _buildDriverAvatar(driverInfo),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      driverInfo.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusIndicator(driverInfo.status),
                ],
              ),
              const SizedBox(height: 4),
              _buildDriverSubInfo(driverInfo),
              const SizedBox(height: 8),
              _buildDriverStats(driverInfo),
            ],
          ),
        ),
        _buildExpandButton(),
      ],
    );
  }

  Widget _buildDriverAvatar(DriverInfo driverInfo) {
    return Stack(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _getStatusColor(driverInfo.status).withOpacity(0.3),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: _getStatusColor(driverInfo.status).withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(35),
            child: driverInfo.profileImageUrl.isNotEmpty
                ? FadeInImage.assetNetwork(
              placeholder: 'assets/placeholder_avatar.png',
              image: driverInfo.profileImageUrl,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 300),
              imageErrorBuilder: (context, error, stackTrace) =>
                  _buildDefaultAvatar(),
            )
                : _buildDefaultAvatar(),
          ),
        ),
        Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: driverInfo.isAvailable ? Colors.green : Colors.red,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade300,
            Colors.deepPurple.shade600,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(
        Icons.person_outline_rounded,
        color: Colors.white,
        size: 35,
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getStatusColor(status).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getStatusColor(status),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _getStatusLabel(status),
            style: TextStyle(
              color: _getStatusColor(status),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverSubInfo(DriverInfo driverInfo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (driverInfo.email.isNotEmpty)
          Row(
            children: [
              Icon(
                Icons.email_outlined,
                size: 14,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  driverInfo.email,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(Icons.directions_car_outlined, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${driverInfo.vehicle.type} • ${driverInfo.vehicle.number}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildDriverStats(DriverInfo driverInfo) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _buildStatChip(
          icon: Icons.star_rounded,
          value: driverInfo.rating,
          color: Colors.amber,
          backgroundColor: Colors.amber.withOpacity(0.1),
        ),
        _buildStatChip(
          icon: Icons.local_shipping_outlined,
          value: '${driverInfo.totalDeliveries}',
          color: Colors.blue,
          backgroundColor: Colors.blue.withOpacity(0.1),
        ),
        if (driverInfo.isAvailable)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  'Available',
                  style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String value,
    required Color color,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: AnimatedRotation(
        turns: _isExpanded ? 0.5 : 0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.grey[600],
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(DriverInfo driverInfo) {
    return Column(
      children: [
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildInfoTile(
                icon: Icons.phone_outlined,
                title: 'Phone',
                value: driverInfo.phone,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoTile(
                icon: Icons.location_on_outlined,
                title: 'Location',
                value: _formatLocation(driverInfo.currentLocation),
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (driverInfo.assignedOrderId.isNotEmpty)
          _buildAssignedOrderCard(driverInfo.assignedOrderId),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedOrderCard(String orderId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assigned Order',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '#${orderId.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _viewOrder(orderId),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text(
              'View',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(DriverInfo driverInfo) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.edit_outlined,
            label: 'Edit',
            color: Colors.blue,
            onTap: widget.onEdit ?? () => _editDriver(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            icon: driverInfo.isAvailable
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
            label: driverInfo.isAvailable ? 'Pause' : 'Activate',
            color: driverInfo.isAvailable ? Colors.orange : Colors.green,
            onTap: () => _toggleAvailability(driverInfo),
          ),
        ),
        const SizedBox(width: 12),
        _buildMoreActionsButton(),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreActionsButton() {
    return PopupMenuButton<String>(
      onSelected: (value) => _handleMoreAction(value),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Icon(
          Icons.more_vert_rounded,
          color: Colors.grey[600],
          size: 20,
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'details',
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 12),
              Text('View Details'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'track',
          child: Row(
            children: [
              Icon(Icons.my_location, color: Colors.green),
              SizedBox(width: 12),
              Text('Track Location'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'history',
          child: Row(
            children: [
              Icon(Icons.history, color: Colors.orange),
              SizedBox(width: 12),
              Text('Order History'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red),
              SizedBox(width: 12),
              Text('Delete Driver'),
            ],
          ),
        ),
      ],
    );
  }

  // Helper methods
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.grey;
      case 'on_delivery':
        return Colors.orange;
      case 'busy':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return 'Online';
      case 'offline':
        return 'Offline';
      case 'on_delivery':
        return 'On Delivery';
      case 'busy':
        return 'Busy';
      default:
        return 'Unknown';
    }
  }

  String _formatLocation(GeoPoint? location) {
    if (location == null) return 'Unknown';
    return '${location.latitude.toStringAsFixed(4)}°, ${location.longitude.toStringAsFixed(4)}°';
  }

  // Action handlers
  void _showDriverDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DriverDetailsBottomSheet(driver: widget.driver),
    );
  }

  void _editDriver(BuildContext context) {
    // This will be handled by the parent widget
    if (widget.onEdit != null) {
      widget.onEdit!();
    }
  }

  void _toggleAvailability(DriverInfo driverInfo) async {
    try {
      await FirebaseFirestore.instance
          .collection('Drivers')
          .doc(widget.driver.id)
          .update({
        'isAvailable': !driverInfo.isAvailable,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Driver ${!driverInfo.isAvailable ? 'activated' : 'paused'}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleMoreAction(String action) async {
    switch (action) {
      case 'details':
        _showDriverDetails(context);
        break;
      case 'track':
        final data = widget.driver.data() as Map<String, dynamic>;
        final GeoPoint? loc = data['currentLocation'] as GeoPoint?;
        await _openGoogleMapsFor(loc);
        break;
      case 'history':
        final data = widget.driver.data() as Map<String, dynamic>;
        final driverName = data['name']?.toString() ?? '';
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _DriverOrderHistoryScreen(
              driverId: widget.driver.id,
              driverName: driverName,
            ),
          ),
        );
        break;
      case 'delete':
        final data = widget.driver.data() as Map<String, dynamic>;
        final name = (data['name'] ?? 'Driver') as String;
        final assignedOrderId = (data['assignedOrderId'] ?? '') as String;
        final confirmed = await _confirmDeleteDriver(context, name);
        if (!confirmed) return;

        if (assignedOrderId.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot delete while assigned to an order. Unassign first.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        await _deleteDriverDoc(context);
        break;
    }
  }

  Future<void> _openGoogleMapsFor(GeoPoint? loc) async {
    if (loc == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location unavailable for this driver.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final lat = loc.latitude.toStringAsFixed(6);
    final lng = loc.longitude.toStringAsFixed(6);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Maps.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _confirmDeleteDriver(BuildContext context, String driverName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            const Text('Delete Driver?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$driverName"? This action cannot be undone.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteDriverDoc(BuildContext context) async {
    try {
      await FirebaseFirestore.instance.collection('Drivers').doc(widget.driver.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver deleted successfully.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _viewOrder(String orderId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrdersScreen(),
      ),
    );
  }
}


/// Card to display driver info
class _DriverCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> driverDoc;
  final VoidCallback onTap;

  const _DriverCard({required this.driverDoc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = driverDoc.data();
    if (data == null) return const SizedBox.shrink();

    final name = data['name'] as String? ?? 'No Name';
    final email = data['email'] as String? ?? 'No Email';
    final status = data['status'] as String? ?? 'offline';
    final profileImageUrl = data['profileImageUrl'] as String? ?? '';

    final (statusColor, statusIcon) = _getStatusLook(status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 25,
          backgroundImage:
          profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null,
          child: profileImageUrl.isEmpty
              ? const Icon(Icons.person)
              : null,
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(email),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 16),
              const SizedBox(width: 4),
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, IconData) _getStatusLook(String status) {
    switch (status) {
      case 'online':
        return (Colors.green, Icons.wifi);
      case 'offline':
        return (Colors.grey, Icons.wifi_off);
      case 'on_delivery':
        return (Colors.blue, Icons.delivery_dining);
      default:
        return (Colors.orange, Icons.help);
    }
  }
}

/// Add/Edit Driver Dialog
/// Add/Edit Driver Dialog
class _DriverDialog extends StatefulWidget {
  final UserScopeService userScope;
  final DocumentSnapshot<Map<String, dynamic>>? driverDoc;

  const _DriverDialog({required this.userScope, this.driverDoc});

  @override
  State<_DriverDialog> createState() => _DriverDialogState();
}

class _DriverDialogState extends State<_DriverDialog> {
  final _formKey = GlobalKey<FormState>();
  late bool _isEdit;
  bool _isLoading = false;

  // Form Controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _profileImgCtrl;
  late TextEditingController _vehicleTypeCtrl;
  late TextEditingController _vehicleNumCtrl;
  String _status = 'offline';
  bool _isAvailable = false;
  List<String> _selectedBranchIds = [];

  @override
  void initState() {
    super.initState();
    _isEdit = widget.driverDoc != null;
    final data = widget.driverDoc?.data();

    _nameCtrl = TextEditingController(text: data?['name'] ?? '');
    _emailCtrl = TextEditingController(text: data?['email'] ?? '');
    _phoneCtrl = TextEditingController(text: data?['phone'] ?? '');
    _profileImgCtrl = TextEditingController(text: data?['profileImageUrl'] ?? '');
    _status = data?['status'] ?? 'offline';
    _isAvailable = data?['isAvailable'] ?? false;
    _selectedBranchIds = List<String>.from(data?['branchIds'] ?? []);

    final vehicle = data?['vehicle'] as Map<String, dynamic>? ?? {};
    _vehicleTypeCtrl = TextEditingController(text: vehicle['type'] ?? 'Motorcycle');
    _vehicleNumCtrl = TextEditingController(text: vehicle['number'] ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _profileImgCtrl.dispose();
    _vehicleTypeCtrl.dispose();
    _vehicleNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;

    setState(() => _isLoading = true);

    // If not super_admin, force branchIds to be their own
    if (!widget.userScope.isSuperAdmin) {
      _selectedBranchIds = widget.userScope.branchIds;
    }

    if (_selectedBranchIds.isEmpty && !widget.userScope.isSuperAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: You are not assigned to any branch.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final driverData = {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'profileImageUrl': _profileImgCtrl.text.trim(),
        'status': _status,
        'isAvailable': _isAvailable,
        'branchIds': _selectedBranchIds,
        'vehicle': {
          'type': _vehicleTypeCtrl.text.trim(),
          'number': _vehicleNumCtrl.text.trim(),
        },
        // Fields not editable here but preserved/set on create
        'assignedOrderId': _isEdit ? widget.driverDoc!.data()!['assignedOrderId'] ?? '' : '',
        'fcmToken': _isEdit ? widget.driverDoc!.data()!['fcmToken'] ?? '' : '',
        'rating': _isEdit ? widget.driverDoc!.data()!['rating'] ?? '0' : '0',
        'totalDeliveries': _isEdit ? widget.driverDoc!.data()!['totalDeliveries'] ?? 0 : 0,
        'currentLocation': _isEdit ? widget.driverDoc!.data()!['currentLocation'] ?? const GeoPoint(0,0) : const GeoPoint(0,0),
      };

      if (_isEdit) {
        // Update existing driver
        await widget.driverDoc!.reference.update(driverData);
      } else {
        // Create new driver (use email as ID)
        final docId = _emailCtrl.text.trim();
        if (docId.isEmpty) {
          throw Exception('Email is required to create a new driver.');
        }
        await FirebaseFirestore.instance
            .collection('Drivers')
            .doc(docId)
            .set(driverData);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Driver ${_isEdit ? 'updated' : 'added'} successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving driver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Driver' : 'Add Driver'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v!.isEmpty ? 'Name is required' : null,
              ),
              TextFormField(
                controller: _emailCtrl,
                enabled: !_isEdit, // Email is the ID, cannot be edited
                decoration: const InputDecoration(labelText: 'Email (ID)'),
                validator: (v) => v!.isEmpty ? 'Email is required' : null,
              ),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              TextFormField(
                controller: _vehicleTypeCtrl,
                decoration: const InputDecoration(labelText: 'Vehicle Type'),
              ),
              TextFormField(
                controller: _vehicleNumCtrl,
                decoration: const InputDecoration(labelText: 'Vehicle Number'),
              ),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: ['online', 'offline', 'on_delivery']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _status = v!),
              ),
              SwitchListTile(
                title: const Text('Is Available'),
                value: _isAvailable,
                onChanged: (v) => setState(() => _isAvailable = v),
              ),
              TextFormField(
                controller: _profileImgCtrl,
                decoration: const InputDecoration(labelText: 'Profile Image URL'),
              ),

              // Use your existing MultiBranchSelector component
              if (widget.userScope.isSuperAdmin) ...[
                const SizedBox(height: 16),
                MultiBranchSelector(
                  selectedIds: _selectedBranchIds,
                  onChanged: (selected) {
                    setState(() {
                      _selectedBranchIds = selected;
                    });
                  },
                ),
              ] else ...[
                // Show read-only branch info for non-super admins
                ListTile(
                  leading: const Icon(Icons.business_sharp, color: Colors.indigo),
                  title: const Text('Assigned Branch'),
                  subtitle: Text(
                    widget.userScope.branchIds.isEmpty
                        ? 'No branch assigned'
                        : '${widget.userScope.branchIds.length} branch(es)',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _onSave,
          child: _isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : Text(_isEdit ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}
/// A multi-select chip field for branches.



/// Bottom Sheet for detailed driver information
/// Bottom Sheet for detailed driver information
class _DriverDetailsBottomSheet extends StatelessWidget {
  final DocumentSnapshot driver;

  const _DriverDetailsBottomSheet({required this.driver});

  @override
  Widget build(BuildContext context) {
    final data = driver.data() as Map<String, dynamic>;
    final driverInfo = DriverInfo.fromFirestore(data);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: driverInfo.profileImageUrl.isNotEmpty
                        ? FadeInImage.assetNetwork(
                      placeholder: 'assets/placeholder_avatar.png',
                      image: driverInfo.profileImageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 300),
                      imageErrorBuilder: (context, error, stackTrace) =>
                          _buildDefaultAvatar(),
                    )
                        : _buildDefaultAvatar(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverInfo.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        driverInfo.email,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _buildStatusBadge(driverInfo),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contact Information
                  _buildSectionHeader('Contact Information'),
                  _buildContactInfo(driverInfo),

                  // Vehicle Information
                  _buildSectionHeader('Vehicle Information'),
                  _buildVehicleInfo(driverInfo),

                  // Statistics
                  _buildSectionHeader('Statistics'),
                  _buildStatistics(driverInfo),

                  // Current Assignment
                  if (driverInfo.assignedOrderId.isNotEmpty) ...[
                    _buildSectionHeader('Current Assignment'),
                    _buildCurrentAssignment(context, driverInfo),
                  ],

                  // Location
                  _buildSectionHeader('Location'),
                  _buildLocationInfo(context, driverInfo),

                  // Quick Actions
                  _buildSectionHeader('Quick Actions'),
                  _buildQuickActions(context, driverInfo),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.white70,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.person_outline_rounded,
        color: Colors.deepPurple.shade300,
        size: 30,
      ),
    );
  }

  Widget _buildStatusBadge(DriverInfo driverInfo) {
    final statusColor = _getStatusColor(driverInfo.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _getStatusLabel(driverInfo.status),
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          if (driverInfo.isAvailable) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Available',
              style: TextStyle(
                color: Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple,
        ),
      ),
    );
  }

  Widget _buildContactInfo(DriverInfo driverInfo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'Phone',
            value: driverInfo.phone.isNotEmpty ? driverInfo.phone : 'Not provided',
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Email',
            value: driverInfo.email,
            color: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfo(DriverInfo driverInfo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.directions_car_rounded,
            label: 'Vehicle Type',
            value: driverInfo.vehicle.type,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.confirmation_number_rounded,
            label: 'Vehicle Number',
            value: driverInfo.vehicle.number,
            color: Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics(DriverInfo driverInfo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            value: driverInfo.rating,
            label: 'Rating',
            icon: Icons.star_rounded,
            color: Colors.amber,
          ),
          _buildStatItem(
            value: driverInfo.totalDeliveries.toString(),
            label: 'Deliveries',
            icon: Icons.local_shipping_rounded,
            color: Colors.blue,
          ),
          _buildStatItem(
            value: driverInfo.isAvailable ? 'Yes' : 'No',
            label: 'Available',
            icon: Icons.check_circle_rounded,
            color: driverInfo.isAvailable ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentAssignment(BuildContext context, DriverInfo driverInfo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.assignment_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Currently Assigned Order',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Order #${driverInfo.assignedOrderId.substring(0, 8).toUpperCase()}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _viewOrder(context, driverInfo.assignedOrderId),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'View Order Details',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInfo(BuildContext context, DriverInfo driverInfo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(
            icon: Icons.location_on_rounded,
            label: 'Current Location',
            value: _formatLocation(driverInfo.currentLocation),
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openMaps(context, driverInfo.currentLocation),
              icon: const Icon(Icons.map_rounded),
              label: const Text('Open in Maps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                side: BorderSide(color: Colors.deepPurple.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, DriverInfo driverInfo) {
    return Row(
      children: [
        Expanded(
          child: _buildQuickActionButton(
            icon: Icons.history_rounded,
            label: 'Order History',
            color: Colors.blue,
            onTap: () => _viewOrderHistory(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickActionButton(
            icon: Icons.edit_rounded,
            label: 'Edit Driver',
            color: Colors.green,
            onTap: () => _editDriver(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickActionButton(
            icon: driverInfo.isAvailable ? Icons.pause_rounded : Icons.play_arrow_rounded,
            label: driverInfo.isAvailable ? 'Pause' : 'Activate',
            color: driverInfo.isAvailable ? Colors.orange : Colors.green,
            onTap: () => _toggleAvailability(context, driverInfo),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper methods
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.grey;
      case 'on_delivery':
        return Colors.orange;
      case 'busy':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return 'Online';
      case 'offline':
        return 'Offline';
      case 'on_delivery':
        return 'On Delivery';
      case 'busy':
        return 'Busy';
      default:
        return 'Unknown';
    }
  }

  String _formatLocation(GeoPoint? location) {
    if (location == null) return 'Location not available';
    return '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
  }

  // Action methods
  void _viewOrder(BuildContext context, String orderId) {
    Navigator.of(context)
      ..pop()
      ..push(
        MaterialPageRoute(
          builder: (_) => OrdersScreen(),
        ),
      );
  }

  void _viewOrderHistory(BuildContext context) {
    final data = driver.data() as Map<String, dynamic>;
    final driverName = data['name']?.toString() ?? '';

    Navigator.of(context)
      ..pop()
      ..push(
        MaterialPageRoute(
          builder: (_) => _DriverOrderHistoryScreen(
            driverId: driver.id,
            driverName: driverName,
          ),
        ),
      );
  }

  void _editDriver(BuildContext context) {
    // This would typically open the edit dialog
    // For now, just close the bottom sheet
    Navigator.of(context).pop();
    // You might want to trigger the edit dialog here
  }

  Future<void> _toggleAvailability(BuildContext context, DriverInfo driverInfo) async {
    try {
      await FirebaseFirestore.instance
          .collection('Drivers')
          .doc(driver.id)
          .update({
        'isAvailable': !driverInfo.isAvailable,
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Driver ${!driverInfo.isAvailable ? 'activated' : 'paused'}',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Close the bottom sheet
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openMaps(BuildContext context, GeoPoint? location) async {
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location unavailable for this driver.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final lat = location.latitude.toStringAsFixed(6);
    final lng = location.longitude.toStringAsFixed(6);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Maps.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Screen to display driver's order history
class _DriverOrderHistoryScreen extends StatefulWidget {
  final String driverId;
  final String driverName;

  const _DriverOrderHistoryScreen({
    required this.driverId,
    required this.driverName,
  });

  @override
  State<_DriverOrderHistoryScreen> createState() => _DriverOrderHistoryScreenState();
}

class _DriverOrderHistoryScreenState extends State<_DriverOrderHistoryScreen> {
  String _filterStatus = 'all';
  // ✅ Updated Statuses to match real data
  final List<String> _statusFilters = ['all', 'delivered', 'cancelled'];

  // ✅ Pagination State
  final int _ordersPerPage = 6;
  List<DocumentSnapshot> _orders = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Query query = FirebaseFirestore.instance.collection('Orders');

      // ✅ FIX 1: Use 'riderId' instead of 'driverId'
      query = query.where('riderId', isEqualTo: widget.driverId);

      // ✅ FIX 2: Use 'timestamp' instead of 'createdAt'
      query = query.orderBy('timestamp', descending: true);

      // Filter
      if (_filterStatus != 'all') {
        query = query.where('status', isEqualTo: _filterStatus);
      }

      // ✅ Pagination Logic
      query = query.limit(_ordersPerPage);
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      setState(() {
        if (snapshot.docs.isNotEmpty) {
          _orders.addAll(snapshot.docs);
          _lastDocument = snapshot.docs.last;
        }

        // If fewer docs than limit, we reached the end
        if (snapshot.docs.length < _ordersPerPage) {
          _hasMore = false;
        }
      });
    } catch (e) {
      debugPrint("Error fetching history: $e");
      setState(() => _errorMessage = "Could not load orders. Check indexes.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onFilterChanged(String selected) {
    if (_filterStatus == selected) return;
    setState(() {
      _filterStatus = selected;
      _orders.clear();
      _lastDocument = null;
      _hasMore = true;
    });
    _fetchOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order History',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 20),
            ),
            Text(
              widget.driverName,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.deepPurple),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _buildStatusFilter(),
          const SizedBox(height: 8),
          Expanded(child: _buildOrderList()),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statusFilters.map((status) {
            final isSelected = _filterStatus == status;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(status.toUpperCase()),
                selected: isSelected,
                onSelected: (val) => _onFilterChanged(val ? status : 'all'),
                selectedColor: Colors.deepPurple,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                backgroundColor: Colors.deepPurple.withOpacity(0.1),
                checkmarkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildOrderList() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 10),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: () {
                setState(() {
                  _orders.clear();
                  _lastDocument = null;
                  _hasMore = true;
                });
                _fetchOrders();
              },
              child: const Text("Retry"),
            )
          ],
        ),
      );
    }

    if (_orders.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_orders.isEmpty && !_isLoading) {
      return const Center(
        child: Text("No orders found.", style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length + 1, // +1 for Loader/End message
      itemBuilder: (context, index) {
        if (index == _orders.length) {
          // Bottom Item
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: ElevatedButton(
                  onPressed: _fetchOrders,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Load More (6 Orders)"),
                ),
              ),
            );
          } else {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text("No more orders", style: TextStyle(color: Colors.grey))),
            );
          }
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _OrderHistoryCard(order: _orders[index]),
        );
      },
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  final DocumentSnapshot order;

  const _OrderHistoryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final data = order.data() as Map<String, dynamic>? ?? {};
    final orderId = order.id;
    final status = data['status']?.toString() ?? 'unknown';
    final timestamp = data['timestamp'] as Timestamp?;
    final totalAmount = double.tryParse(data['totalAmount']?.toString() ?? '0') ?? 0.0;

    // ✅ Fix Delivery Address Crash (Handle Map vs String)
    String address = 'No address';
    final addrRaw = data['deliveryAddress'];
    if (addrRaw is String) {
      address = addrRaw;
    } else if (addrRaw is Map) {
      address = addrRaw['street']?.toString() ?? 'No address';
    }

    final dateStr = timestamp != null
        ? "${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}"
        : "N/A";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Order #${orderId.substring(0, 6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(status.toUpperCase(), style: TextStyle(color: _getStatusColor(status), fontSize: 10, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text('📅 $dateStr', style: const TextStyle(fontSize: 12)),
            Text('📍 $address', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text('QAR ${totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'delivered') return Colors.green;
    if (status == 'cancelled') return Colors.red;
    return Colors.grey;
  }
}


class DriverInfo {
  final String name;
  final String email;
  final String phone;
  final String profileImageUrl;
  final bool isAvailable;
  final String status;
  final String rating;
  final int totalDeliveries;
  final Vehicle vehicle;
  final GeoPoint? currentLocation;
  final String assignedOrderId;

  DriverInfo({
    required this.name,
    required this.email,
    required this.phone,
    required this.profileImageUrl,
    required this.isAvailable,
    required this.status,
    required this.rating,
    required this.totalDeliveries,
    required this.vehicle,
    this.currentLocation,
    required this.assignedOrderId,
  });

  factory DriverInfo.fromFirestore(Map<String, dynamic> data) {
    final vehicleData = (data['vehicle'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    String phoneStr;
    final dynamic rawPhone = data['phone'];
    if (rawPhone == null) {
      phoneStr = 'N/A';
    } else if (rawPhone is num) {
      phoneStr = rawPhone.toString();
    } else {
      phoneStr = rawPhone.toString();
    }

    return DriverInfo(
      name: (data['name'] ?? 'Unknown Driver').toString(),
      email: (data['email'] ?? '').toString(),
      phone: phoneStr,
      profileImageUrl: (data['profileImageUrl'] ?? '').toString(),
      isAvailable: (data['isAvailable'] ?? false) == true,
      status: (data['status'] ?? 'offline').toString(),
      rating: (data['rating'] ?? '0').toString(),
      totalDeliveries: (data['totalDeliveries'] as num?)?.toInt() ?? 0,
      vehicle: Vehicle.fromMap(vehicleData),
      currentLocation: data['currentLocation'] as GeoPoint?,
      assignedOrderId: (data['assignedOrderId'] ?? '').toString(),
    );
  }
}

class Vehicle {
  final String type;
  final String number;

  Vehicle({required this.type, required this.number});

  factory Vehicle.fromMap(Map<String, dynamic> data) {
    return Vehicle(
      type: data['type'] ?? 'Unknown',
      number: data['number'] ?? 'N/A',
    );
  }
}