import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Widgets/BranchFilterService.dart';
import '../main.dart'; // UserScopeService

class BranchFilterSelector extends StatelessWidget {
  final Color? color;
  final bool showLabel;
  final EdgeInsetsGeometry padding;

  const BranchFilterSelector({
    super.key,
    this.color,
    this.showLabel = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final userScope = context.watch<UserScopeService>();
    final branchFilter = context.watch<BranchFilterService>();
    final theme = Theme.of(context);
    final primaryColor = color ?? theme.primaryColor;

    final showSelector = userScope.isSuperAdmin && userScope.branchIds.length > 1;

    if (!showSelector) return const SizedBox.shrink();

    // Ensure branch names are loaded
    branchFilter.loadBranchNames(userScope.branchIds);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 45),
        tooltip: 'Select Branch',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: primaryColor.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store, size: 16, color: primaryColor),
              if (showLabel) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    branchFilter.selectedBranchId == null
                        ? 'All Branches'
                        : branchFilter.getBranchName(branchFilter.selectedBranchId!),
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: primaryColor, size: 18),
            ],
          ),
        ),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: BranchFilterService.allBranchesValue,
            child: Row(
              children: [
                Icon(
                  branchFilter.selectedBranchId == null
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                  color: branchFilter.selectedBranchId == null
                      ? primaryColor
                      : Colors.grey,
                ),
                const SizedBox(width: 10),
                const Text('All Branches', style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const PopupMenuDivider(),
          ...userScope.branchIds.map((branchId) => PopupMenuItem<String>(
                value: branchId,
                child: Row(
                  children: [
                    Icon(
                      branchFilter.selectedBranchId == branchId
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 18,
                      color: branchFilter.selectedBranchId == branchId
                          ? primaryColor
                          : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        branchFilter.getBranchName(branchId),
                        style: TextStyle(
                          fontWeight: branchFilter.selectedBranchId == branchId
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
        onSelected: (value) {
          branchFilter.selectBranch(value);
        },
      ),
    );
  }
}
