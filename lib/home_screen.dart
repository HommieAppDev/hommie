// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/asset_paths.dart'; // avatarOptions, defaultAvatar

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  User? get _user => FirebaseAuth.instance.currentUser;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final u = _user;
    if (u != null) {
      _userDocStream =
          FirebaseFirestore.instance.collection('users').doc(u.uid).snapshots();
      _touchLastSeen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _touchLastSeen();
    }
  }

  void _touchLastSeen() {
    final u = _user;
    if (u == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .set({'lastSeen': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (_) => false);
  }

  // ---- Safe navigation helper (prevents dependOnInherited crash) ----
  void _safePushNamed(String route, {Object? arguments}) {
    FocusScope.of(context).unfocus(); // close any keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamed(route, arguments: arguments);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/home_screen.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          // Optional overlay for readability
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.25)),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: _userDocStream == null
                  ? _buildContent(displayName: 'there', avatarAsset: defaultAvatar)
                  : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _userDocStream,
                      builder: (context, snap) {
                        final data = snap.data?.data();
                        final displayName = (data?['displayName'] ??
                                data?['name'] ??
                                _user?.displayName ??
                                'there')
                            .toString();

                        final key = data?['avatarKey'] as String?;
                        final avatarAsset = (key != null && avatarOptions.containsKey(key))
                            ? avatarOptions[key]!
                            : defaultAvatar;

                        return _buildContent(
                          displayName: displayName,
                          avatarAsset: avatarAsset,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent({required String displayName, required String avatarAsset}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        // Avatar -> go to Profile
        GestureDetector(
          onTap: () => _safePushNamed('/profile'),
          child: CircleAvatar(
            radius: 44,
            backgroundColor: Colors.white.withOpacity(0.85),
            backgroundImage: AssetImage(avatarAsset),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Welcome, $displayName!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
        const Spacer(),
        _HomeBtn(
          label: 'Search Listings',
          onPressed: () => _safePushNamed('/search'),
        ),
        const SizedBox(height: 16),
        _HomeBtn(
          label: 'View Favorites',
          onPressed: () => _safePushNamed('/favorites'),
        ),
        const SizedBox(height: 16),
        _HomeBtn(
          label: 'Visited Properties',
          onPressed: () => _safePushNamed('/visited'),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: _logout,
          child: const Text('Log Out', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _HomeBtn extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _HomeBtn({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.9),
          foregroundColor: Colors.blueGrey[800],
          elevation: 2,
          shape: const StadiumBorder(),
        ),
        child: Text(label),
      ),
    );
  }
}
