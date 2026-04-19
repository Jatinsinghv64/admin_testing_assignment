// lib/Screens/pos/PosProductTile.dart
// Reusable product card for the POS grid

import 'package:flutter/material.dart';

class PosProductTile extends StatelessWidget {
  final String name;
  final double price;
  final String? imageUrl;
  final bool isAvailable;
  final bool disableTapWhenUnavailable;
  final String unavailableLabel;
  final Color? chinColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PosProductTile({
    super.key,
    required this.name,
    required this.price,
    this.imageUrl,
    this.isAvailable = true,
    this.disableTapWhenUnavailable = true,
    this.unavailableLabel = 'Unavailable',
    this.chinColor,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isAvailable && onLongPress != null ? 'Hold for bulk order' : '',
      waitDuration: const Duration(seconds: 1),
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (isAvailable || !disableTapWhenUnavailable) ? onTap : null,
        onLongPress: isAvailable ? onLongPress : null,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isAvailable
                ? Theme.of(context).cardColor
                : Theme.of(context).disabledColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAvailable
                  ? Theme.of(context).dividerColor.withOpacity(0.15)
                  : Theme.of(context).dividerColor.withOpacity(0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        alignment: Alignment.center,
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isAvailable
                                ? Theme.of(context).textTheme.bodyLarge?.color
                                : Theme.of(context).disabledColor,
                            height: 1.25,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Category Chin Color
              if (chinColor != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    color: isAvailable
                        ? chinColor
                        : chinColor!.withValues(alpha: 0.3),
                  ),
                ),
              // Unavailable overlay
              if (!isAvailable)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          unavailableLabel,
                          style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Theme.of(context).cardColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
