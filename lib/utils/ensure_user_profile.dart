// lib/utils/ensure_user_profile.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> ensureUserProfile() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return;
  final ref = FirebaseFirestore.instance.collection('users').doc(u.uid);
  final snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      'displayName': u.displayName ?? 'User',
      'avatarKey': null,          // will be set from Avatar Picker
      'photoURL': u.photoURL,     // if you ever allow network avatars
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  } else {
    await ref.set({
      'displayName': u.displayName ?? snap.data()?['displayName'] ?? 'User',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
