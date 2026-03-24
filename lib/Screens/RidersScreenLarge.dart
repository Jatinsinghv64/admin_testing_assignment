import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../Widgets/BranchFilterService.dart';
import '../Widgets/ProfessionalErrorWidget.dart';
import '../main.dart'; // UserScopeService
import 'BranchManagement.dart'; // MultiBranchSelector

class RidersScreenLarge extends StatefulWidget {
  const RidersScreenLarge({super.key});

  @override
  State<RidersScreenLarge> createState() => _RidersScreenLargeState();
}

class _RidersScreenLargeState extends State<RidersScreenLarge> {
  String _filterStatus = 'all';
  String _searchQuery = '';
  String? _selectedDriverId;
  DocumentSnapshot? _selectedDriverDoc;

  final MapController _mapController = MapController();

  // For metrics
  int _activeRiderCount = 0;
  double _avgDeliveryTime = 0; // in minutes
  int _totalOrdersToday = 0;
  double _avgRating = 0;
  int _activeIncidents = 0;

  // Stream subscriptions
  StreamSubscription? _activeRidersSub;
  StreamSubscription? _todayOrdersSub;
  StreamSubscription? _deliveredOrdersSub;
  StreamSubscription? _incidentsSub;

  // Stable stream references
  Stream<QuerySnapshot<Map<String, dynamic>>>? _directoryStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _mapStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _trackingStream;

  List<String>? _lastFilterBranchIds;
  String? _lastFilterStatus;

  void _updateStableStreams(List<String> filterBranchIds, List<String> userBranchIds) {
    final bool branchIdsChanged = _lastFilterBranchIds == null || 
        _lastFilterBranchIds!.length != filterBranchIds.length ||
        !_lastFilterBranchIds!.every((id) => filterBranchIds.contains(id));
    
    final bool statusChanged = _lastFilterStatus != _filterStatus;

    if (branchIdsChanged || statusChanged) {
      // 1. Directory Query
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('Drivers').orderBy('name');
      if (filterBranchIds.isNotEmpty) {
        if (filterBranchIds.length == 1) {
          query = query.where('branchIds', arrayContains: filterBranchIds.first);
        } else {
          query = query.where('branchIds', arrayContainsAny: filterBranchIds.take(10).toList());
        }
      } else if (userBranchIds.isNotEmpty) {
        if (userBranchIds.length == 1) {
          query = query.where('branchIds', arrayContainsAny: userBranchIds);
        } else {
          query = query.where('branchIds', arrayContainsAny: userBranchIds.take(10).toList());
        }
      }

      if (_filterStatus == 'online') {
        query = query.where('status', isEqualTo: 'online');
      } else if (_filterStatus == 'offline') {
        query = query.where('status', isEqualTo: 'offline');
      } else if (_filterStatus == 'available') {
        query = query.where('isAvailable', isEqualTo: true);
      } else if (_filterStatus == 'busy') {
        query = query.where('isAvailable', isEqualTo: false);
      }
      _directoryStream = query.snapshots();

      // 2. Map Query (Always online or on_delivery + branch filter)
      Query<Map<String, dynamic>> mapQuery = FirebaseFirestore.instance
          .collection('Drivers')
          .where('status', whereIn: ['online', 'on_delivery']);
      
      if (filterBranchIds.isNotEmpty) {
        if (filterBranchIds.length == 1) {
          mapQuery = mapQuery.where('branchIds', arrayContains: filterBranchIds.first);
        } else {
          mapQuery = mapQuery.where('branchIds', arrayContainsAny: filterBranchIds.take(10).toList());
        }
      }
      _mapStream = mapQuery.snapshots();

      // 3. Tracking Query (Always on_delivery + branch filter)
      Query<Map<String, dynamic>> trackingQuery = FirebaseFirestore.instance
          .collection('Drivers')
          .where('status', isEqualTo: 'on_delivery');
      
      if (filterBranchIds.isNotEmpty) {
        if (filterBranchIds.length == 1) {
          trackingQuery = trackingQuery.where('branchIds', arrayContains: filterBranchIds.first);
        } else {
          trackingQuery = trackingQuery.where('branchIds', arrayContainsAny: filterBranchIds.take(10).toList());
        }
      }
      _trackingStream = trackingQuery.limit(5).snapshots();

      if (branchIdsChanged) {
        _fetchMetrics(filterBranchIds);
      }

      _lastFilterBranchIds = List.from(filterBranchIds);
      _lastFilterStatus = _filterStatus;
    }
  }


