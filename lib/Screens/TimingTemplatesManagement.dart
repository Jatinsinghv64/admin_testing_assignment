import 'package:flutter/material.dart';
import '../models/timing_template.dart';
import '../services/timing_template_service.dart';

class TimingTemplatesManagement extends StatefulWidget {
  const TimingTemplatesManagement({super.key});

  @override
  State<TimingTemplatesManagement> createState() => _TimingTemplatesManagementState();
}

class _TimingTemplatesManagementState extends State<TimingTemplatesManagement> {
  final _service = TimingTemplateService();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('MANAGE TEMPLATES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () => _editTemplate(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('CREATE NEW'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<TimingTemplate>>(
        stream: _service.getTemplates(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final templates = snapshot.data!;

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: templates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final template = templates[index];
              return _buildTemplateCard(template, textTheme);
            },
          );
        },
      ),
    );
  }

  Widget _buildTemplateCard(TimingTemplate template, TextTheme textTheme) {
    IconData icon;
    switch (template.icon) {
      case 'wb_sunny': icon = Icons.wb_sunny; break;
      case 'ac_unit': icon = Icons.ac_unit; break;
      default: icon = Icons.auto_awesome;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.deepPurple),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Customizable weekly schedule with preset shifts',
                  style: textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                onPressed: () => _editTemplate(template),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _confirmDelete(template),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(TimingTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template?'),
        content: Text('Are you sure you want to delete "${template.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteTemplate(template.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Template "${template.name}" deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting template: $e')),
          );
        }
      }
    }
  }

  Future<void> _editTemplate([TimingTemplate? template]) async {
    final result = await showDialog<TimingTemplate>(
      context: context,
      builder: (context) => _TemplateEditDialog(template: template),
    );

    if (result != null) {
      try {
        await _service.saveTemplate(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Template "${result.name}" saved')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving template: $e')),
          );
        }
      }
    }
  }
}

class _TemplateEditDialog extends StatefulWidget {
  final TimingTemplate? template;
  const _TemplateEditDialog({this.template});

  @override
  State<_TemplateEditDialog> createState() => _TemplateEditDialogState();
}

class _TemplateEditDialogState extends State<_TemplateEditDialog> {
  late TextEditingController _nameController;
  late String _selectedIcon;
  late Map<String, dynamic> _workingHours;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.template?.name ?? '');
    _selectedIcon = widget.template?.icon ?? 'auto_awesome';
    _workingHours = widget.template != null 
        ? Map<String, dynamic>.from(widget.template!.workingHours)
        : _createDefaultWorkingHours();
  }

  Map<String, dynamic> _createDefaultWorkingHours() {
    final Map<String, dynamic> hours = {};
    final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    for (var day in days) {
      hours[day] = {
        'isOpen': true,
        'slots': [
          {'open': '09:00', 'close': '22:00', 'staffCount': 4, 'requiredStaff': 4}
        ]
      };
    }
    return hours;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.template == null ? 'CREATE TEMPLATE' : 'EDIT TEMPLATE',
              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 12),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Template Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Select Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildIconOption('auto_awesome', Icons.auto_awesome),
                const SizedBox(width: 12),
                _buildIconOption('wb_sunny', Icons.wb_sunny),
                const SizedBox(width: 12),
                _buildIconOption('ac_unit', Icons.ac_unit),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              'Initial Schedule Note:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const Text(
              'New templates start with standard 09:00-22:00 hours. You can adjust the schedule in the main screen after applying.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_nameController.text.isNotEmpty) {
                        Navigator.pop(context, TimingTemplate(
                          id: widget.template?.id ?? '',
                          name: _nameController.text,
                          icon: _selectedIcon,
                          workingHours: _workingHours,
                          createdAt: widget.template?.createdAt ?? DateTime.now(),
                          updatedAt: DateTime.now(),
                        ));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('SAVE TEMPLATE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconOption(String value, IconData icon) {
    final isSelected = _selectedIcon == value;
    return InkWell(
      onTap: () => setState(() => _selectedIcon = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.deepPurple : Colors.grey[300]!),
        ),
        child: Icon(icon, color: isSelected ? Colors.deepPurple : Colors.grey),
      ),
    );
  }
}
