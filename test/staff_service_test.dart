// test/staff_service_test.dart
// Unit tests for StaffService data payload construction and role-based logic

import 'package:flutter_test/flutter_test.dart';

/// Helper that simulates buildStaffPayload logic from StaffService.addStaff
Map<String, dynamic> buildStaffPayload(Map<String, dynamic> data) {
  return {
    'name': data['name'],
    'email': data['email'],
    'phone': data['phone'] ?? '',
    'role': data['role'],
    'qid': data['qid'] ?? '',
    'passportNumber': data['passportNumber'] ?? '',
    'salary': data['salary'] ?? 0,
    'roleFields': data['roleFields'] ?? {},
    'isActive': true,
    'branchIds': data['branchIds'] ?? [],
    'permissions': data['permissions'] ?? {},
  };
}

/// Helper that simulates buildUpdatePayload logic from StaffService.updateStaff
Map<String, dynamic> buildUpdatePayload(Map<String, dynamic> data) {
  return {
    'name': data['name'],
    'phone': data['phone'] ?? '',
    'role': data['role'],
    'qid': data['qid'] ?? '',
    'passportNumber': data['passportNumber'] ?? '',
    'salary': data['salary'] ?? 0,
    'roleFields': data['roleFields'] ?? {},
    'isActive': data['isActive'],
    'branchIds': data['branchIds'] ?? [],
    'permissions': data['permissions'] ?? {},
  };
}

/// Helper that replicates _todayString() from StaffService
String todayString() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

void main() {
  group('Staff Payload Construction', () {
    test('addStaff payload includes all new fields', () {
      final data = {
        'name': 'John Doe',
        'email': 'john@example.com',
        'phone': '+974555123',
        'role': 'branch_admin',
        'qid': 'QID123456',
        'passportNumber': 'P987654',
        'salary': 5000.0,
        'branchIds': ['branch1'],
      };

      final payload = buildStaffPayload(data);

      expect(payload['name'], 'John Doe');
      expect(payload['email'], 'john@example.com');
      expect(payload['phone'], '+974555123');
      expect(payload['role'], 'branch_admin');
      expect(payload['qid'], 'QID123456');
      expect(payload['passportNumber'], 'P987654');
      expect(payload['salary'], 5000.0);
      expect(payload['roleFields'], {});
      expect(payload['isActive'], true);
      expect(payload['branchIds'], ['branch1']);
    });

    test('addStaff payload defaults for missing optional fields', () {
      final data = {
        'name': 'Jane',
        'email': 'jane@example.com',
        'role': 'server',
      };

      final payload = buildStaffPayload(data);

      expect(payload['phone'], '');
      expect(payload['qid'], '');
      expect(payload['passportNumber'], '');
      expect(payload['salary'], 0);
      expect(payload['roleFields'], {});
      expect(payload['branchIds'], []);
      expect(payload['permissions'], {});
    });

    test('updateStaff payload includes all fields', () {
      final data = {
        'name': 'Updated Name',
        'phone': '+974555999',
        'role': 'manager',
        'qid': 'QID999',
        'passportNumber': 'P111',
        'salary': 8000,
        'roleFields': {},
        'isActive': false,
        'branchIds': ['b1', 'b2'],
        'permissions': {'canViewDashboard': true},
      };

      final payload = buildUpdatePayload(data);

      expect(payload['name'], 'Updated Name');
      expect(payload['qid'], 'QID999');
      expect(payload['passportNumber'], 'P111');
      expect(payload['salary'], 8000);
      expect(payload['isActive'], false);
      expect(payload['branchIds'], ['b1', 'b2']);
    });
  });

  group('Driver Role Fields', () {
    test('driver role includes roleFields with license and vehicle data', () {
      final driverData = {
        'name': 'Ali Driver',
        'email': 'ali@example.com',
        'role': 'driver',
        'roleFields': {
          'licenseNumber': 'DL-12345',
          'vehicleType': 'car',
          'vehiclePlateNumber': 'Q-1234',
        },
        'branchIds': ['branch1'],
      };

      final payload = buildStaffPayload(driverData);

      expect(payload['role'], 'driver');
      expect(payload['roleFields'], isA<Map>());
      expect(payload['roleFields']['licenseNumber'], 'DL-12345');
      expect(payload['roleFields']['vehicleType'], 'car');
      expect(payload['roleFields']['vehiclePlateNumber'], 'Q-1234');
    });

    test('non-driver role has empty roleFields', () {
      final data = {
        'name': 'Manager Mike',
        'email': 'mike@example.com',
        'role': 'manager',
        'roleFields': {},
      };

      final payload = buildStaffPayload(data);

      expect(payload['role'], 'manager');
      expect(payload['roleFields'], isEmpty);
    });

    test('roleFields defaults to empty map when not provided', () {
      final data = {
        'name': 'No Fields',
        'email': 'no@example.com',
        'role': 'server',
      };

      final payload = buildStaffPayload(data);
      expect(payload['roleFields'], {});
    });

    test('driver roleFields can include bike vehicle type', () {
      final driverData = {
        'name': 'Bike Rider',
        'email': 'bike@example.com',
        'role': 'driver',
        'roleFields': {
          'licenseNumber': 'BIKE-999',
          'vehicleType': 'bike',
          'vehiclePlateNumber': 'B-5678',
        },
      };

      final payload = buildStaffPayload(driverData);
      expect(payload['roleFields']['vehicleType'], 'bike');
    });

    test('driver roleFields can include van vehicle type', () {
      final driverData = {
        'name': 'Van Driver',
        'email': 'van@example.com',
        'role': 'driver',
        'roleFields': {
          'licenseNumber': 'VAN-111',
          'vehicleType': 'van',
          'vehiclePlateNumber': 'V-9012',
        },
      };

      final payload = buildStaffPayload(driverData);
      expect(payload['roleFields']['vehicleType'], 'van');
    });
  });

  group('Date Formatting', () {
    test('todayString returns YYYY-MM-DD format', () {
      final today = todayString();
      // Should match pattern: YYYY-MM-DD
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(today), true);
    });

    test('todayString pads single-digit months and days', () {
      final today = todayString();
      final parts = today.split('-');
      expect(parts.length, 3);
      expect(parts[1].length, 2);  // Month is zero-padded
      expect(parts[2].length, 2);  // Day is zero-padded
    });
  });

  group('Salary Validation', () {
    test('salary defaults to 0 when not provided', () {
      final payload = buildStaffPayload({
        'name': 'Test',
        'email': 'test@test.com',
        'role': 'server',
      });
      expect(payload['salary'], 0);
    });

    test('salary accepts decimal values', () {
      final payload = buildStaffPayload({
        'name': 'Test',
        'email': 'test@test.com',
        'role': 'server',
        'salary': 5500.50,
      });
      expect(payload['salary'], 5500.50);
    });

    test('salary accepts integer values', () {
      final payload = buildStaffPayload({
        'name': 'Test',
        'email': 'test@test.com',
        'role': 'server',
        'salary': 3000,
      });
      expect(payload['salary'], 3000);
    });
  });
}
