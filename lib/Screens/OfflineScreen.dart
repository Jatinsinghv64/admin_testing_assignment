//
//
//
// // Add this anywhere in your file, maybe after RiderAssignmentService class
// import 'dart:async';
// import 'dart:ui';
//
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:flutter/material.dart';
//
// import 'dart:io';
// import 'dart:io';
// import 'package:connectivity_plus/connectivity_plus.dart';
//
// class ConnectionUtils {
//   static final Connectivity _connectivity = Connectivity();
//
//   static Future<bool> hasInternetConnection() async {
//     try {
//       final result = await InternetAddress.lookup('google.com');
//       return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
//     } on SocketException catch (_) {
//       return false;
//     }
//   }
//
//   static Stream<bool> get connectionStream async* {
//     // Yield initial connection status
//     yield await hasInternetConnection();
//
//     // Listen for connectivity changes
//     await for (final results in _connectivity.onConnectivityChanged) {
//       // Wait 2 seconds for connection to stabilize
//       await Future.delayed(Duration(seconds: 2));
//       yield await hasInternetConnection();
//     }
//   }
// }
//
// class OfflineBanner extends StatefulWidget {
//   final Widget child;
//
//   const OfflineBanner({super.key, required this.child});
//
//   @override
//   State<OfflineBanner> createState() => _OfflineBannerState();
// }
//
// class _OfflineBannerState extends State<OfflineBanner> {
//   bool _isOnline = true;
//   bool _showOfflineMessage = false;
//
//   @override
//   void initState() {
//     super.initState();
//     _checkConnectionPeriodically();
//   }
//
//   void _checkConnectionPeriodically() {
//     // Check connection immediately
//     _checkConnection();
//
//     // Check every 10 seconds
//     Timer.periodic(Duration(seconds: 10), (timer) {
//       _checkConnection();
//     });
//
//     // Also listen for connectivity changes
//     Connectivity().onConnectivityChanged.listen((result) async {
//       await Future.delayed(Duration(seconds: 2));
//       _checkConnection();
//     });
//   }
//
//   Future<void> _checkConnection() async {
//     final isOnline = await ConnectionUtils.hasInternetConnection();
//     if (mounted) {
//       setState(() {
//         _isOnline = isOnline;
//       });
//
//       _handleConnectionChange(isOnline);
//     }
//   }
//
//   void _handleConnectionChange(bool isOnline) {
//     if (!isOnline) {
//       // Show offline SnackBar if not already showing
//       if (!_showOfflineMessage) {
//         _showOfflineMessage = true;
//         _showOfflineSnackBar();
//       }
//     } else {
//       // Hide offline SnackBar and show online message
//       if (_showOfflineMessage) {
//         _showOfflineMessage = false;
//         ScaffoldMessenger.of(context).hideCurrentSnackBar();
//         _showOnlineSnackBar();
//       }
//     }
//   }
//
//   void _showOfflineSnackBar() {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Row(
//           children: [
//             Icon(Icons.wifi_off, color: Colors.white),
//             SizedBox(width: 8),
//             Text('No internet connection'),
//           ],
//         ),
//         backgroundColor: Colors.red,
//         duration: Duration(days: 1), // Stays until we're back online
//         action: SnackBarAction(
//           label: 'Retry',
//           textColor: Colors.white,
//           onPressed: _retryConnection,
//         ),
//       ),
//     );
//   }
//
//   void _showOnlineSnackBar() {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Row(
//           children: [
//             Icon(Icons.wifi, color: Colors.white),
//             SizedBox(width: 8),
//             Text('Back online!'),
//           ],
//         ),
//         backgroundColor: Colors.green,
//         duration: Duration(seconds: 3),
//       ),
//     );
//   }
//
//   void _retryConnection() {
//     // Hide current SnackBar
//     ScaffoldMessenger.of(context).hideCurrentSnackBar();
//     _showOfflineMessage = false;
//
//     // Show loading SnackBar temporarily
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Row(
//           children: [
//             SizedBox(
//               width: 20,
//               height: 20,
//               child: CircularProgressIndicator(
//                 strokeWidth: 2,
//                 valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//               ),
//             ),
//             SizedBox(width: 12),
//             Text('Checking connection...'),
//           ],
//         ),
//         backgroundColor: Colors.blue,
//         duration: Duration(seconds: 2),
//       ),
//     );
//
//     // Check connection after a short delay
//     Future.delayed(Duration(seconds: 2), () {
//       _checkConnection();
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return widget.child;
//   }
// }