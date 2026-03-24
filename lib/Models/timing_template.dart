import 'package:cloud_firestore/cloud_firestore.dart';

class TimingTemplate {
  final String id;
  final String name;
  final String icon;
  final Map<String, dynamic> workingHours;
  final DateTime createdAt;
  final DateTime updatedAt;

  TimingTemplate({
    required this.id,
    required this.name,
    this.icon = 'auto_awesome',
    required this.workingHours,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TimingTemplate.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TimingTemplate(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed Template',
      icon: data['icon'] as String? ?? 'auto_awesome',
      workingHours: Map<String, dynamic>.from(data['workingHours'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'icon': icon,
      'workingHours': workingHours,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  TimingTemplate copyWith({
    String? id,
    String? name,
    String? icon,
    Map<String, dynamic>? workingHours,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TimingTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      workingHours: workingHours ?? this.workingHours,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