  @override
  void initState() {
    super.initState();
    // Initial metrics fetch will happen in build/updateStableStreams
  }

  @override
  void dispose() {
    _activeRidersSub?.cancel();
    _todayOrdersSub?.cancel();
    _deliveredOrdersSub?.cancel();
    _incidentsSub?.cancel();
    super.dispose();
  }

  void _fetchMetrics(List<String> branchIds) {
    // Cancel existing subscriptions
    _activeRidersSub?.cancel();
    _todayOrdersSub?.cancel();
    _deliveredOrdersSub?.cancel();
    _incidentsSub?.cancel();

    // 1. Active riders (online or on_delivery)
    Query<Map<String, dynamic>> ridersQuery = FirebaseFirestore.instance
        .collection('Drivers')
        .where('status', whereIn: ['online', 'on_delivery']);
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        ridersQuery = ridersQuery.where('branchIds', arrayContains: branchIds.first);
      } else {
        ridersQuery = ridersQuery.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    _activeRidersSub = ridersQuery.snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _activeRiderCount = snapshot.docs.length;
        });
      }
    });

    // 2. Today's orders
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    Query<Map<String, dynamic>> ordersQuery = FirebaseFirestore.instance
        .collection('Orders')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay));
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        ordersQuery = ordersQuery.where('branchIds', arrayContains: branchIds.first);
      } else {
        ordersQuery = ordersQuery.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    _todayOrdersSub = ordersQuery.snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _totalOrdersToday = snapshot.docs.length;
        });
      }
    });

    // 3. Delivered orders for rating and delivery time
    Query<Map<String, dynamic>> deliveredQuery = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', isEqualTo: 'delivered');
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        deliveredQuery = deliveredQuery.where('branchIds', arrayContains: branchIds.first);
      } else {
        deliveredQuery = deliveredQuery.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    _deliveredOrdersSub = deliveredQuery.snapshots().listen((snapshot) {
      double totalRating = 0;
      int ratedCount = 0;
      double totalDuration = 0;
      int durationCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        // Rating
        final rawRating = data['riderRating'];
        double? ratingVal;
        if (rawRating is num) {
          ratingVal = rawRating.toDouble();
        } else if (rawRating is String) {
          ratingVal = double.tryParse(rawRating);
        }
        if (ratingVal != null && ratingVal > 0) {
          totalRating += ratingVal;
          ratedCount++;
        }

        // Duration
        final duration = data['deliveryDuration'];
        if (duration is num) {
          totalDuration += duration.toDouble();
          durationCount++;
        }
      }

      if (mounted) {
        setState(() {
          _avgRating = ratedCount > 0 ? totalRating / ratedCount : 0;
          _avgDeliveryTime = durationCount > 0 ? totalDuration / durationCount : 0;
        });
      }
    });

    // 4. Active incidents
    Query<Map<String, dynamic>> incidentsQuery = FirebaseFirestore.instance
        .collection('Orders')
        .where('status', whereIn: ['issue', 'cancelled']);
    
    if (branchIds.isNotEmpty) {
      if (branchIds.length == 1) {
        incidentsQuery = incidentsQuery.where('branchIds', arrayContains: branchIds.first);
      } else {
        incidentsQuery = incidentsQuery.where('branchIds', arrayContainsAny: branchIds.take(10).toList());
      }
    }

    _incidentsSub = incidentsQuery.snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _activeIncidents = snapshot.docs.length;
        });
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final theme = Theme.of(context);

    final filterBranchIds = 
        branchFilter.getFilterBranchIds(userScope.branchIds);

    _updateStableStreams(filterBranchIds, userScope.branchIds);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ========== TOP APP BAR ==========

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: theme.appBarTheme.backgroundColor ?? Colors.white,
              border: Border(
                bottom: BorderSide(color: theme.primaryColor.withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                // Logo / Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.delivery_dining,
                          color: theme.primaryColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Rider Management',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Add New Rider button
                ElevatedButton.icon(
                  onPressed: () => _showDriverDialog(context, userScope),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add New Rider'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),


            // ========== MAIN CONTENT ==========
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Top metrics info
                  Text(
                    'Monitoring $_activeRiderCount active riders across delivery zones.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),

                  const SizedBox(height: 24),

                  // Performance Metrics Row (real data)
                  _buildMetricsRow(theme.primaryColor),
                  const SizedBox(height: 24),

                  // Three‑column grid
                  SizedBox(
                    height: 800, // Constrained height for full page scroll
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [

                        // LEFT COLUMN: Rider list
                        Container(
                          width: 320,
                          margin: const EdgeInsets.only(right: 16),
                          child: _buildRiderList(_directoryStream!, theme.primaryColor),
                        ),


                        // MIDDLE COLUMN: Map + Active tracking
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildMapSection(theme.primaryColor),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                flex: 2,
                                child: _buildActiveTracking(theme.primaryColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),

                        // RIGHT COLUMN: Rider details
                        Expanded(
                          flex: 3,
                          child: _selectedDriverDoc != null
                              ? _DriverDetailPaneNew(
                            driverDoc: _selectedDriverDoc!,
                            userScope: userScope,
                            onClose: () => setState(() {
                              _selectedDriverId = null;
                              _selectedDriverDoc = null;
                            }),
                          )
                              : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.two_wheeler,
                                    size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'Select a rider to view details',
                                  style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }





  Widget _buildMetricsRow(Color primary) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [

        _MetricCard(
          title: 'Avg. Delivery Time',
          value: '${_avgDeliveryTime.toStringAsFixed(1)} min',
          change: '-4%', // You can compute real change if you have historical data
          progress: 0.75,
          color: primary,
        ),
        const SizedBox(width: 16),
        _MetricCard(
          title: 'Total Orders Today',
          value: '$_totalOrdersToday',
          change: '+12%',
          progress: 0.88,
          color: primary,
        ),
        const SizedBox(width: 16),
        _MetricCard(
          title: 'Customer Rating',
          value: _avgRating.toStringAsFixed(2),
          change: '+0.2',
          progress: _avgRating / 5,
          color: primary,
        ),
        const SizedBox(width: 16),
          _MetricCard(
            title: 'Active Incidents',
            value: '$_activeIncidents',
            change: 'Low',
            progress: _activeIncidents / 10, // adjust scale
            color: primary,
            isIncident: true,
          ),
        ],
      ),
    );
  }


  Widget _buildRiderList(Stream<QuerySnapshot<Map<String, dynamic>>> stream, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rider Directory',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _filterStatus == 'all',
                        onTap: () => setState(() => _filterStatus = 'all'),
                        primary: primary,
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Active',
                        selected: _filterStatus == 'online',
                        onTap: () => setState(() => _filterStatus = 'online'),
                        primary: primary,
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'On Delivery',
                        selected: _filterStatus == 'busy',
                        onTap: () => setState(() => _filterStatus = 'busy'),
                        primary: primary,
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Offline',
                        selected: _filterStatus == 'offline',
                        onTap: () => setState(() => _filterStatus = 'offline'),
                        primary: primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Search field (moved here from app bar)
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search riders...',
                    prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ProfessionalErrorWidget(
                    title: 'Error',
                    message: snapshot.error.toString(),
                    icon: Icons.error_outline,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data!.docs;

                // Apply search filter
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final name = (data['name'] as String? ?? '').toLowerCase();
                    final email = (data['email'] as String? ?? '').toLowerCase();
                    return name.contains(q) || email.contains(q);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('No drivers found',
                            style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final isSelected = doc.id == _selectedDriverId;
                    return _DriverListTile(
                      doc: doc,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedDriverId = doc.id;
                          _selectedDriverDoc = doc;
                        });
                      },
                      primaryColor: primary,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection(Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),

                ),
                const SizedBox(width: 8),
                const Text(
                  'Live View',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    if (_selectedDriverDoc != null) {
                      _showTrackingDialog(context, _selectedDriverDoc!);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Select a rider first')),
                      );
                    }
                  },
                  icon: const Icon(Icons.fullscreen, size: 16),
                  label: const Text('Full Screen'),
                  style: TextButton.styleFrom(foregroundColor: primary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _mapStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;

                final markers = <Marker>[];
                for (final doc in docs) {
                  final data = doc.data();
                  final geoPoint = data['currentLocation'] as GeoPoint?;
                  if (geoPoint != null &&
                      geoPoint.latitude != 0 &&
                      geoPoint.longitude != 0) {
                    markers.add(
                      Marker(
                        point: LatLng(geoPoint.latitude, geoPoint.longitude),
                        width: 60,
                        height: 60,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDriverId = doc.id;
                              _selectedDriverDoc = doc;
                            });
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: data['status'] == 'online'
                                          ? Colors.green
                                          : Colors.orange,
                                      width: 2),

                                ),
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundImage:
                                  data['profileImageUrl'] != null
                                      ? NetworkImage(data['profileImageUrl'])
                                      : null,
                                  child: data['profileImageUrl'] == null
                                      ? const Icon(Icons.person, size: 16)
                                      : null,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: data['status'] == 'online'
                                        ? Colors.green
                                        : Colors.orange,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white),

                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                }

                return FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: markers.isNotEmpty
                        ? markers.first.point
                        : const LatLng(40.7128, -74.0060),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Row(
                  children: [
                    Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: primary, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('On Delivery', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(width: 16),
                Row(
                  children: [
                    Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('Available', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTracking(Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Active Delivery Tracking',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _trackingStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No active deliveries',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    // You can fetch the assigned order to get distance/ETA
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: primary.withOpacity(0.1),
                            backgroundImage: data['profileImageUrl'] != null
                                ? NetworkImage(data['profileImageUrl'])
                                : null,
                            child: data['profileImageUrl'] == null
                                ? Text(data['name']?[0] ?? '?')
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['name'] ?? 'Unknown',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Order: ${data['assignedOrderId'] ?? 'N/A'}',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey[600]),
                                ),

                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${(data['distanceToNext'] ?? '?')} km',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, color: Colors.orange),
                              ),

                              Text(
                                'ETA: ${(data['eta'] ?? '?')} min',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDriverDialog(BuildContext context, UserScopeService userScope,
      {DocumentSnapshot<Map<String, dynamic>>? driverDoc}) {
    showDialog(
      context: context,
      builder: (context) => _DriverDialog(userScope: userScope, driverDoc: driverDoc),
    );
  }

  void _showTrackingDialog(BuildContext context, DocumentSnapshot driverDoc) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
            child: Column(
              children: [
                AppBar(
                  title: Text(
                    'Live Tracking: ${(driverDoc.data() as Map)['name'] ?? 'Driver'}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  leading: const Icon(Icons.location_on, color: Colors.white),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: driverDoc.reference.snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                      final geoPoint = data['currentLocation'] as GeoPoint?;
                      final status = data['status'] ?? 'offline';

                      if (geoPoint == null ||
                          (geoPoint.latitude == 0 && geoPoint.longitude == 0)) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.location_off, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No GPS data available for this driver'),
                            ],
                          ),
                        );
                      }

                      final position = LatLng(geoPoint.latitude, geoPoint.longitude);

                      return FlutterMap(
                        options: MapOptions(
                          initialCenter: position,
                          initialZoom: 15,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.app',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: position,
                                width: 120, // Increased to avoid clipping labels
                                height: 80,

                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: status == 'online' ? Colors.green : Theme.of(context).primaryColor,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                          )
                                        ],
                                      ),
                                      child: Text(
                                        data['name'] ?? 'Driver',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),


                                    Icon(
                                      Icons.location_on,
                                      color: status == 'online'
                                          ? Colors.green
                                          : (status == 'on_delivery' ? Colors.orange : Colors.grey),
                                      size: 40,
                                    ),

                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[50],
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        'Updates live as the driver moves.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ========== HELPER WIDGETS ==========

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color primary;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary : primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? primary : primary.withOpacity(0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : primary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),

      ),
    );
  }
}

class _DriverListTile extends StatelessWidget {
  final DocumentSnapshot doc;
  final bool isSelected;
  final VoidCallback onTap;
  final Color primaryColor;

  const _DriverListTile({
    required this.doc,
    required this.isSelected,
    required this.onTap,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unknown';
    final status = data['status'] ?? 'offline';

    // Safely extract vehicle type
    String vehicleType = 'Bike';
    if (data['vehicle'] != null) {
      if (data['vehicle'] is Map) {
        vehicleType = (data['vehicle'] as Map)['type']?.toString() ?? 'Bike';
      } else {
        vehicleType = data['vehicle'].toString();
      }
    }

    Color statusColor;
    String statusLabel;
    if (status == 'online') {
      statusColor = Colors.green;
      statusLabel = 'Available';
    } else if (status == 'on_delivery') {
      statusColor = Colors.orange;
      statusLabel = 'On Delivery';
    } else {
      statusColor = Colors.grey;
      statusLabel = 'Offline';
    }


    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? primaryColor : Colors.transparent),
        ),

        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage: data['profileImageUrl'] != null
                      ? NetworkImage(data['profileImageUrl'])
                      : null,
                  child: data['profileImageUrl'] == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 4),
                  Text(
                    vehicleType,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 10,
                        color: isSelected ? Colors.white.withOpacity(0.8) : Colors.grey[600]),
                  ),


                ],
              ),
            ),
            Text(
              statusLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : statusColor,
              ),
            ),

          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String change;
  final double progress; // 0..1
  final Color color;
  final bool isIncident;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.change,
    required this.progress,
    required this.color,
    this.isIncident = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220, // Fixed width for scrolling
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isIncident
                        ? Colors.red.withOpacity(0.1)
                        : color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    change,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isIncident ? Colors.red : color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                  isIncident ? Colors.red : color),
            ),
          ],
        ),
      );
  }


}

