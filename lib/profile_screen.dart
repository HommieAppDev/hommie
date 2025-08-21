// lib/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'constants/asset_paths.dart'; // avatarOptions, defaultAvatar

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Your UID: only you can use the "founder" avatar
  static const String founderUid = 'M4lWfnacEJPwJ2ZaEr7eFo8azEy2';

  User? get _user => FirebaseAuth.instance.currentUser;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;

  bool get _isFounder => _user?.uid == founderUid;

  @override
  void initState() {
    super.initState();
    if (_user != null) {
      _userDocStream = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .snapshots();
    }
  }

  String _assetForAvatarKey(String? key) {
    if (key != null && key.isNotEmpty && avatarOptions.containsKey(key)) {
      // block spoofing: non-founder cannot use "founder"
      if (key == 'founder' && !_isFounder) return defaultAvatar;
      return avatarOptions[key]!;
    }
    // default: founder gets founder image if none chosen; others get default
    if (_isFounder && avatarOptions.containsKey('founder')) {
      return avatarOptions['founder']!;
    }
    return defaultAvatar;
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? 'no-email';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _userDocStream == null
            ? const Center(child: Text('Please sign in'))
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userDocStream,
                builder: (context, snap) {
                  final data = snap.data?.data();
                  final displayName =
                      (data?['displayName'] ?? data?['name'] ?? _user?.displayName ?? 'Guest')
                          .toString();
                  final avatarKey = data?['avatarKey'] as String?;
                  final avatarAsset = _assetForAvatarKey(avatarKey);

                  final badgeLabel = _isFounder ? 'Founder 💻' : '';
                  final tagline = _isFounder
                      ? 'Just a girl developing apps to get the tea ☕️'
                      : 'Spillin’ the Real-Tea';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      // Tap avatar to open picker (no-arg screen via named route)
                      GestureDetector(
                        onTap: () async {
                          final result =
                                await Navigator.pushNamed(context, '/avatar-picker');
                          // No need to handle result here; AvatarPicker writes to Firestore
                          // StreamBuilder will auto-refresh. (Optional: setState if you cache anything.)
                        },
                        child: CircleAvatar(
                          radius: 48,
                          backgroundImage: AssetImage(avatarAsset),
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
                            style: const TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.bold,
                            ),
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
                        onTap: () => Navigator.pushNamed(context, '/edit-profile'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.favorite_border),
                        title: const Text('Favorites'),
                        onTap: () => Navigator.pushNamed(context, '/favorites'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.check_circle_outline),
                        title: const Text('Visited Properties'),
                        onTap: () => Navigator.pushNamed(context, '/visited'),
                      ),
                      const Spacer(),
                      Text(
                        email,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
