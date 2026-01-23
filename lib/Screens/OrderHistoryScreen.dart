// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:intl/intl.dart';
//
// class OrderHistoryScreen extends StatefulWidget {
//   const OrderHistoryScreen({super.key});
//
//   @override
//   _OrderHistoryScreenState createState() => _OrderHistoryScreenState();
// }
//
// class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
//   final int _ordersPerPage = 5;
//   List<DocumentSnapshot> _orders = [];
//   bool _isLoading = false;
//   bool _hasMore = true;
//   DocumentSnapshot? _lastDocument;
//   String _errorMessage = '';
//
//   // State for date filtering
//   DateTime? _startDate;
//   DateTime? _endDate;
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchOrders();
//   }
//
//   // Reset pagination and fetch orders with the current filters
//   void _resetAndFetchOrders() {
//     setState(() {
//       _orders = [];
//       _lastDocument = null;
//       _hasMore = true;
//     });
//     _fetchOrders();
//   }
//
//   Future<void> _fetchOrders() async {
//     if (_isLoading) return;
//
//     setState(() {
//       _isLoading = true;
//       _errorMessage = '';
//     });
//
//     try {
//       Query query = FirebaseFirestore.instance
//           .collection('Orders')
//           .where('status', whereIn: ['delivered', 'cancelled'])
//           .orderBy('timestamp', descending: true);
//
//       // Apply date filter if present
//       if (_startDate != null) {
//         query = query.where('timestamp', isGreaterThanOrEqualTo: _startDate);
//       }
//
//       if (_endDate != null) {
//         // Adjust end date to include the whole day
//         final inclusiveEndDate =
//         DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
//         query = query.where('timestamp', isLessThanOrEqualTo: inclusiveEndDate);
//       }
//
//       query = query.limit(_ordersPerPage);
//       if (_lastDocument != null) {
//         query = query.startAfterDocument(_lastDocument!);
//       }
//
//       final querySnapshot = await query.get();
//       if (querySnapshot.docs.isNotEmpty) {
//         _lastDocument = querySnapshot.docs.last;
//       }
//
//       setState(() {
//         _orders.addAll(querySnapshot.docs);
//         _hasMore = querySnapshot.docs.length == _ordersPerPage;
//       });
//     } catch (e) {
//       setState(() {
//         _errorMessage = "Error fetching orders: ${e.toString()}";
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }
//
//   // Function to show the date range picker
//   Future<void> _selectDateRange(BuildContext context) async {
//     final picked = await showDateRangePicker(
//       context: context,
//       firstDate: DateTime(2020),
//       lastDate: DateTime.now(),
//       initialDateRange: _startDate != null && _endDate != null
//           ? DateTimeRange(start: _startDate!, end: _endDate!)
//           : null,
//       builder: (context, child) {
//         return Theme(
//           data: ThemeData.light().copyWith(
//             colorScheme: const ColorScheme.light(
//               primary: Colors.deepPurple,
//               onPrimary: Colors.white,
//               surface: Colors.white,
//               onSurface: Colors.black,
//               secondary: Colors.deepPurple,
//               onSecondary: Colors.white,
//             ),
//             dialogBackgroundColor: Colors.white,
//             datePickerTheme: DatePickerThemeData(
//               backgroundColor: Colors.white,
//               elevation: 8,
//               shadowColor: Colors.black.withOpacity(0.1),
//               surfaceTintColor: Colors.transparent,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(24),
//               ),
//               headerBackgroundColor: Colors.deepPurple,
//               headerForegroundColor: Colors.white,
//               headerHeadlineStyle: const TextStyle(
//                 fontSize: 24,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.white,
//               ),
//               headerHelpStyle: const TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.w500,
//                 color: Colors.white70,
//               ),
//               weekdayStyle: TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.w600,
//                 color: Colors.grey[600],
//               ),
//               dayStyle: const TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.w500,
//               ),
//               // Use WidgetStateProperty for colors
//               dayForegroundColor: WidgetStateProperty.resolveWith((states) {
//                 if (states.contains(WidgetState.selected)) {
//                   return Colors.white;
//                 }
//                 if (states.contains(WidgetState.disabled)) {
//                   return Colors.grey[400];
//                 }
//                 return Colors.deepPurple;
//               }),
//               dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
//                 if (states.contains(WidgetState.selected)) {
//                   return Colors.deepPurple;
//                 }
//                 if (states.contains(WidgetState.hovered)) {
//                   return Colors.deepPurple.withOpacity(0.1);
//                 }
//                 return Colors.transparent;
//               }),
//               todayForegroundColor: WidgetStateProperty.resolveWith((states) {
//                 if (states.contains(WidgetState.selected)) {
//                   return Colors.white;
//                 }
//                 return Colors.deepPurple;
//               }),
//               todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
//                 if (states.contains(WidgetState.selected)) {
//                   return Colors.deepPurple;
//                 }
//                 return Colors.deepPurple.withOpacity(0.15);
//               }),
//               todayBorder: BorderSide(
//                 color: Colors.deepPurple,
//                 width: 2,
//               ),
//               yearForegroundColor: WidgetStateProperty.resolveWith((states) {
//                 if (states.contains(WidgetState.selected)) {
//                   return Colors.white;
//                 }
//                 return Colors.deepPurple;
//               }),
//               yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
//                 if (states.contains(WidgetState.selected)) {
//                   return Colors.deepPurple;
//                 }
//                 return Colors.transparent;
//               }),
//               rangePickerBackgroundColor: Colors.white,
//               rangePickerElevation: 8,
//               rangePickerShadowColor: Colors.black.withOpacity(0.1),
//               rangePickerSurfaceTintColor: Colors.transparent,
//               rangePickerShape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(24),
//               ),
//               rangePickerHeaderBackgroundColor: Colors.deepPurple,
//               rangePickerHeaderForegroundColor: Colors.white,
//               rangePickerHeaderHeadlineStyle: const TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.white,
//               ),
//               rangePickerHeaderHelpStyle: const TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.w500,
//                 color: Colors.white70,
//               ),
//               rangeSelectionBackgroundColor: Colors.deepPurple.withOpacity(0.2),
//               rangeSelectionOverlayColor: WidgetStateProperty.resolveWith((states) {
//                 if (states.contains(WidgetState.hovered)) {
//                   return Colors.deepPurple.withOpacity(0.1);
//                 }
//                 return Colors.transparent;
//               }),
//             ),
//             textButtonTheme: TextButtonThemeData(
//               style: TextButton.styleFrom(
//                 foregroundColor: Colors.deepPurple,
//                 textStyle: const TextStyle(
//                   fontWeight: FontWeight.bold,
//                   fontSize: 16,
//                 ),
//                 padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//               ),
//             ),
//             elevatedButtonTheme: ElevatedButtonThemeData(
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: Colors.deepPurple,
//                 foregroundColor: Colors.white,
//                 textStyle: const TextStyle(
//                   fontWeight: FontWeight.bold,
//                   fontSize: 16,
//                 ),
//                 padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 elevation: 0,
//               ),
//             ),
//           ),
//           child: Container(
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(24),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withOpacity(0.1),
//                   blurRadius: 20,
//                   offset: const Offset(0, 8),
//                 ),
//               ],
//             ),
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(24),
//               child: child!,
//             ),
//           ),
//         );
//       },
//     );
//
//     if (picked != null) {
//       setState(() {
//         _startDate = picked.start;
//         _endDate = picked.end;
//       });
//       _resetAndFetchOrders();
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.grey[50],
//       appBar: AppBar(
//         elevation: 0,
//         backgroundColor: Colors.white,
//         centerTitle: true,
//         iconTheme: const IconThemeData(color: Colors.deepPurple),
//         title: const Text(
//           'Order History',
//           style: TextStyle(
//             fontWeight: FontWeight.bold,
//             color: Colors.deepPurple,
//             fontSize: 24,
//           ),
//         ),
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Filter Section Header
//             _buildSectionHeader('Filter Orders', Icons.filter_list_outlined),
//             const SizedBox(height: 16),
//
//             // Date Filter Card
//             _buildDateFilterCard(),
//             const SizedBox(height: 32),
//
//             // Orders Section Header
//             _buildSectionHeader('Recent Orders', Icons.history_rounded),
//             const SizedBox(height: 16),
//
//             // Orders List
//             _buildOrdersList(),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildSectionHeader(String title, IconData icon) {
//     return Row(
//       children: [
//         Container(
//           padding: const EdgeInsets.all(8),
//           decoration: BoxDecoration(
//             color: Colors.deepPurple.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(10),
//           ),
//           child: Icon(icon, color: Colors.deepPurple, size: 20),
//         ),
//         const SizedBox(width: 12),
//         Text(
//           title,
//           style: const TextStyle(
//               fontSize: 20,
//               fontWeight: FontWeight.bold,
//               color: Colors.deepPurple),
//         ),
//       ],
//     );
//   }
//
//   Widget _buildDateFilterCard() {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: InkWell(
//         onTap: () => _selectDateRange(context),
//         borderRadius: BorderRadius.circular(20),
//         child: Padding(
//           padding: const EdgeInsets.all(20),
//           child: Row(
//             children: [
//               Container(
//                 width: 50,
//                 height: 50,
//                 decoration: BoxDecoration(
//                   color: Colors.deepPurple.withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(16),
//                 ),
//                 child: const Icon(
//                   Icons.calendar_today_outlined,
//                   color: Colors.deepPurple,
//                   size: 26,
//                 ),
//               ),
//               const SizedBox(width: 16),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       'Date Range Filter',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         fontSize: 16,
//                         color: Colors.black87,
//                       ),
//                     ),
//                     const SizedBox(height: 4),
//                     Text(
//                       _startDate != null && _endDate != null
//                           ? '${DateFormat('MMM d, yyyy').format(_startDate!)} - ${DateFormat('MMM d, yyyy').format(_endDate!)}'
//                           : 'Select date range to filter orders',
//                       style: TextStyle(
//                         fontSize: 14,
//                         color: _startDate != null
//                             ? Colors.deepPurple
//                             : Colors.grey[600],
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               if (_startDate != null)
//                 Container(
//                   padding: const EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     color: Colors.red.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: InkWell(
//                     onTap: () {
//                       setState(() {
//                         _startDate = null;
//                         _endDate = null;
//                       });
//                       _resetAndFetchOrders();
//                     },
//                     child: Icon(
//                       Icons.clear,
//                       size: 16,
//                       color: Colors.red[600],
//                     ),
//                   ),
//                 )
//               else
//                 Container(
//                   padding: const EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     color: Colors.grey[100],
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Icon(
//                     Icons.arrow_forward_ios_rounded,
//                     size: 16,
//                     color: Colors.grey[600],
//                   ),
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildOrdersList() {
//     if (_errorMessage.isNotEmpty) {
//       return _buildErrorCard();
//     }
//
//     if (_orders.isEmpty && _isLoading) {
//       return _buildLoadingCard();
//     }
//
//     if (_orders.isEmpty && !_isLoading) {
//       return _buildEmptyStateCard();
//     }
//
//     return Column(
//       children: [
//         ..._orders.map((orderDoc) {
//           final data = orderDoc.data() as Map<String, dynamic>;
//           return Padding(
//             padding: const EdgeInsets.only(bottom: 16),
//             child: _OrderHistoryCard(data: data, orderId: orderDoc.id),
//           );
//         }).toList(),
//
//         if (_hasMore && !_isLoading)
//           _buildLoadMoreButton(),
//
//         if (_isLoading && _orders.isNotEmpty)
//           _buildLoadingIndicator(),
//       ],
//     );
//   }
//
//   Widget _buildErrorCard() {
//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.red.withOpacity(0.05),
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: Colors.red.withOpacity(0.2)),
//       ),
//       child: Row(
//         children: [
//           Icon(Icons.error_outline, color: Colors.red[600], size: 24),
//           const SizedBox(width: 16),
//           Expanded(
//             child: Text(
//               _errorMessage,
//               style: TextStyle(
//                 color: Colors.red[700],
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildLoadingCard() {
//     return Container(
//       padding: const EdgeInsets.all(40),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: const Center(
//         child: Column(
//           children: [
//             CircularProgressIndicator(
//               valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
//             ),
//             SizedBox(height: 16),
//             Text(
//               'Loading orders...',
//               style: TextStyle(
//                 color: Colors.grey,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildEmptyStateCard() {
//     return Container(
//       padding: const EdgeInsets.all(40),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Center(
//         child: Column(
//           children: [
//             Container(
//               width: 80,
//               height: 80,
//               decoration: BoxDecoration(
//                 color: Colors.grey[100],
//                 borderRadius: BorderRadius.circular(20),
//               ),
//               child: Icon(
//                 Icons.receipt_long_outlined,
//                 size: 40,
//                 color: Colors.grey[400],
//               ),
//             ),
//             const SizedBox(height: 20),
//             Text(
//               'No Order History Found',
//               style: TextStyle(
//                 color: Colors.grey[600],
//                 fontSize: 18,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               _startDate != null
//                   ? 'No orders in the selected date range'
//                   : 'Completed orders will appear here',
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                 color: Colors.grey[500],
//                 fontSize: 14,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildLoadMoreButton() {
//     return Container(
//       width: double.infinity,
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(20),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.deepPurple.withOpacity(0.2),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: ElevatedButton.icon(
//         icon: const Icon(Icons.add, color: Colors.white, size: 20),
//         label: const Text(
//           'Load More Orders',
//           style: TextStyle(
//             color: Colors.white,
//             fontWeight: FontWeight.bold,
//             fontSize: 16,
//           ),
//         ),
//         onPressed: _fetchOrders,
//         style: ElevatedButton.styleFrom(
//           backgroundColor: Colors.deepPurple,
//           padding: const EdgeInsets.symmetric(vertical: 18),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(20),
//           ),
//           elevation: 0,
//         ),
//       ),
//     );
//   }
//
//   Widget _buildLoadingIndicator() {
//     return const Padding(
//       padding: EdgeInsets.symmetric(vertical: 20),
//       child: Center(
//         child: CircularProgressIndicator(
//           valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
//         ),
//       ),
//     );
//   }
// }
//
// class _OrderHistoryCard extends StatefulWidget {
//   final Map<String, dynamic> data;
//   final String orderId;
//
//   const _OrderHistoryCard({required this.data, required this.orderId});
//
//   @override
//   __OrderHistoryCardState createState() => __OrderHistoryCardState();
// }
//
// class __OrderHistoryCardState extends State<_OrderHistoryCard> {
//   String? _driverName;
//   bool _isFetchingDriver = false;
//
//   @override
//   void initState() {
//     super.initState();
//     final riderId = widget.data['riderId'] as String?;
//     if (riderId != null && riderId.isNotEmpty) {
//       _fetchDriverName(riderId);
//     }
//   }
//
//   Future<void> _fetchDriverName(String riderId) async {
//     setState(() {
//       _isFetchingDriver = true;
//     });
//
//     try {
//       final driverDoc = await FirebaseFirestore.instance
//           .collection('Drivers')
//           .doc(riderId)
//           .get();
//
//       if (driverDoc.exists) {
//         setState(() {
//           _driverName = driverDoc.data()?['name'] as String? ?? 'N/A';
//         });
//       }
//     } catch (e) {
//       setState(() {
//         _driverName = 'N/A';
//       });
//     } finally {
//       setState(() {
//         _isFetchingDriver = false;
//       });
//     }
//   }
//
//   Color _getStatusColor(String status) {
//     switch (status.toLowerCase()) {
//       case 'delivered':
//         return Colors.green;
//       case 'cancelled':
//         return Colors.red;
//       default:
//         return Colors.grey;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final data = widget.data;
//     final status = data['status']?.toString() ?? 'unknown';
//     final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
//     final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
//     final customerName = data['customerName']?.toString() ?? 'N/A';
//     final orderNumber = data['dailyOrderNumber']?.toString() ??
//         widget.orderId.substring(0, 6).toUpperCase();
//
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Padding(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Header Row with Order Number and Status
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         'Order #$orderNumber',
//                         style: const TextStyle(
//                           fontWeight: FontWeight.bold,
//                           fontSize: 18,
//                           color: Colors.black87,
//                         ),
//                       ),
//                       if (timestamp != null)
//                         const SizedBox(height: 4),
//                       if (timestamp != null)
//                         Text(
//                           DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp),
//                           style: TextStyle(
//                             color: Colors.grey[600],
//                             fontSize: 13,
//                           ),
//                         ),
//                     ],
//                   ),
//                 ),
//                 Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                   decoration: BoxDecoration(
//                     color: _getStatusColor(status).withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(20),
//                   ),
//                   child: Text(
//                     status.toUpperCase(),
//                     style: TextStyle(
//                       color: _getStatusColor(status),
//                       fontWeight: FontWeight.bold,
//                       fontSize: 11,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//
//             const SizedBox(height: 20),
//
//             // Details Section
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: Colors.grey[50],
//                 borderRadius: BorderRadius.circular(16),
//               ),
//               child: Column(
//                 children: [
//                   _buildDetailRow(
//                     Icons.person_outline,
//                     'Customer',
//                     customerName,
//                     Colors.deepPurple,
//                   ),
//                   const SizedBox(height: 12),
//
//                   if (_driverName != null)
//                     _buildDetailRow(
//                       Icons.delivery_dining_outlined,
//                       'Driver',
//                       _driverName!,
//                       Colors.blue,
//                     ),
//
//                   if (_isFetchingDriver)
//                     Padding(
//                       padding: const EdgeInsets.symmetric(vertical: 8),
//                       child: Row(
//                         children: [
//                           Icon(
//                             Icons.delivery_dining_outlined,
//                             size: 20,
//                             color: Colors.blue.withOpacity(0.7),
//                           ),
//                           const SizedBox(width: 12),
//                           const Text(
//                             'Driver: ',
//                             style: TextStyle(
//                               fontSize: 14,
//                               fontWeight: FontWeight.w500,
//                               color: Colors.black54,
//                             ),
//                           ),
//                           const Expanded(
//                             child: LinearProgressIndicator(
//                               backgroundColor: Colors.white,
//                               valueColor: AlwaysStoppedAnimation(Colors.blue),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//
//                   if (_driverName != null || _isFetchingDriver)
//                     const SizedBox(height: 12),
//
//                   // Total Amount Row
//                   Container(
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       color: Colors.white,
//                       borderRadius: BorderRadius.circular(12),
//                       border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
//                     ),
//                     child: Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         const Text(
//                           'Total Amount',
//                           style: TextStyle(
//                             fontSize: 15,
//                             fontWeight: FontWeight.w600,
//                             color: Colors.black87,
//                           ),
//                         ),
//                         Text(
//                           'QAR ${totalAmount.toStringAsFixed(2)}',
//                           style: const TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.deepPurple,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildDetailRow(IconData icon, String label, String value, Color iconColor) {
//     return Row(
//       children: [
//         Icon(icon, size: 20, color: iconColor),
//         const SizedBox(width: 12),
//         Text(
//           '$label: ',
//           style: const TextStyle(
//             fontSize: 14,
//             fontWeight: FontWeight.w500,
//             color: Colors.black54,
//           ),
//         ),
//         Expanded(
//           child: Text(
//             value,
//             style: const TextStyle(
//               fontSize: 14,
//               fontWeight: FontWeight.w600,
//               color: Colors.black87,
//             ),
//             textAlign: TextAlign.right,
//           ),
//         ),
//       ],
//     );
//   }
// }