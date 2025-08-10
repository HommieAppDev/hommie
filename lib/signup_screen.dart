import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  final _nameNode = FocusNode();
  final _emailNode = FocusNode();
  final _passwordNode = FocusNode();
  final _confirmNode = FocusNode();

  bool _obscurePw = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _nameNode.dispose();
    _emailNode.dispose();
    _passwordNode.dispose();
    _confirmNode.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email required';
    final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s);
    return ok ? null : 'Enter a valid email';
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password required';
    if (v.length < 6) return 'Minimum 6 characters';
    return null;
  }

  Future<void> _signUp() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      final user = cred.user;
      if (user != null) {
        // set display name
        await user.updateDisplayName(_name.text.trim());
        // optional: send verification (uncomment if you want it)
        // await user.sendEmailVerification();
        await user.reload();
      }

      if (!mounted) return;
      // Navigate to your home screen (adjust route as needed)
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Sign up failed.');
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    focusNode: _nameNode,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (_) => _emailNode.requestFocus(),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name required' : null,
                    autofillHints: const [AutofillHints.name],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    focusNode: _emailNode,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (_) => _passwordNode.requestFocus(),
                    validator: _validateEmail,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    focusNode: _passwordNode,
                    textInputAction: TextInputAction.next,
                    obscureText: _obscurePw,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscurePw = !_obscurePw),
                        icon: Icon(_obscurePw ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                    onFieldSubmitted: (_) => _confirmNode.requestFocus(),
                    validator: _validatePassword,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    focusNode: _confirmNode,
                    textInputAction: TextInputAction.done,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Confirm your password' : null,
                    onFieldSubmitted: (_) => _signUp(),
                  ),
                  const SizedBox(height: 12),

                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                  ],

                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signUp,
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign Up'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.pop(context), // back to Welcome/Login
                    child: const Text('Already have an account? Log in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
