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

# Extract functions
old_methods = content[start_idx:end_idx]

# Remove them from class
new_content = content[:start_idx] + content[end_idx:]

# Also find _formatOrderTypeForPieLabel and make it public
format_start = new_content.find('  String _formatOrderTypeForPieLabel(String')
if format_start != -1:
    format_end = new_content.find('\n  }\n', format_start) + 4
    format_func = new_content[format_start:format_end].strip()
    
    # Replace in func body
    format_func_public = format_func.replace('String _formatOrderTypeForPieLabel', 'String formatOrderTypeForPieLabel')
    
    # Replace calls inside AnalyticsScreen
    new_content = new_content.replace('_formatOrderTypeForPieLabel', 'formatOrderTypeForPieLabel')
else:
    format_func_public = ""

# Make the dialog and generate methods public and use context.mounted instead of mounted
extracted = old_methods.replace('  Future<void> _showExportDialog(BuildContext context) async {', 'Future<void> showAnalyticsExportDialog(BuildContext context, DateTimeRange reportDateRange, String reportOrderType) async {')
extracted = extracted.replace('    DateTimeRange reportDateRange = _dateRange;\n', '')
extracted = extracted.replace('    String reportOrderType = _selectedOrderType;\n', '')
extracted = extracted.replace('if (mounted)', 'if (context.mounted)')
extracted = extracted.replace('_formatOrderTypeForPieLabel', 'formatOrderTypeForPieLabel')
extracted = extracted.replace('onPressed: () => _showExportDialog(context)', 'onPressed: () => showAnalyticsExportDialog(context, _dateRange, _selectedOrderType)')

# Unindent 2 spaces
lines = extracted.split('\n')
unindented = [line[2:] if line.startswith('  ') else line for line in lines]
extracted = '\n'.join(unindented)

# Update the onPressed for Dashboard button wait, Dashboard button isn't in this file.
# Update the call inside AnalyticsScreen itself:
new_content = new_content.replace('onPressed: () => _showExportDialog(context),', 'onPressed: () => showAnalyticsExportDialog(context, _dateRange, _selectedOrderType),')

# Append format func and extracted to the end, right before classes
final_content = new_content.replace('class SalesData {', format_func_public + '\n\n' + extracted + '\n\nclass SalesData {')

with open(path, 'w') as f:
    f.write(final_content)

print("Extraction complete.")
