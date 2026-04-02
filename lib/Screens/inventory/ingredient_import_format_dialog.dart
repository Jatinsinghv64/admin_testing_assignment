import 'package:flutter/material.dart';

Future<bool> showIngredientImportFormatDialog(BuildContext context) async {
  final shouldContinue = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Bulk Upload Ingredients'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Accepted file types',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text('CSV: `.csv`'),
              Text('Excel: `.xlsx` or `.xls`'),
              SizedBox(height: 16),
              Text(
                'Required headers',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text('Use `name` and either `cost` or `cost_per_unit`.'),
              SizedBox(height: 16),
              Text(
                'Optional headers',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                '`category`, `unit`, `sku`, `barcode`, `stock`, `min_stock`',
              ),
              SizedBox(height: 16),
              Text(
                'Accepted values',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text('Categories: `produce`, `dairy`, `meat`, `spices`, `dry_goods`, `beverages`, `other`'),
              Text('Units: `kg`, `g`, `L`, `mL`, `pieces`, `dozen`, `bunch`'),
              SizedBox(height: 16),
              Text(
                'Format notes',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text('The first row must contain headers.'),
              Text('Each row should represent one ingredient.'),
              Text('Existing ingredients are matched by SKU, then barcode, then name.'),
              Text('If `stock` or `min_stock` is present, the selected branch values will be updated.'),
              SizedBox(height: 16),
              Text(
                'Example',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              SelectableText(
                'name,cost,category,unit,sku,barcode,stock,min_stock\n'
                'Tomato,4.5,produce,kg,ING-001,1234567890,12,4',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Choose File'),
        ),
      ],
    ),
  );

  return shouldContinue == true;
}
