// avatar_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AvatarPickerScreen extends StatefulWidget {
  final Function(String) onAvatarSelected;

  const AvatarPickerScreen({required this.onAvatarSelected, super.key});

  @override
  State<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends State<AvatarPickerScreen> {
  String? _selectedAvatar;

  final List<Map<String, String>> avatars = [
    {'path': 'assets/avatars/founder.png', 'label': 'Founder'},
    {'path': 'assets/avatars/house_hunter.png', 'label': 'House Hunter'},
    {'path': 'assets/avatars/browsing.png', 'label': 'Just Browsing'},
    {'path': 'assets/avatars/realtor.png', 'label': 'Agent Mode'},
    {'path': 'assets/avatars/price_watcher.png', 'label': 'Price Watcher'},
    {'path': 'assets/avatars/couch_surfer.png', 'label': 'Couch Surfer'},
    {'path': 'assets/avatars/matchmaker.png', 'label': 'Matchmaker'},
    {'path': 'assets/avatars/homeowner.png', 'label': 'Seller'},
    {'path': 'assets/avatars/clown.png', 'label': 'Came for the Chaos'},
    {'path': 'assets/avatars/tea_spiller.png', 'label': 'Spillin the Tea'},
  ];

  void _saveAvatarSelection() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedAvatar == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'avatarPath': _selectedAvatar,
    }, SetOptions(merge: true));

    widget.onAvatarSelected(_selectedAvatar!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Your Avatar')),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemCount: avatars.length,
              itemBuilder: (context, index) {
                final avatar = avatars[index];
                final isSelected = avatar['path'] == _selectedAvatar;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAvatar = avatar['path'];
                    });
                  },
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                avatar['path']!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.green,
                                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        avatar['label']!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _saveAvatarSelection,
              child: const Text('Save Selection'),
            ),
          ),
        ],
      ),
    );
  }
}
