import os

path = 'lib/Screens/AnalyticsScreen.dart'
with open(path, 'r') as f:
    content = f.read()

start_marker = '  Future<void> _showExportDialog(BuildContext context) async {'
end_marker = '}\n\nclass SalesData {'

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print("Could not find markers.")
    exit(1)

old_methods = content[start_idx:end_idx]

# Remove from AnalyticsScreen.dart
new_content = content[:start_idx] + content[end_idx:]

# Find formatOrderTypeForPieLabel
format_start = new_content.find('  String _formatOrderTypeForPieLabel(String')
format_end = new_content.find('\n  }\n', format_start) + 4
format_func = new_content[format_start:format_end].strip()

# Make it public in AnalyticsScreen so we don't break existing references
new_content = new_content.replace('String _formatOrderTypeForPieLabel', 'String formatOrderTypeForPieLabel')
new_content = new_content.replace('_formatOrderTypeForPieLabel', 'formatOrderTypeForPieLabel')
new_content = new_content.replace('onPressed: () => _showExportDialog(context),', 'onPressed: () => ExportReportUtil.showExportDialog(context, _dateRange, _selectedOrderType),')

# Add import to AnalyticsScreen
import_statement = "import '../utils/ExportReportUtil.dart';\n"
if "import '../utils/ExportReportUtil.dart';" not in new_content:
    import_idx = new_content.find('import ')
    new_content = new_content[:import_idx] + import_statement + new_content[import_idx:]

with open(path, 'w') as f:
    f.write(new_content)

# Update extracted methods
extracted = old_methods
extracted = extracted.replace('if (mounted)', 'if (context.mounted)')
extracted = extracted.replace('_formatOrderTypeForPieLabel', 'formatOrderTypeForPieLabel')

extracted = extracted.replace('  Future<void> _showExportDialog(BuildContext context) async {', '  static Future<void> showExportDialog(BuildContext context, DateTimeRange initialDateRange, String initialOrderType) async {')
extracted = extracted.replace('    DateTimeRange reportDateRange = _dateRange;', '    DateTimeRange reportDateRange = initialDateRange;')
extracted = extracted.replace('    String reportOrderType = _selectedOrderType;', '    String reportOrderType = initialOrderType;')
extracted = extracted.replace('onPressed: () => _showExportDialog(context)', 'onPressed: () => showExportDialog(context, initialDateRange, initialOrderType)')

# Add BuildContext to generate methods
extracted = extracted.replace('  Future<void> _generatePdfReportWithParams(', '  static Future<void> _generatePdfReportWithParams(BuildContext context, ')
extracted = extracted.replace('  Future<void> _generateExcelReportWithParams(', '  static Future<void> _generateExcelReportWithParams(BuildContext context, ')
extracted = extracted.replace('_generatePdfReportWithParams(\n                        reportDateRange, reportOrderType)', '_generatePdfReportWithParams(context, reportDateRange, reportOrderType)')
extracted = extracted.replace('_generateExcelReportWithParams(\n                        reportDateRange, reportOrderType)', '_generateExcelReportWithParams(context, reportDateRange, reportOrderType)')
extracted = extracted.replace('_generatePdfReportWithParams(reportDateRange, reportOrderType)', '_generatePdfReportWithParams(context, reportDateRange, reportOrderType)')
extracted = extracted.replace('_generateExcelReportWithParams(reportDateRange, reportOrderType)', '_generateExcelReportWithParams(context, reportDateRange, reportOrderType)')

# Fix Widget method
extracted = extracted.replace('  Widget _buildOrderTypeChip(', '  static Widget _buildOrderTypeChip(')

util_class = f"""import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../services/AnalyticsPdfService.dart';
import '../Widgets/BranchFilterService.dart';
import '../main.dart';
import '../constants.dart';

class ExportReportUtil {{
  static {format_func.replace('String _formatOrderTypeForPieLabel', 'String formatOrderTypeForPieLabel')}

{extracted}
}}
"""

os.makedirs('lib/utils', exist_ok=True)
with open('lib/utils/ExportReportUtil.dart', 'w') as f:
    f.write(util_class)

print("Extraction complete.")
