import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/asset_paths.dart'; // avatarOptions, defaultAvatar

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // Your UID: only you can use "founder"
  static const String founderUid = 'M4lWfnacEJPwJ2ZaEr7eFo8azEy2';

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _avatarKey; // e.g., "house_hunter"
  bool _saving = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  String sanitizeAvatarKey(String? key, String uid) {
    if (key == null || key.isEmpty) return '';
    if (!avatarOptions.containsKey(key)) return '';
    if (key == 'founder' && uid != founderUid) return '';
    return key;
  }

  @override
  void initState() {
    super.initState();
    final u = _user;
    if (u != null) {
      _email.text = u.email ?? '';
      FirebaseFirestore.instance.collection('users').doc(u.uid).get().then((doc) {
        final data = doc.data();
        if (!mounted) return;
        _name.text = (data?['displayName'] ?? data?['name'] ?? u.displayName ?? '');
        final storedKey = data?['avatarKey'] as String?;
        _avatarKey = sanitizeAvatarKey(storedKey, u.uid);
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    // AvatarPickerScreen returns a key like "house_hunter"
    final result = await Navigator.pushNamed(context, '/avatar-picker');
    final u = _user;
    if (u == null) return;
    if (result is String) {
      final safe = sanitizeAvatarKey(result, u.uid);
      setState(() => _avatarKey = safe.isEmpty ? null : safe);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final u = _user;
    if (u == null) return;

    setState(() => _saving = true);
    try {
      final safeKey = sanitizeAvatarKey(_avatarKey, u.uid);

      // Firestore: store only the key
      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
        'displayName': _name.text.trim(),
        'name': _name.text.trim(),
        'avatarKey': safeKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Keep FirebaseAuth displayName in sync
      await u.updateDisplayName(_name.text.trim());

      // Email change (verification required)
      final newEmail = _email.text.trim();
      if (newEmail.isNotEmpty && newEmail != (u.email ?? '')) {
        await u.verifyBeforeUpdateEmail(newEmail);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification email sent.')),
          );
        }
      }

      // Password change
      if (_password.text.isNotEmpty) {
        await u.updatePassword(_password.text);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      final msg = (e.code == 'requires-recent-login')
          ? 'Please log out/in again, then update your password.'
          : (e.message ?? 'Update failed.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = (_avatarKey != null && _avatarKey!.isNotEmpty && avatarOptions.containsKey(_avatarKey))
        ? avatarOptions[_avatarKey]!
        : defaultAvatar;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: AssetImage(assetPath),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: IconButton.filled(
                      onPressed: _pickAvatar,
                      icon: const Icon(Icons.edit),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your email' : null,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'New Password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
