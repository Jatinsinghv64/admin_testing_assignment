import 'package:flutter/material.dart';

/// Shared CancellationReasonDialog widget
/// 
/// Usage for order cancellation:
/// ```dart
/// final reason = await showDialog<String>(
///   context: context,
///   builder: (context) => const CancellationReasonDialog(),
/// );
/// if (reason != null && reason.trim().isNotEmpty) {
///   // Proceed with cancellation using the reason
/// }
/// ```
/// 
/// Can also be used for refunds:
/// ```dart
/// final reason = await showDialog<String>(
///   context: context,
///   builder: (context) => const CancellationReasonDialog(
///     title: 'Refund Order?',
///     confirmText: 'Confirm Refund',
///     reasons: CancellationReasons.refundReasons,
///   ),
/// );
/// ```

/// Standard cancellation reasons for orders
class CancellationReasons {
  CancellationReasons._(); // Prevent instantiation

  static const List<String> orderReasons = [
    'Customer Request',
    'Out of Stock',
    'Kitchen Busy / Closed',
    'Duplicate Order',
    'Payment Issue',
    'Delivery Issue',
    'Other',
  ];

  static const List<String> refundReasons = [
    'Customer Request',
    'Order Delayed',
    'Wrong Order',
    'Food Quality Issue',
    'Delivery Issue',
    'Other',
  ];

  static const List<String> riderRejectReasons = [
    'Too Far Away',
    'Vehicle Issue',
    'Already Busy',
    'Restaurant Closed',
    'Other',
  ];
}

/// A dialog for selecting a cancellation (or refund) reason
/// 
/// Returns the selected reason as a String, or null if cancelled
class CancellationReasonDialog extends StatefulWidget {
  /// Title shown at the top of the dialog
  final String title;

  /// Text for the confirm button
  final String confirmText;

  /// Text for the cancel button  
  final String cancelText;

  /// List of predefined reasons to choose from
  /// Defaults to [CancellationReasons.orderReasons]
  final List<String> reasons;

  /// Color theme for the dialog (defaults to red)
  final Color themeColor;

  const CancellationReasonDialog({
    super.key,
    this.title = 'Cancel Order?',
    this.confirmText = 'Confirm Cancel',
    this.cancelText = 'Keep Order',
    this.reasons = const [
      'Customer Request',
      'Out of Stock',
      'Kitchen Busy / Closed',
      'Duplicate Order',
      'Other',
    ],
    this.themeColor = Colors.red,
  });

  @override
  State<CancellationReasonDialog> createState() =>
      _CancellationReasonDialogState();
}

class _CancellationReasonDialogState extends State<CancellationReasonDialog> {
  String? _selectedReason;
  final TextEditingController _otherReasonController = TextEditingController();
  final FocusNode _otherFocusNode = FocusNode();

  @override
  void dispose() {
    _otherReasonController.dispose();
    _otherFocusNode.dispose();
    super.dispose();
  }

  void _onReasonSelected(String? value) {
    setState(() {
      _selectedReason = value;
    });

    if (value == 'Other') {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) FocusScope.of(context).requestFocus(_otherFocusNode);
      });
    } else {
      _otherFocusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOther = _selectedReason == 'Other';
    final bool isValid = _selectedReason != null &&
        (!isOther || _otherReasonController.text.trim().isNotEmpty);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 5,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: widget.themeColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, 
                       color: widget.themeColor.withOpacity(0.8)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor.withOpacity(0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Reason List
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Please select a reason:",
                      style: TextStyle(
                        fontWeight: FontWeight.w500, 
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...widget.reasons.map((reason) {
                      final bool isSelected = _selectedReason == reason;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: InkWell(
                          onTap: () => _onReasonSelected(reason),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected
                                    ? widget.themeColor
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: isSelected
                                  ? widget.themeColor.withOpacity(0.1)
                                  : Colors.white,
                            ),
                            child: RadioListTile<String>(
                              title: Text(
                                reason,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? widget.themeColor.withOpacity(0.9)
                                      : Colors.black87,
                                ),
                              ),
                              value: reason,
                              groupValue: _selectedReason,
                              onChanged: _onReasonSelected,
                              activeColor: widget.themeColor,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    
                    // "Other" text field
                    AnimatedCrossFade(
                      firstChild: const SizedBox(width: double.infinity, height: 0),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                        child: TextField(
                          controller: _otherReasonController,
                          focusNode: _otherFocusNode,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Specify reason...',
                            hintText: 'e.g. Customer changed mind',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: widget.themeColor, 
                                width: 2,
                              ),
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ),
                      crossFadeState: isOther
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                  ],
                ),
              ),
            ),
            
            const Divider(height: 1),
            
            // Action Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: Colors.grey.shade700,
                      ),
                      child: Text(widget.cancelText),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isValid
                          ? () {
                              String finalReason = _selectedReason!;
                              if (finalReason == 'Other') {
                                finalReason = _otherReasonController.text.trim();
                              }
                              Navigator.of(context).pop(finalReason);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        disabledBackgroundColor: widget.themeColor.withOpacity(0.3),
                      ),
                      child: Text(widget.confirmText),
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
