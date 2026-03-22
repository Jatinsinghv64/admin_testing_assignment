import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HolidayClosuresCard extends StatelessWidget {
  final List<Map<String, dynamic>> holidays;
  final VoidCallback onAddHoliday;
  final ValueChanged<int> onDeleteHoliday;
  final ValueChanged<int> onEditHoliday;

  const HolidayClosuresCard({
    super.key,
    required this.holidays,
    required this.onAddHoliday,
    required this.onDeleteHoliday,
    required this.onEditHoliday,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_busy, color: Colors.deepPurple, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'HOLIDAY CLOSURES',
                    style: textTheme.labelSmall?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {}, // View All
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'View All',
                  style: textTheme.labelSmall?.copyWith(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (holidays.isEmpty)
              Padding(
               padding: const EdgeInsets.symmetric(vertical: 24),
               child: Center(
                 child: Text(
                   'No holiday closures scheduled',
                   style: textTheme.bodySmall?.copyWith(color: const Color(0xFF64748b)),
                 ),
               ),
             )
          else
            ...holidays.asMap().entries.map((entry) {
              final index = entry.key;
              final holiday = entry.value;
              final date = holiday['date'] as DateTime;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          children: [
                            Text(
                              DateFormat('MMM').format(date).toUpperCase(),
                              style: textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF64748b),
                                fontWeight: FontWeight.bold,
                                fontSize: 8,
                              ),
                            ),
                            Text(
                              DateFormat('dd').format(date),
                              style: textTheme.titleMedium?.copyWith(
                                color: Colors.black87,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              holiday['name'] ?? 'Holiday',
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              (holiday['type'] ?? 'Fully Closed').toUpperCase(),
                              style: textTheme.labelSmall?.copyWith(
                                color: const Color(0xFFef4444),
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => onEditHoliday(index),
                        icon: const Icon(Icons.edit, color: Color(0xFF475569), size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => onDeleteHoliday(index),
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFef4444), size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          const SizedBox(height: 12),
          InkWell(
            onTap: onAddHoliday,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!, style: BorderStyle.solid, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle, color: Color(0xFF64748b), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'ADD EXCEPTION DATE',
                    style: textTheme.labelSmall?.copyWith(
                      color: Colors.grey,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
