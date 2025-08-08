// profile_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'avatar_picker_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? avatarPath;
  String displayName = 'Guest';

  final String devUserId = 'your-firebase-uid-here'; // Replace with your UID

  bool get isDevUser => FirebaseAuth.instance.currentUser?.uid == devUserId;

  String get displayAvatarPath {
    if (isDevUser) return 'assets/avatars/founder.png';
    return avatarPath ?? 'assets/avatars/default_avatar.png';
  }

  String get badgeLabel {
    if (isDevUser) return 'Founder 💻';
    return '';
  }

  String get tagline {
    if (isDevUser) return 'Just a girl developing apps to get the tea ☕️';
    return 'Spillin’ the Real-Tea';
  }

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    setState(() {
      avatarPath = doc.data()?['avatarPath'];
      displayName = doc.data()?['name'] ?? user.displayName ?? 'Guest';
    });
  }

  void _updateAvatar(String newPath) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'avatarPath': newPath,
    }, SetOptions(merge: true));
    setState(() {
      avatarPath = newPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final String email = user?.email ?? 'no-email';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final newAvatar = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AvatarPickerScreen(
                      onAvatarSelected: _updateAvatar,
                    ),
                  ),
                );

                if (newAvatar !=null) {
                  _updateAvatar(newAvatar);
                }
              },
              child: CircleAvatar(
                radius: 48,
                backgroundImage: AssetImage(displayAvatarPath),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              displayName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (badgeLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tagline,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Your Profile'),
              onTap: () {
                Navigator.pushNamed(context, '/edit-profile');
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Favorites'),
              onTap: () {
                Navigator.pushNamed(context, '/favorites');
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Visited Properties'),
              onTap: () {
                Navigator.pushNamed(context, '/visited');
              },
            ),
          ],
        ),
      ),
    );
  }
}
