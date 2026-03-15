import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'lib/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  
  final snapshot = await FirebaseFirestore.instance
      .collection(AppConstants.collectionOrders)
      .where('status', isEqualTo: AppConstants.statusServed)
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
      .limit(10)
      .get();
      
  print('Found ${snapshot.docs.length} served orders for today.');
  for (var doc in snapshot.docs) {
    print('Order ${doc.id}: status=${doc.data()['status']}, timestamp=${doc.data()['timestamp']?.toDate()}');
  }
}
