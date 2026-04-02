import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/Permissions.dart';
import '../main.dart';

// -----------------------------------------------------------------------------
// STAFF MANAGEMENT SCREEN
// Extracted from SettingsScreen.dart
// -----------------------------------------------------------------------------

import '../utils/responsive_helper.dart';
import 'staff_management_screen_large.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stable stream references
  Stream<QuerySnapshot>? _staffStream;
  Stream<DocumentSnapshot>? _myProfileStream;

  List<String>? _lastFilterBranchIds;
  String? _lastSelectedBranchId;
  String? _lastMyEmail;

  void _updateStreams(UserScopeService userScope, BranchFilterService branchFilter) {
    final filterBranchIds = branchFilter.getFilterBranchIds(userScope.branchIds);
    
    final bool branchIdsChanged = _lastFilterBranchIds == null || 
        _lastFilterBranchIds!.length != filterBranchIds.length ||
        !_lastFilterBranchIds!.every((id) => filterBranchIds.contains(id));
    
    final bool selectionChanged = _lastSelectedBranchId != branchFilter.selectedBranchId;
    final bool emailChanged = _lastMyEmail != userScope.userEmail;

    if (branchIdsChanged || selectionChanged) {
      _staffStream = _getStaffQuery(userScope, branchFilter);
      _lastFilterBranchIds = List.from(filterBranchIds);
      _lastSelectedBranchId = branchFilter.selectedBranchId;
    }

    if (emailChanged && userScope.userEmail != null) {
      _myProfileStream = _db.collection('staff').doc(userScope.userEmail).snapshots();
      _lastMyEmail = userScope.userEmail;
    }
  }

  // Track if we had permission initially (to avoid flash during scope reload)
  bool? _hadPermissionOnInit;

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();

    // Cache the initial permission state
    if (_hadPermissionOnInit == null && userScope.isLoaded) {
      _hadPermissionOnInit =
          userScope.isSuperAdmin && userScope.can(Permissions.canManageStaff);
    }

    // Show loading indicator while scope is loading/reloading
    // This prevents flashing "Access Denied" during state transitions
    if (!userScope.isLoaded) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.deepPurple),
          title: const Text(
            'Manage Staff',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
              fontSize: 24,
            ),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.deepPurple),
              SizedBox(height: 16),
              Text('Loading...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    // Only show Access Denied if we genuinely don't have permission
    // and it's not just a transitional state
    if (!userScope.isSuperAdmin || !userScope.can(Permissions.canManageStaff)) {
      // If we had permission before and now don't, it might be a reload flash
      // Give it a moment - show loading briefly
      if (_hadPermissionOnInit == true) {
        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.deepPurple),
            title: const Text(
              'Manage Staff',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
                fontSize: 24,
              ),
            ),
          ),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.deepPurple),
                SizedBox(height: 16),
                Text('Refreshing...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('❌ You do not have permission to manage staff.'),
        ),
      );
    }

    // Update cached permission state
    _updateStreams(userScope, branchFilter);

    return ResponsiveLayout(
      mobile: _buildMobileLayout(context, userScope, branchFilter),
      desktop: const StaffManagementScreenLarge(),
    );
  }

  Widget _buildMobileLayout(BuildContext context, UserScopeService userScope, BranchFilterService branchFilter) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: !(userScope.branchIds.length > 1), // Center if no selector
        iconTheme: const IconThemeData(color: Colors.deepPurple),
        title: const Text(
          'Manage Staff',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
        actions: [
          // Branch selector removed in favor of global BranchFilterService
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Add New Staff',
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.deepPurple),
              ),
              onPressed: () => _showAddStaffDialog(userScope.userEmail),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _staffStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final staffMembers = snapshot.data?.docs ?? [];

          return CustomScrollView(
            slivers: [
              // 1. My Profile Section (Always Visible)
              SliverToBoxAdapter(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _myProfileStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.exists)
                      return const SizedBox.shrink();
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: _StaffCard(
                        staffId: userScope.userEmail!,
                        data: data,
                        isSelf: true,
                        onEdit: () => _showEditStaffDialog(
                            userScope.userEmail!, data, true),
                      ),
                    );
                  },
                ),
              ),

              // 2. Staff List (Filtered)
              if (staffMembers.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No staff members found matching filter',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final staff = staffMembers[index];
                      // Skip self because it's shown at top
                      if (staff.id == userScope.userEmail)
                        return const SizedBox.shrink();

                      final data = staff.data() as Map<String, dynamic>;
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            child: _StaffCard(
                              staffId: staff.id,
                              data: data,
                              isSelf: false,
                              onEdit: () =>
                                  _showEditStaffDialog(staff.id, data, false),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: staffMembers.length,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showAddStaffDialog(String currentUserEmail) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _StaffEditDialog(
        isEditing: false,
        isSelf: false,
        onSave: (staffData) => _addStaffMember(staffData),
      ),
    );
  }

  void _showEditStaffDialog(
      String staffId, Map<String, dynamic> currentData, bool isSelf) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _StaffEditDialog(
        isEditing: true,
        isSelf: isSelf,
        currentData: currentData,
        onSave: (staffData) => _updateStaffMember(staffId, staffData),
      ),
    );
  }

  Future<void> _addStaffMember(Map<String, dynamic> staffData) async {
    final String email = staffData['email'];

    try {
      final docRef = _db.collection('staff').doc(email);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        if (mounted) {
          _showSnackBar('❌ User with email $email already exists.',
              isError: true);
        }
        return;
      }

      // ✅ IMPROVED: Clean staff document structure
      await docRef.set({
        // Core user info
        'name': staffData['name'],
        'email': email,
        'phone': staffData['phone'] ?? '',
        'role': staffData['role'],
        'qid': staffData['qid'] ?? '',
        'passportNumber': staffData['passportNumber'] ?? '',
        'salary': staffData['salary'] ?? 0,
        'roleFields': staffData['roleFields'] ?? {},
        'isActive': true,

        // Branch assignments
        'branchIds': staffData['branchIds'] ?? [],

        // Permissions
        'permissions': staffData['permissions'] ?? {},

        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': context.read<UserScopeService>().userEmail,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnackBar('✅ Staff member "$email" added successfully');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error adding staff: $e', isError: true);
      }
    }
  }

  Future<void> _updateStaffMember(
      String staffId, Map<String, dynamic> staffData) async {
    try {
      final userScope = context.read<UserScopeService>();

      // ✅ IMPROVED: Explicitly update only allowed fields, add audit metadata
      await _db.collection('staff').doc(staffId).update({
        'name': staffData['name'],
        'phone': staffData['phone'] ?? '',
        'role': staffData['role'],
        'qid': staffData['qid'] ?? '',
        'passportNumber': staffData['passportNumber'] ?? '',
        'salary': staffData['salary'] ?? 0,
        'roleFields': staffData['roleFields'] ?? {},
        'isActive': staffData['isActive'],
        'branchIds': staffData['branchIds'] ?? [],
        'permissions': staffData['permissions'] ?? {},
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastUpdatedBy': userScope.userEmail,
      });

      if (mounted) {
        _showSnackBar('✅ Staff member "$staffId" updated successfully');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error updating staff: $e', isError: true);
      }
    }
  }

  // ✅ Query definition
  Stream<QuerySnapshot> _getStaffQuery(
      UserScopeService userScope, BranchFilterService branchFilter) {
    Query query = _db.collection('staff');

    // Always filter by branches - SuperAdmin sees only their assigned branches
    final filterBranchIds =
        branchFilter.getFilterBranchIds(userScope.branchIds);
    debugPrint(
        "DEBUG: _getStaffQuery called. FilterBranchIds: $filterBranchIds");

    // SuperAdmin with 'All Branches' selected OR too many branches to filter
    if (userScope.isSuperAdmin && (branchFilter.selectedBranchId == null || filterBranchIds.length > 10)) {
       debugPrint("DEBUG: SuperAdmin global view - no branch filter applied");
    } else if (filterBranchIds.isNotEmpty) {
      if (filterBranchIds.length == 1) {
        debugPrint(
            "DEBUG: Using arrayContains for single branch: ${filterBranchIds.first}");
        query = query.where('branchIds', arrayContains: filterBranchIds.first);
      } else {
        debugPrint("DEBUG: Using arrayContainsAny for: $filterBranchIds");
        query = query.where('branchIds', arrayContainsAny: filterBranchIds.take(10).toList());
      }
    } else if (userScope.branchIds.isNotEmpty) {
      // Fall back to user's assigned branches
      if (userScope.branchIds.length == 1) {
        query =
            query.where('branchIds', arrayContains: userScope.branchIds.first);
      } else {
        query = query.where('branchIds', arrayContainsAny: userScope.branchIds.take(10).toList());
      }
    } else {
      // User with no branches - return impossible query (empty result)
      query =
          query.where(FieldPath.documentId, isEqualTo: 'force_empty_result');
    }

    return query.snapshots();
  }


  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final String staffId;
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final bool isSelf;

  const _StaffCard({
    required this.staffId,
    required this.data,
    required this.onEdit,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    final String name = data['name'] ?? 'No Name';
    final String email = data['email'] ?? staffId;
    final String role = data['role'] ?? 'No Role';
    final bool isActive = data['isActive'] ?? false;
    final List<dynamic> branchIds = data['branchIds'] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isSelf ? Colors.deepPurple.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isSelf
            ? Border.all(color: Colors.deepPurple.withOpacity(0.3))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isSelf ? Colors.deepPurple : Colors.grey[300],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: isSelf ? Colors.white : Colors.grey[700],
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelf)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.edit_outlined, color: Colors.deepPurple),
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatusBadge(
                    label: _formatRole(role),
                    color: Colors.blue,
                    icon: Icons.security,
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(
                    label: isActive ? 'Active' : 'Inactive',
                    color: isActive ? Colors.green : Colors.red,
                    icon: isActive ? Icons.check_circle : Icons.cancel,
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(
                    label: '${branchIds.length} Branches',
                    color: Colors.orange,
                    icon: Icons.store,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRole(String role) {
    final normalized = role.toLowerCase().replaceAll('_', '');
    if (normalized == 'superadmin') return 'Super Admin';
    if (normalized == 'branchadmin') return 'Branch Admin';
    if (normalized == 'superadmin') return 'Super Admin';
    if (normalized == 'branchadmin') return 'Branch Admin';
    if (normalized == 'server') return 'Server';
    return role.toUpperCase();
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusBadge(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StaffEditDialog extends StatefulWidget {
  final bool isEditing;
  final bool isSelf;
  final Map<String, dynamic>? currentData;
  final Function(Map<String, dynamic>) onSave;

  const _StaffEditDialog({
    required this.isEditing,
    required this.isSelf,
    this.currentData,
    required this.onSave,
  });

  @override
  State<_StaffEditDialog> createState() => _StaffEditDialogState();
}

class _StaffEditDialogState extends State<_StaffEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _qidController = TextEditingController();
  final _passportController = TextEditingController();
  final _salaryController = TextEditingController();
  // Driver-specific controllers
  final _licenseController = TextEditingController();
  final _vehiclePlateController = TextEditingController();
  String _vehicleType = 'car';

  String _selectedRole = 'branch_admin';
  bool _isActive = true;
  List<String> _selectedBranches = [];
  late Stream<QuerySnapshot> _branchStream;

  // Email validation regex
  static final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  final Map<String, bool> _permissions = {
    'canViewDashboard': true,
    'canManageOrders': true,
    'canManageInventory': false,
    'canManageRiders': false,
    'canManageSettings': false,
    'canManageStaff': false,
    'canManageCoupons': false,
  };

  @override
  void initState() {
    super.initState();
    _branchStream = FirebaseFirestore.instance.collection('Branch').snapshots();
    if (widget.isEditing && widget.currentData != null) {
      _nameController.text = widget.currentData!['name'] ?? '';
      _emailController.text = widget.currentData!['email'] ?? '';
      _phoneController.text = widget.currentData!['phone'] ?? '';
      _qidController.text = widget.currentData!['qid'] ?? '';
      _passportController.text = widget.currentData!['passportNumber'] ?? '';
      final sal = widget.currentData!['salary'];
      _salaryController.text = (sal != null && sal != 0) ? sal.toString() : '';

      String rawRole = widget.currentData!['role'] ?? 'branch_admin';
      if (rawRole == 'superadmin') rawRole = 'super_admin';
      if (rawRole == 'branchadmin') rawRole = 'branch_admin';
      _selectedRole = rawRole;

      _isActive = widget.currentData!['isActive'] ?? true;
      _selectedBranches =
          List<String>.from(widget.currentData!['branchIds'] ?? []);

      // Load role-specific fields
      final rf = widget.currentData!['roleFields'] as Map<String, dynamic>? ?? {};
      if (_selectedRole == 'driver') {
        _licenseController.text = rf['licenseNumber'] ?? '';
        _vehicleType = rf['vehicleType'] ?? 'car';
        _vehiclePlateController.text = rf['vehiclePlateNumber'] ?? '';
      }

      final existingPerms =
          widget.currentData!['permissions'] as Map<String, dynamic>? ?? {};
      _permissions.forEach((key, _) {
        if (existingPerms.containsKey(key)) {
          _permissions[key] = existingPerms[key];
        }
      });
    }

    // Set default permissions based on role if creating new user
    if (!widget.isEditing) {
      _updatePermissionsForRole(_selectedRole);
    }
  }

  void _updatePermissionsForRole(String role) {
    setState(() {
      _selectedRole = role;
      if (role == 'super_admin') {
        _permissions.updateAll((key, value) => true);
      } else if (role == 'branch_admin') {
        _permissions.updateAll((key, value) => true);
        _permissions['canManageSettings'] =
            false; // Branch admin can't change global settings
      } else if (role == 'manager') {
        _permissions['canViewDashboard'] = true;
        _permissions['canManageOrders'] = true;
        _permissions['canManageInventory'] = true;
        _permissions['canManageRiders'] = true;
        _permissions['canManageSettings'] = false;
        _permissions['canManageStaff'] = false;
        _permissions['canManageCoupons'] = false;
      } else {
        // Driver or other roles - reset to basic
        _permissions.updateAll((key, value) => false);
        _permissions['canViewDashboard'] = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.isEditing ? 'Edit Staff Member' : 'Add New Staff'),
      content: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 600), // Limit height
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info Section
                _buildSectionHeader('Basic Information', Icons.person),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nameController,
                        decoration:
                            _buildInputDecoration('Full Name', Icons.badge),
                        validator: (v) =>
                            v!.isEmpty ? 'Name is required' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _emailController,
                        decoration:
                            _buildInputDecoration('Email Address', Icons.email),
                        enabled: !widget.isEditing, // Cannot change email
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Email is required';
                          if (!_emailRegex.hasMatch(v))
                            return 'Invalid email format';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration:
                      _buildInputDecoration('Phone Number', Icons.phone),
                  validator: (v) =>
                      v!.isEmpty ? 'Phone number is required' : null,
                  keyboardType: TextInputType.phone,
                ),

                const SizedBox(height: 24),
                _buildSectionHeader('Identity & Compensation', Icons.credit_card),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qidController,
                        decoration:
                            _buildInputDecoration('QID', Icons.credit_card),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _passportController,
                        decoration:
                            _buildInputDecoration('Passport Number', Icons.book),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _salaryController,
                  decoration:
                      _buildInputDecoration('Salary (QAR)', Icons.payments),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),

                const SizedBox(height: 24),
                _buildSectionHeader('Role & Access', Icons.security),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: _buildInputDecoration('Role', Icons.work),
                  items: const [
                    DropdownMenuItem(
                        value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(
                        value: 'branch_admin', child: Text('Branch Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'server', child: Text('Server')),
                    DropdownMenuItem(value: 'driver', child: Text('Driver')),
                  ],
                  onChanged: (widget.isSelf) // Cannot change own role?
                      ? null
                      : (val) {
                          if (val != null) _updatePermissionsForRole(val);
                        },
                ),

                // --- Driver-specific fields ---
                if (_selectedRole == 'driver') ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('Driver Details', Icons.directions_car),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _licenseController,
                          decoration: _buildInputDecoration('License Number', Icons.directions_car),
                          validator: (v) => v!.isEmpty ? 'Required for drivers' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _vehicleType,
                          decoration: _buildInputDecoration('Vehicle Type', Icons.local_shipping),
                          items: const [
                            DropdownMenuItem(value: 'car', child: Text('Car')),
                            DropdownMenuItem(value: 'bike', child: Text('Bike')),
                            DropdownMenuItem(value: 'van', child: Text('Van')),
                          ],
                          onChanged: (v) => setState(() => _vehicleType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _vehiclePlateController,
                    decoration: _buildInputDecoration('Vehicle Plate Number', Icons.confirmation_number),
                    validator: (v) => v!.isEmpty ? 'Required for drivers' : null,
                  ),
                ],
                if (!widget.isSelf) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Active Account'),
                    subtitle: const Text('Allow this user to sign in'),
                    value: _isActive,
                    activeColor: Colors.deepPurple,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _isActive = val),
                  ),
                ],

                const SizedBox(height: 24),
                _buildSectionHeader('Branch Assignment', Icons.store),
                const SizedBox(height: 8),
                const Text('Select branches this user can access:',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 8),

                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _branchStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final branches = snapshot.data!.docs;

                      return ListView(
                        shrinkWrap: true,
                        children: branches.map((doc) {
                          final name = doc['name'];
                          final id = doc.id;
                          final isSelected = _selectedBranches.contains(id);

                          return CheckboxListTile(
                            title: Text(name),
                            value: isSelected,
                            activeColor: Colors.deepPurple,
                            dense: true,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedBranches.add(id);
                                } else {
                                  _selectedBranches.remove(id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),

                // Permissions Section (Collapsible or just visible)
                const SizedBox(height: 24),
                ExpansionTile(
                  title: const Row(
                    children: [
                      Icon(Icons.lock_person,
                          color: Colors.deepPurple, size: 20),
                      SizedBox(width: 8),
                      Text('Fine-grained Permissions',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.deepPurple)),
                    ],
                  ),
                  children: _permissions.keys.map((key) {
                    return CheckboxListTile(
                      title: Text(key.replaceAll('can', '').replaceAll(
                          RegExp(r'(?=[A-Z])'), ' ')), // e.g., "Manage Orders"
                      value: _permissions[key],
                      activeColor: Colors.deepPurple,
                      dense: true,
                      onChanged: widget.isSelf
                          ? null
                          : (val) {
                              setState(() => _permissions[key] = val ?? false);
                            },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              if (_selectedBranches.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Please select at least one branch')));
                return;
              }

              final Map<String, dynamic> roleFields = {};
              if (_selectedRole == 'driver') {
                roleFields['licenseNumber'] = _licenseController.text.trim();
                roleFields['vehicleType'] = _vehicleType;
                roleFields['vehiclePlateNumber'] = _vehiclePlateController.text.trim();
              }

              widget.onSave({
                'name': _nameController.text.trim(),
                'email': _emailController.text.trim(),
                'phone': _phoneController.text.trim(),
                'qid': _qidController.text.trim(),
                'passportNumber': _passportController.text.trim(),
                'salary': double.tryParse(_salaryController.text.trim()) ?? 0,
                'role': _selectedRole,
                'roleFields': roleFields,
                'isActive': _isActive,
                'branchIds': _selectedBranches,
                'permissions': _permissions,
              });
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text('Save Staff'),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.deepPurple),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple)),
        const Expanded(child: Divider(indent: 12, color: Colors.deepPurple)),
      ],
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: Colors.grey[600]),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      isDense: true,
    );
  }
}
