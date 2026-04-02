import 'package:flutter/material.dart';

Future<bool> showSupplierImportFormatDialog(BuildContext context) async {
  final shouldContinue = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Import Suppliers'),
      content: SizedBox(
        width: 460,
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
                'Required header',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                  'Use one of: `company_name`, `company`, `supplier_name`, or `name`.'),
              SizedBox(height: 16),
              Text(
                'Optional headers',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                '`contact_person`, `phone`, `email`, `address`, `payment_terms`, `notes`, `supplier_categories`, `rating`, `is_active`',
              ),
              SizedBox(height: 16),
              Text(
                'Format notes',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text('The first row must contain headers.'),
              Text('Use one supplier per row.'),
              Text('For multiple categories, separate values with commas.'),
              Text(
                  'Accepted active values: `true/false`, `yes/no`, `active/inactive`, or `1/0`.'),
              SizedBox(height: 16),
              Text(
                'Example',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              SelectableText(
                'company_name,contact_person,phone,email,payment_terms,supplier_categories,is_active\n'
                'Fresh Foods,Ali,12345678,ali@example.com,Net 30,"Produce,Dairy",true',
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
