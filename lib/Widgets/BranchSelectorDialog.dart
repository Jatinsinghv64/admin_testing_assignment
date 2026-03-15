import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BranchSelectorDialog extends StatefulWidget {
  final List<String> initialSelectedBranchIds;
  final Function(List<String>)? onSelectionChanged;
  final bool isMultiSelect;

  const BranchSelectorDialog({
    super.key,
    required this.initialSelectedBranchIds,
    this.onSelectionChanged,
    this.isMultiSelect = true,
  });

  @override
  State<BranchSelectorDialog> createState() => _BranchSelectorDialogState();
}

class _BranchSelectorDialogState extends State<BranchSelectorDialog> {
  List<String> _selectedIds = [];
  Map<String, String> _allBranches = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.initialSelectedBranchIds);
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Branch').get();
      final branches = {
        for (var doc in snapshot.docs)
          doc.id: doc.data()['name'] as String? ?? doc.id
      };
      if (mounted) {
        setState(() {
          _allBranches = branches;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isMultiSelect ? 'Select Branches' : 'Select Branch'),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (widget.isMultiSelect) ...[
                    CheckboxListTile(
                      title: const Text('Select All', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: _selectedIds.length == _allBranches.length && _allBranches.isNotEmpty,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedIds = _allBranches.keys.toList();
                          } else {
                            _selectedIds = [];
                          }
                        });
                      },
                    ),
                    const Divider(),
                  ],
                  ..._allBranches.entries.map((e) {
                    if (widget.isMultiSelect) {
                      return CheckboxListTile(
                        title: Text(e.value),
                        value: _selectedIds.contains(e.key),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedIds.add(e.key);
                            } else {
                              _selectedIds.remove(e.key);
                            }
                          });
                        },
                      );
                    } else {
                      return RadioListTile<String>(
                        title: Text(e.value),
                        value: e.key,
                        groupValue: _selectedIds.isNotEmpty ? _selectedIds.first : null,
                        onChanged: (val) {
                          setState(() {
                            if (val != null) {
                              _selectedIds = [val];
                            }
                          });
                        },
                      );
                    }
                  }).toList(),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (widget.onSelectionChanged != null) {
              widget.onSelectionChanged!(_selectedIds);
            }
            Navigator.pop(context, _selectedIds);
          },
          child: const Text('Select'),
        ),
      ],
    );
  }
}
