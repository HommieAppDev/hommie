import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/asset_paths.dart';

class AvatarPickerScreen extends StatefulWidget {
  const AvatarPickerScreen({super.key});
  @override
  State<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends State<AvatarPickerScreen> {
  static const String founderUid = 'M4lWfnacEJPwJ2ZaEr7eFo8azEy2';

  String? _selected;
  bool _loading = true;
  late final User? _user;

  Map<String, String> _filteredOptionsFor(String? uid) {
    final map = Map<String, String>.from(avatarOptions);
    if (uid != founderUid) map.remove('founder');
    // sort keys by human label
    final sorted = map.keys.toList()
      ..sort((a, b) => _label(a).compareTo(_label(b)));
    return {for (final k in sorted) k: map[k]!};
  }

  String _label(String key) =>
      key.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _initSelection();
  }

  Future<void> _initSelection() async {
    final uid = _user?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final currentKey = doc.data()?['avatarKey'] as String?;
      _selected = (currentKey != null && currentKey.isNotEmpty)
          ? currentKey
          : (uid == founderUid ? 'founder' : null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final uid = _user?.uid;
    if (uid == null) return;

    var toSave = _selected;
    if (toSave == 'founder' && uid != founderUid) toSave = null;

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'avatarKey': toSave,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.pop(context, toSave);
  }

  @override
  Widget build(BuildContext context) {
    final uid = _user?.uid;
    final options = _filteredOptionsFor(uid);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose Avatar')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Choose Avatar')),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: options.length,
              itemBuilder: (context, index) {
                final entry = options.entries.elementAt(index);
                final key = entry.key;
                final path = entry.value;
                final selected = key == _selected;

                return GestureDetector(
                  onTap: () => setState(() => _selected = key),
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                path,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image_not_supported),
                                ),
                              ),
                            ),
                            if (selected)
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
                      const SizedBox(height: 6),
                      Text(
                        _label(key),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(onPressed: _save, child: const Text('Save Selection')),
            ),
          ),
        ],
      ),
    );
  }
}
