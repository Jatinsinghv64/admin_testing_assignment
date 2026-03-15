// lib/Screens/pos/components/kds_constants.dart

import 'package:flutter/material.dart';

class KDSConfig {
  static const int onTimeMinutes = 10; // Green
  static const int warningMinutes = 15; // Orange
  static const int lateMinutes = 20; // Red (late)
  static const int columnsCount = 3; // 3 orders per row

  // Grid View time thresholds (Odoo Kitchen Display style)
  static const int gridFreshMinutes = 5;    // Green — just arrived
  static const int gridWarningMinutes = 10;  // Orange — waiting too long
  // 10+ min = Red (urgent)

  // Delayed alert threshold (configurable)
  static const int delayedAlertMinutes = 15;

  /// Color for grid tile background based on elapsed minutes
  static Color getGridTileColor(int elapsedMinutes) {
    if (elapsedMinutes >= gridWarningMinutes) return const Color(0xFFE53935); // Red
    if (elapsedMinutes >= gridFreshMinutes) return const Color(0xFFF57C00);   // Orange
    return const Color(0xFF43A047); // Green
  }

  // Text sizes - Odoo style
  static const double headerMainText = 18;
  static const double headerSecondaryText = 15;
  static const double dishNameSize = 18;
  static const double dishQuantitySize = 18;
  static const double notesSize = 15;
  static const double badgeTextSize = 14;
  static const double buttonTextSize = 15;
  static const double timerTextSize = 15;
  static const double customerInfoSize = 15;

  static Color getTimerColor(int elapsedMinutes) {
    if (elapsedMinutes >= lateMinutes) return Colors.red;
    if (elapsedMinutes >= warningMinutes) return Colors.orange;
    return Colors.green;
  }

  // ✅ Order Source mappings
  static Color getSourceColor(String? source) {
    switch (source?.toLowerCase()) {
      case 'snoonu':
        return const Color(0xFFE91E63); // Pink
      case 'talabat':
        return const Color(0xFFFF6F00); // Orange
      case 'keta':
        return const Color(0xFF4CAF50); // Green
      case 'pos':
        return Colors.deepPurple;
      case 'app':
      case 'website':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  static String getSourceLabel(String? source) {
    switch (source?.toLowerCase()) {
      case 'snoonu':
        return 'SNOONU';
      case 'talabat':
        return 'TALABAT';
      case 'keta':
        return 'KETA';
      case 'pos':
        return 'POS';
      case 'app':
        return 'APP';
      case 'website':
        return 'WEB';
      default:
        return 'APP';
    }
  }

  static IconData getSourceIcon(String? source) {
    switch (source?.toLowerCase()) {
      case 'snoonu':
      case 'talabat':
      case 'keta':
        return Icons.delivery_dining;
      case 'pos':
        return Icons.point_of_sale;
      case 'website':
        return Icons.language;
      default:
        return Icons.phone_android;
    }
  }
}
