import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/responsive_helper.dart';
import 'BranchManagement.dart'; // For BranchDialog

class BranchManagementScreenLarge extends StatefulWidget {
  const BranchManagementScreenLarge({super.key});

  @override
  State<BranchManagementScreenLarge> createState() => _BranchManagementScreenLargeState();
}

class _BranchManagementScreenLargeState extends State<BranchManagementScreenLarge> {
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _cityFilter = 'All';

  // App Palette COLORS
  static const Color appBackground = Color(0xFFF9FAFB); // grey[50]
  static const Color appPrimary = Colors.deepPurple;
  static const Color appTertiary = Colors.orange;
  static const Color appError = Colors.red;
  static const Color appSurface = Colors.white;
  static const Color appText = Colors.black87;
  static const Color appTextVariant = Colors.grey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: appBackground,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(textTheme, primaryColor),
            const SizedBox(height: 40),
            _buildFilterBar(primaryColor),
            const SizedBox(height: 24),
            _buildBranchGrid(primaryColor),
            const SizedBox(height: 48),
            _buildActivityAndMap(textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TextTheme textTheme, Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BRANCH MANAGEMENT',
              style: textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: Colors.black87,
                letterSpacing: -1,
                fontSize: 36,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Operational control of regional logistics hubs.',
              style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ],
        ),
        Row(
          children: [
            _buildKPI('Active Branches', '42', '+3%', primaryColor),
            const SizedBox(width: 16),
            _buildKPI('System Volume', '1,284', 'Live', primaryColor),
            const SizedBox(width: 16),
            _buildKPI('Avg Delivery', '24.5m', '-1.2m', appTertiary),
          ],
        ),
      ],
    );
  }

  Widget _buildKPI(String label, String value, String change, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minWidth: 160),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: appTextVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  change,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, color: appTextVariant, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              style: const TextStyle(color: Colors.black87, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Filter by branch name, ID or city...',
                hintStyle: TextStyle(color: appTextVariant.withOpacity(0.5)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          _buildDropdown('Status: $_statusFilter', ['All', 'Open', 'Closed'], (val) => setState(() => _statusFilter = val!)),
          const SizedBox(width: 12),
          _buildDropdown('City: $_cityFilter', ['All', 'Cairo', 'Alexandria', 'Mansoura'], (val) => setState(() => _cityFilter = val!)),
          const SizedBox(width: 12),
          _buildActionButton('Advanced', Icons.filter_list, () {}),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(label.split(': ').last) ? label.split(': ').last : items.first,
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down, color: appTextVariant, size: 18),
          style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          items: items.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.black87),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchGrid(Color primaryColor) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Branch').orderBy('name').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: primaryColor));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No branches found', style: TextStyle(color: appText)));
        }

        final branches = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = data['name']?.toString().toLowerCase() ?? '';
          final city = (data['address'] as Map?)?['city']?.toString().toLowerCase() ?? '';
          final status = (data['isOpen'] ?? false) ? 'Open' : 'Closed';

          final matchesSearch = name.contains(_searchQuery) || city.contains(_searchQuery);
          final matchesStatus = _statusFilter == 'All' || status == _statusFilter;
          final matchesCity = _cityFilter == 'All' || city.contains(_cityFilter.toLowerCase());

          return matchesSearch && matchesStatus && matchesCity;
        }).toList();

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            childAspectRatio: 1.1,
          ),
          itemCount: branches.length + 1,
          itemBuilder: (context, index) {
            if (index == branches.length) {
              return _buildAddBranchPlaceholder();
            }
            final doc = branches[index];
            return _buildBranchCard(doc, index, primaryColor);
          },
        );
      },
    );
  }

  Widget _buildBranchCard(QueryDocumentSnapshot doc, int index, Color primaryColor) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unnamed';
    final isOpen = data['isOpen'] ?? false;
    final city = (data['address'] as Map?)?['city'] ?? 'Unknown';
    final capacity = (index % 3 == 0) ? 84 : (index % 3 == 1 ? 92 : 45); 

    return Container(
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isOpen ? Colors.green : appError).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isOpen ? 'OPEN' : 'CLOSED',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isOpen ? Colors.green : appError),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 12, color: appTextVariant),
                          const SizedBox(width: 4),
                          Text(city, style: const TextStyle(fontSize: 12, color: appTextVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isOpen,
                  onChanged: (val) => _toggleBranchStatus(doc.id, val),
                  activeColor: Colors.green,
                  activeTrackColor: Colors.green.withOpacity(0.3),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMiniStat('Active Orders', '124', primaryColor),
                      _buildMiniStat('Avg Delivery', '18m', Colors.black87),
                      _buildMiniStat('Riders', '32', Colors.black87),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Hub Load Capacity', style: TextStyle(fontSize: 12, color: appTextVariant)),
                      Text('$capacity%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: capacity > 90 ? appError : Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 6,
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(3)),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: capacity / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          color: capacity > 90 ? appError : Colors.green,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Colors.transparent),
            child: Row(
              children: [
                Expanded(
                  child: _buildSmallButton('View Dashboard', () {}),
                ),
                const SizedBox(width: 8),
                _buildSmallIconButton(Icons.settings, () => _editBranch(doc)),
                const SizedBox(width: 8),
                _buildSmallIconButton(Icons.delete, () => _deleteBranch(doc.id), color: appError.withOpacity(0.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: appTextVariant)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  Widget _buildSmallButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
      ),
    );
  }

  Widget _buildSmallIconButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Icon(icon, size: 14, color: color ?? appTextVariant),
      ),
    );
  }

  Widget _buildAddBranchPlaceholder() {
    return InkWell(
      onTap: () => showDialog(context: context, builder: (_) => const BranchDialog()),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!, width: 2, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
              child: const Icon(Icons.add_location, color: appTextVariant, size: 24),
            ),
            const SizedBox(height: 16),
            const Text('Create New Branch', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 4),
            const Text('Configure a new regional logistics hub', style: TextStyle(fontSize: 10, color: appTextVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityAndMap(TextTheme textTheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _buildOperationalAnomalies(textTheme),
        ),
        const SizedBox(width: 32),
        Expanded(
          flex: 1,
          child: _buildNetworkMap(textTheme),
        ),
      ],
    );
  }

  Widget _buildOperationalAnomalies(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Operational Anomalies', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.black87)),
              Text('Last 24 Hours', style: TextStyle(fontSize: 12, color: appTextVariant.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 24),
          _buildAnomalyItem(
            'System Latency: Alex Waterfront',
            'Delivery estimation engine reporting 5ms lag above threshold.',
            '14:22',
            appError,
          ),
          const SizedBox(height: 16),
          _buildAnomalyItem(
            'High Load: Cairo Terminal 1',
            'Approaching 95% capacity. Suggest diverting new orders to Heliopolis.',
            '12:05',
            Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildAnomalyItem(String title, String desc, String time, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: borderColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(borderColor == appError ? Icons.warning : Icons.electric_bolt, color: borderColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                Text(desc, style: const TextStyle(fontSize: 12, color: appTextVariant)),
              ],
            ),
          ),
          Text(time, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildNetworkMap(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Network Map', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 16),
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  FlutterMap(
                    options: const MapOptions(
                      initialCenter: LatLng(25.276987, 51.520008), // Doha
                      initialZoom: 11,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                      ),
                    ],
                  ),
                  const Positioned(
                    bottom: 12,
                    left: 12,
                    child: Text('LIVE DEPLOYMENT VIEW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black54, letterSpacing: 1)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Functional Methods
  void _toggleBranchStatus(String id, bool val) {
    FirebaseFirestore.instance.collection('Branch').doc(id).update({'isOpen': val});
  }

  void _editBranch(QueryDocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (_) => BranchDialog(docId: doc.id, initialData: doc.data() as Map<String, dynamic>),
    );
  }

  void _deleteBranch(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Branch'),
        content: const Text('Are you sure you want to delete this branch?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: appError))),
        ],
      ),
    );
    if (confirmed == true) {
      FirebaseFirestore.instance.collection('Branch').doc(id).delete();
    }
  }
}
