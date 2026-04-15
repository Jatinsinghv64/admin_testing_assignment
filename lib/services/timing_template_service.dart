import 'package:cloud_firestore/cloud_firestore.dart';
import '../Models/timing_template.dart';
import '../constants.dart';

class TimingTemplateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(AppConstants.collectionTimingTemplates);

  Stream<List<TimingTemplate>> getTemplates() {
    return _collection.orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => TimingTemplate.fromFirestore(doc)).toList();
    });
  }

  Future<void> saveTemplate(TimingTemplate template) async {
    final data = template.toFirestore();
    data['updatedAt'] = FieldValue.serverTimestamp();
    
    if (template.id.isEmpty) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await _collection.add(data);
    } else {
      await _collection.doc(template.id).update(data);
    }
  }

  Future<void> deleteTemplate(String id) async {
    await _collection.doc(id).delete();
  }

  /// Initial seeding of default templates if collection is empty
  Future<void> seedDefaultTemplates() async {
    try {
      final snapshot = await _collection.limit(1).get();
      if (snapshot.docs.isNotEmpty) return;

      final batch = _firestore.batch();
      
      final standardSlots = [
        {'open': '09:00', 'close': '22:00', 'staffCount': 4, 'requiredStaff': 4}
      ];
      final weekendSlots = [
        {'open': '09:00', 'close': '23:59', 'staffCount': 6, 'requiredStaff': 6}
      ];
      final holidaySlots = [
        {'open': '10:00', 'close': '18:00', 'staffCount': 3, 'requiredStaff': 3}
      ];

      final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

      // Helper to create template data
      Map<String, dynamic> _createTemplateData(String name, String icon, Map<String, dynamic> hours) {
        return {
          'name': name,
          'icon': icon,
          'workingHours': hours,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      }

      // Standard Ops
      final Map<String, dynamic> standardHours = {};
      for (var day in days) standardHours[day] = {'isOpen': true, 'slots': standardSlots};
      batch.set(_collection.doc('default_standard'), _createTemplateData('Standard Ops', 'auto_awesome', standardHours));

      // Extended Weekend
      final Map<String, dynamic> weekendHours = {};
      for (var day in days) {
        if (day == 'friday' || day == 'saturday') {
          weekendHours[day] = {'isOpen': true, 'slots': weekendSlots};
        } else {
          weekendHours[day] = {'isOpen': true, 'slots': standardSlots};
        }
      }
      batch.set(_collection.doc('default_weekend'), _createTemplateData('Extended Weekend', 'wb_sunny', weekendHours));

      // Holiday Minimal
      final Map<String, dynamic> holidayHours = {};
      for (var day in days) holidayHours[day] = {'isOpen': true, 'slots': holidaySlots};
      batch.set(_collection.doc('default_holiday'), _createTemplateData('Holiday Minimal', 'ac_unit', holidayHours));

      await batch.commit();
    } catch (e) {
      print('Error seeding templates: $e');
    }
  }
}
