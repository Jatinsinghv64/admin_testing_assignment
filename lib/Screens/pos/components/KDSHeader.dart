// lib/Screens/pos/components/KDSHeader.dart
// Clean, industry-grade KDS header with date filter and layout toggle

import 'package:flutter/material.dart';

class KDSHeader extends StatelessWidget {
  final bool isDark;
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;
  final bool isAudioEnabled;
  final VoidCallback onToggleAudio;
  final bool isKanbanMode;
  final VoidCallback? onToggleLayout;
  final String dateRange;
  final ValueChanged<String>? onDateRangeChanged;

  const KDSHeader({
    super.key,
    required this.isDark,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.isAudioEnabled,
    required this.onToggleAudio,
    this.isKanbanMode = false,
    this.onToggleLayout,
    this.dateRange = 'today',
    this.onDateRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16213e) : Colors.white,
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // Title
          Icon(Icons.kitchen, color: Colors.deepPurple, size: 22),
          const SizedBox(width: 10),
          Text(
            'Kitchen Display',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(width: 20),

          // Status filter chips
          _chip('All', 'all'),
          const SizedBox(width: 6),
          _chip('New', 'new'),
          const SizedBox(width: 6),
          _chip('Cooking', 'inProgress'),

          const Spacer(),

          // Date range filter
          if (onDateRangeChanged != null)
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: dateRange,
                  isDense: true,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                  dropdownColor: isDark ? const Color(0xFF252545) : Colors.white,
                  icon: Icon(Icons.calendar_today, size: 14, color: isDark ? Colors.white54 : Colors.grey),
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Today')),
                    DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
                    DropdownMenuItem(value: 'week', child: Text('Last 7 Days')),
                  ],
                  onChanged: (v) { if (v != null) onDateRangeChanged!(v); },
                ),
              ),
            ),
          const SizedBox(width: 8),

          // Layout toggle
          if (onToggleLayout != null)
            _iconBtn(
              isKanbanMode ? Icons.grid_view_rounded : Icons.view_column_rounded,
              isKanbanMode ? 'Grid view' : 'Kanban view',
              onToggleLayout!,
            ),

          // Audio toggle
          _iconBtn(
            isAudioEnabled ? Icons.volume_up : Icons.volume_off,
            'Sound',
            onToggleAudio,
            color: isAudioEnabled ? Colors.deepPurple : Colors.grey,
          ),

          const SizedBox(width: 4),
          // Clock
          _buildClock(),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = activeFilter == value;
    return GestureDetector(
      onTap: () => onFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.deepPurple : (isDark ? Colors.white12 : Colors.grey[300]!),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? Colors.white : (isDark ? Colors.white54 : Colors.grey[700]),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: color ?? Colors.deepPurple),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildClock() {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, _) {
        final now = DateTime.now();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey[50],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white54 : Colors.black54,
              fontFamily: 'monospace',
            ),
          ),
        );
      },
    );
  }
}