// ========== DETAIL PANE ==========
class _DriverDetailPaneNew extends StatefulWidget {
  final DocumentSnapshot driverDoc;
  final UserScopeService userScope;
  final VoidCallback onClose;

  const _DriverDetailPaneNew({
    required this.driverDoc,
    required this.userScope,
    required this.onClose,
  });

  @override
  State<_DriverDetailPaneNew> createState() => _DriverDetailPaneNewState();
}

class _DriverDetailPaneNewState extends State<_DriverDetailPaneNew> {
  int? _realDeliveryCount;
  double? _realAverageRating;
  StreamSubscription? _statsSub;


  @override
  void initState() {
    super.initState();
    _fetchRealStats();
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    super.dispose();
  }


  @override
  void didUpdateWidget(covariant _DriverDetailPaneNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driverDoc.id != widget.driverDoc.id) {
      _fetchRealStats();
    }
  }

  void _fetchRealStats() {
    _statsSub?.cancel();
    _statsSub = FirebaseFirestore.instance
        .collection('Orders')
        .where('riderId', isEqualTo: widget.driverDoc.id)
        .where('status', isEqualTo: 'delivered')
        .snapshots()
        .listen((snapshot) {
      double totalRating = 0.0;
      int ratedOrdersCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rawRating = data['riderRating'];
        double? ratingVal;

        if (rawRating is num) {
          ratingVal = rawRating.toDouble();
        } else if (rawRating is String) {
          ratingVal = double.tryParse(rawRating);
        }

        if (ratingVal != null && ratingVal > 0) {
          totalRating += ratingVal;
          ratedOrdersCount++;
        }
      }

      if (mounted) {
        setState(() {
          _realDeliveryCount = snapshot.docs.length;
          _realAverageRating =
              ratedOrdersCount > 0 ? totalRating / ratedOrdersCount : 0.0;
        });
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.driverDoc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unknown';
    final vehicle = data['vehicle'] ?? {};
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header with avatar and edit button
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: Colors.white,
                        backgroundImage: data['profileImageUrl'] != null
                            ? NetworkImage(data['profileImageUrl'])
                            : null,
                        child: data['profileImageUrl'] == null
                            ? Icon(Icons.person, size: 48, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: Icon(Icons.edit, color: theme.primaryColor),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => _DriverDialog(
                            userScope: widget.userScope,
                            driverDoc: widget.driverDoc
                            as DocumentSnapshot<Map<String, dynamic>>,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Contact and vehicle info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(icon: Icons.phone, label: data['phone'] ?? 'N/A'),
                  _DetailRow(
                      icon: Icons.motorcycle,
                      label:
                      '${vehicle['type'] ?? 'Unknown'} • ${vehicle['number'] ?? ''}'),
                  _DetailRow(icon: Icons.email, label: data['email'] ?? 'N/A'),
                  const SizedBox(height: 16),
                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          label: 'Deliveries',
                          value: '${_realDeliveryCount ?? 0}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBox(
                          label: 'Rating',
                          value: _realAverageRating?.toStringAsFixed(1) ?? '0.0',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  // History button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _DriverOrderHistoryScreen(
                              driverId: widget.driverDoc.id,
                              driverName: name,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('View Full History'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.primaryColor,
                        side: BorderSide(color: theme.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ========== DRIVER DIALOG (ADD/EDIT) ==========
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

    _nameCtrl = TextEditingController(text: data?['name']?.toString() ?? '');
    _emailCtrl = TextEditingController(text: data?['email']?.toString() ?? '');
    _phoneCtrl = TextEditingController(text: data?['phone']?.toString() ?? '');
    _profileImgCtrl =
        TextEditingController(text: data?['profileImageUrl']?.toString() ?? '');
    _status = data?['status']?.toString() ?? 'offline';
    _isAvailable = data?['isAvailable'] ?? false;
    _selectedBranchIds = List<String>.from(data?['branchIds'] ?? []);

    String vType = 'Motorcycle';
    String vNum = '';
    try {
      if (data?['vehicle'] is Map) {
        final v = data!['vehicle'] as Map<String, dynamic>;
        vType = v['type']?.toString() ?? 'Motorcycle';
        vNum = v['number']?.toString() ?? '';
      } else if (data?['vehicle'] != null) {
        vType = data?['vehicle'].toString() ?? 'Motorcycle';
      }
    } catch (e) {
      debugPrint('Error parsing vehicle data: $e');
    }
    _vehicleTypeCtrl = TextEditingController(text: vType);
    _vehicleNumCtrl = TextEditingController(text: vNum);
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

    if (!widget.userScope.isSuperAdmin) {
      _selectedBranchIds = widget.userScope.branchIds;
    }

    if (_selectedBranchIds.isEmpty && !widget.userScope.isSuperAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Error: You are not assigned to any branch.'),
            backgroundColor: Colors.red),
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
        'assignedOrderId':
        _isEdit ? widget.driverDoc!.data()!['assignedOrderId'] ?? '' : '',
        'fcmToken': _isEdit ? widget.driverDoc!.data()!['fcmToken'] ?? '' : '',
        'rating': _isEdit ? widget.driverDoc!.data()!['rating'] ?? '0' : '0',
        'totalDeliveries':
        _isEdit ? widget.driverDoc!.data()!['totalDeliveries'] ?? 0 : 0,
        'currentLocation': _isEdit
            ? widget.driverDoc!.data()!['currentLocation'] ??
            const GeoPoint(0, 0)
            : const GeoPoint(0, 0),
      };

      if (_isEdit) {
        await widget.driverDoc!.reference.update(driverData);
      } else {
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
              content:
              Text('Driver ${_isEdit ? 'updated' : 'added'} successfully!'),
              backgroundColor: Theme.of(context).primaryColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving driver: $e'),
              backgroundColor: Colors.red),
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
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with theme color
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: primary,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(
                      _isEdit ? Icons.edit : Icons.person_add,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEdit ? 'Edit Rider' : 'Add New Rider',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _isEdit
                            ? 'Update rider information'
                            : 'Fill in rider details below',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8), fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Form body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle('Personal Information'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: inputDecoration.copyWith(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline, color: primary),
                        ),
                        validator: (v) =>
                        v!.isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        enabled: !_isEdit,
                        decoration: inputDecoration.copyWith(
                          labelText: 'Email (Login ID)',
                          prefixIcon: Icon(Icons.email_outlined, color: primary),
                          helperText:
                          _isEdit ? 'Email cannot be changed' : null,
                        ),
                        validator: (v) =>
                        v!.isEmpty ? 'Email is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: inputDecoration.copyWith(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone_outlined, color: primary),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle('Vehicle Information'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _vehicleTypeCtrl,
                              decoration: inputDecoration.copyWith(
                                labelText: 'Vehicle Type',
                                prefixIcon: Icon(Icons.two_wheeler, color: primary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _vehicleNumCtrl,
                              decoration: inputDecoration.copyWith(
                                labelText: 'Plate Number',
                                prefixIcon: Icon(Icons.pin, color: primary),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle('Status & Availability'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration: inputDecoration.copyWith(
                          labelText: 'Status',
                          prefixIcon: Icon(Icons.signal_wifi_4_bar, color: primary),
                        ),
                        items: ['online', 'offline', 'on_delivery'].map((s) {
                          IconData icon;
                          Color color;
                          switch (s) {
                            case 'online':
                              icon = Icons.check_circle;
                              color = primary;
                              break;
                            case 'offline':
                              icon = Icons.cancel;
                              color = Colors.red;
                              break;
                            default:
                              icon = Icons.delivery_dining;
                              color = Colors.orange;
                          }
                          return DropdownMenuItem(
                              value: s,
                              child: Row(
                                children: [
                                  Icon(icon, color: color, size: 18),
                                  const SizedBox(width: 8),
                                  Text(s.replaceAll('_', ' ').toUpperCase()),
                                ],
                              ));
                        }).toList(),
                        onChanged: (v) => setState(() => _status = v!),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Available for Orders'),
                          subtitle: Text(
                              _isAvailable
                                  ? 'Can receive new orders'
                                  : 'Not accepting orders',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12)),
                          value: _isAvailable,
                          activeColor: primary,
                          onChanged: (v) => setState(() => _isAvailable = v),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (widget.userScope.isSuperAdmin) ...[
                        _SectionTitle('Branch Assignment'),
                        const SizedBox(height: 12),
                        MultiBranchSelector(
                          selectedIds: _selectedBranchIds,
                          onChanged: (selected) =>
                              setState(() => _selectedBranchIds = selected),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Icon(Icons.store, color: primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Branch Assignment',
                                        style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                    Text(
                                        '${widget.userScope.branchIds.length} branch(es) assigned',
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
            // Footer buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[400]!),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                          : Text(_isEdit ? 'Update Rider' : 'Add Rider'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.grey[700],
      ),
    );
  }
}

// ========== ORDER HISTORY SCREEN ==========
class _DriverOrderHistoryScreen extends StatefulWidget {
  final String driverId;
  final String driverName;

  const _DriverOrderHistoryScreen({
    required this.driverId,
    required this.driverName,
  });

  @override
  State<_DriverOrderHistoryScreen> createState() =>
      _DriverOrderHistoryScreenState();
}

class _DriverOrderHistoryScreenState extends State<_DriverOrderHistoryScreen> {
  String _filterStatus = 'all';
  final List<String> _statusFilters = ['all', 'delivered', 'cancelled'];
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
      query = query.where('riderId', isEqualTo: widget.driverId);
      query = query.orderBy('timestamp', descending: true);
      if (_filterStatus != 'all') {
        query = query.where('status', isEqualTo: _filterStatus);
      }
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
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order History',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primary,
                  fontSize: 20),
            ),
            Text(
              widget.driverName,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _buildStatusFilter(primary),
          const SizedBox(height: 8),
          Expanded(child: _buildOrderList(primary)),
        ],
      ),
    );
  }

  Widget _buildStatusFilter(Color primary) {
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
                selectedColor: primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                backgroundColor: primary.withOpacity(0.1),
                checkmarkColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildOrderList(Color primary) {
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
              child: Text("Retry", style: TextStyle(color: primary)),
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
        child: Text("No orders found.",
            style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length + 1,
      itemBuilder: (context, index) {
        if (index == _orders.length) {
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: ElevatedButton(
                  onPressed: _fetchOrders,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.black),
                  child: _isLoading
                      ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                      : const Text("Load More (6 Orders)"),
                ),
              ),
            );
          } else {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                  child: Text("No more orders",
                      style: TextStyle(color: Colors.grey))),
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
    final theme = Theme.of(context);
    final data = order.data() as Map<String, dynamic>? ?? {};
    final orderId = order.id;
    final status = data['status']?.toString() ?? 'unknown';
    final timestamp = data['timestamp'] as Timestamp?;
    final totalAmount =
        double.tryParse(data['totalAmount']?.toString() ?? '0') ?? 0.0;
    final orderType = data['Order_type']?.toString() ?? 'delivery';
    double rating = 0.0;
    final rawRating = data['rating'] ?? data['riderRating'];
    if (rawRating is num) {
      rating = rawRating.toDouble();
    } else if (rawRating is String) {
      rating = double.tryParse(rawRating) ?? 0.0;
    }
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

    Color statusColor;
    switch (status) {
      case 'delivered':
        statusColor = theme.primaryColor;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order Number',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      SelectableText('#$orderId',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              fontFamily: 'monospace',
                              color: theme.primaryColor)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(status.toUpperCase(),
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (rating > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.amber)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(orderType.toUpperCase().replaceAll('_', ' '),
                  style: TextStyle(
                      fontSize: 10,
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Text('📅 $dateStr', style: const TextStyle(fontSize: 12)),
            if (address != 'No address')
              Text('📍 $address',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text('QAR ${totalAmount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                    fontSize: 16)),
          ],
        ),
      ),
    );
  }
}