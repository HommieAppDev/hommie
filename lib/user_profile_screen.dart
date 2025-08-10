import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/asset_paths.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final uid = args['uid'] as String;
    final me = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (_, snap) {
          final data = snap.data?.data();
          final name = data?['displayName'] ?? data?['name'] ?? 'User';
          final avatarKeyOrUrl = data?['avatarKey'] ?? data?['avatarUrl'] ?? data?['photoURL'];
          final bio = data?['bio'] ?? '';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundImage: avatarOptions.containsKey(avatarKeyOrUrl)
                      ? AssetImage(avatarOptions[avatarKeyOrUrl]!)
                      : (avatarKeyOrUrl != null && avatarKeyOrUrl.toString().startsWith('http'))
                          ? NetworkImage(avatarKeyOrUrl)
                          : AssetImage(defaultAvatar) as ImageProvider,
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              if (bio.isNotEmpty) Center(child: Text(bio, textAlign: TextAlign.center)),
              const SizedBox(height: 16),
              if (me != null && me != uid)
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/chat', arguments: {
                    'threadId': ([me, uid]..sort()).join('_'),
                    'otherUid': uid,
                  }),
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Message'),
                ),
            ],
          );
        },
      ),
    );
  }
}
