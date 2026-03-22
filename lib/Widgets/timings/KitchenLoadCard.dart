import 'package:flutter/material.dart';

class KitchenLoadCard extends StatelessWidget {
  final int preparationTime;
  final ValueChanged<int> onPreparationTimeChanged;
  final bool isUpdatingPrepTime;
  final bool rushModeOverride;
  final ValueChanged<bool> onRushModeChanged;
  final List<Map<String, dynamic>> throttleRules;
  final VoidCallback onAddRule;
  final ValueChanged<int> onDeleteRule;

  const KitchenLoadCard({
    super.key,
    required this.preparationTime,
    required this.onPreparationTimeChanged,
    required this.isUpdatingPrepTime,
    required this.rushModeOverride,
    required this.onRushModeChanged,
    required this.throttleRules,
    required this.onAddRule,
    required this.onDeleteRule,
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
            blurRadius: 12,
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
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_fire_department,
                      color: Colors.deepPurple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Kitchen Load',
                    style: textTheme.titleMedium?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.deepPurple,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LIVE SYNC ON',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Preparation Buffer
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preparation Buffer',
                        style: textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF94a3b8),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Extra time per order',
                        style: textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748b),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '+$preparationTime',
                          style: textTheme.headlineSmall?.copyWith(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        TextSpan(
                          text: ' min',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.deepPurple,
                  inactiveTrackColor: Colors.grey[200],
                  thumbColor: Colors.deepPurple,
                  overlayColor: Colors.deepPurple.withOpacity(0.2),
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: preparationTime.toDouble(),
                  min: 0,
                  max: 60,
                  onChanged: (v) => onPreparationTimeChanged(v.round()),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('0m', style: textTheme.labelSmall?.copyWith(color: const Color(0xFF64748b), fontWeight: FontWeight.w900)),
                   Text('30m', style: textTheme.labelSmall?.copyWith(color: const Color(0xFF64748b), fontWeight: FontWeight.w900)),
                   Text('60m', style: textTheme.labelSmall?.copyWith(color: const Color(0xFF64748b), fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Auto-Throttle Rules
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AUTO-THROTTLE RULES',
                      style: textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF94a3b8),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    TextButton(
                      onPressed: onAddRule,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Add Rule',
                        style: textTheme.labelSmall?.copyWith(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...throttleRules.asMap().entries.map((entry) {
                  final index = entry.key;
                  final rule = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'If orders > ',
                                style: textTheme.labelSmall?.copyWith(color: const Color(0xFF94a3b8)),
                              ),
                                Text(
                                  '${rule['orderCount']}',
                                  style: textTheme.labelSmall?.copyWith(color: Colors.black87, fontWeight: FontWeight.bold),
                                ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, color: const Color(0xFF64748b), size: 10),
                              const SizedBox(width: 8),
                                Text(
                                  '+${rule['extraTime']} min',
                                  style: textTheme.labelSmall?.copyWith(color: Colors.deepPurple, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => onDeleteRule(index),
                            child: const Icon(Icons.close, color: const Color(0xFF64748b), size: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Rush Mode Override
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rush Mode Override',
                      style: textTheme.titleSmall?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Increases delivery ETA globally',
                      style: textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF64748b),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: rushModeOverride,
                  onChanged: onRushModeChanged,
                  activeColor: Colors.deepPurple,
                  activeTrackColor: Colors.deepPurple.withOpacity(0.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
