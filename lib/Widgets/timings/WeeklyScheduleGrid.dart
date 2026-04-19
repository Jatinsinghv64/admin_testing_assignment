import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WeeklyScheduleGrid extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>>
      schedule; // Day -> List of shifts
  final Map<String, bool> dayStatus; // Day -> IsOpen
  final ValueChanged<String> onAddShift; // Day
  final Function(String, int) onDeleteShift; // Day, index
  final Function(String, int, Map<String, dynamic>)
      onUpdateShift; // Day, index, data
  final Function(String, bool) onToggleDay; // Day, isOpen

  const WeeklyScheduleGrid({
    super.key,
    required this.schedule,
    required this.dayStatus,
    required this.onAddShift,
    required this.onDeleteShift,
    required this.onUpdateShift,
    required this.onToggleDay,
  });

  @override
  Widget build(BuildContext context) {
    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];

    return Container(
      width: double.infinity, // Ensure it fills available width
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
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
          _buildHeader(context),
          _buildGridHeader(context),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: Theme.of(context).dividerColor),
            itemBuilder: (context, index) => _buildDayRow(context, days[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.calendar_today,
                    color: Theme.of(context).primaryColor, size: 20),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WEEKLY SCHEDULE',
                    style: textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Define operational shifts and staffing',
                    style: textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              _buildLegendItem(context, 'STAFFED', Colors.deepPurple),
              const SizedBox(width: 16),
              _buildLegendItem(
                  context, 'UNDERSTAFFED', const Color(0xFFef4444)),
              const SizedBox(width: 16),
              _buildLegendItem(context, 'OVERLAP', const Color(0xFFf59e0b)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
        ),
      ],
    );
  }

  Widget _buildGridHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.grey,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey[50],
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('DAY', style: style)),
          Expanded(flex: 2, child: Center(child: Text('STATUS', style: style))),
          Expanded(
              flex: 10,
              child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text('ACTIVE SHIFTS & STAFFING', style: style))),
          Expanded(
              flex: 2,
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('ACTION', style: style))),
        ],
      ),
    );
  }

  Widget _buildDayRow(BuildContext context, String day) {
    final isOpen = dayStatus[day] ?? true;
    final shifts = schedule[day] ?? [];
    final isToday = DateFormat('EEEE').format(DateTime.now()) == day;
    final isClosed = !isOpen;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: isToday
            ? Colors.deepPurple.withOpacity(0.05)
            : (isClosed ? Colors.red.withOpacity(0.05) : Colors.transparent),
        border: isToday
            ? const Border(left: BorderSide(color: Colors.deepPurple, width: 4))
            : (isClosed
                ? Border(
                    left: BorderSide(
                        color: Colors.red.withOpacity(0.5), width: 4))
                : null),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  day,
                  style: textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (isToday)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      'TODAY',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Switch(
                value: isOpen,
                onChanged: (val) => onToggleDay(day, val),
                activeColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: !isOpen
                  ? _buildClosedMessage(context)
                  : Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...shifts
                            .asMap()
                            .entries
                            .map((entry) => _buildShiftBadge(
                                context, day, entry.key, entry.value))
                            .toList(),
                        _buildAddButton(context, day),
                      ],
                    ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () {},
                icon: Icon(Icons.settings_backup_restore,
                    color: Theme.of(context).hintColor, size: 18),
                tooltip: 'Reset to default',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosedMessage(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.do_not_disturb_on, color: Colors.red, size: 16),
        const SizedBox(width: 8),
        Text(
          'RESTAURANT FULLY CLOSED',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.red[700],
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
        ),
      ],
    );
  }

  Widget _buildShiftBadge(
      BuildContext context, String day, int index, Map<String, dynamic> shift) {
    final startTime = shift['startTime'] as String;
    final endTime = shift['endTime'] as String;
    final staffCount = shift['staffCount'] as int? ?? 0;
    final requiredStaff = shift['requiredStaff'] as int? ?? 4;
    final isUnderstaffed = staffCount < requiredStaff;
    final hasConflict = shift['hasConflict'] as bool? ?? false;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnderstaffed
                  ? Colors.red.withOpacity(0.5)
                  : (hasConflict
                      ? Colors.orange.withOpacity(0.5)
                      : Theme.of(context).dividerColor),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => onUpdateShift(day, index, shift),
                child: _buildTimeField(context, 'FROM', startTime),
              ),
              Container(
                  width: 1,
                  height: 16,
                  color: Theme.of(context).dividerColor,
                  margin: const EdgeInsets.symmetric(horizontal: 8)),
              InkWell(
                onTap: () => onUpdateShift(day, index, shift),
                child: _buildTimeField(context, 'TO', endTime),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => onUpdateShift(day, index, shift),
                child: _buildStaffingBadge(
                    context, staffCount, requiredStaff, isUnderstaffed),
              ),
              IconButton(
                onPressed: () => onDeleteShift(day, index),
                icon: const Icon(Icons.close, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        if (isUnderstaffed || hasConflict)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child:
                  const Icon(Icons.priority_high, color: Colors.white, size: 8),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeField(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.bold,
              fontSize: 8),
        ),
        Text(
          value,
          style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildStaffingBadge(
      BuildContext context, int count, int required, bool isUnderstaffed) {
    final color = isUnderstaffed ? Colors.red : Colors.deepPurple;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(isUnderstaffed ? Icons.group_off : Icons.badge,
              color: color, size: 10),
          const SizedBox(width: 4),
          Text(
            '${count.toString().padLeft(2, '0')}/${required.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, String day) {
    return InkWell(
      onTap: () => onAddShift(day),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context).dividerColor, style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, color: Theme.of(context).hintColor, size: 16),
            const SizedBox(width: 8),
            Text(
              'ADD SHIFT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
