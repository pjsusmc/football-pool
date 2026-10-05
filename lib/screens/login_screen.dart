import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    try {
      if (_isSignUp) {
        await auth.signUp(_email.text.trim(), _password.text, _name.text.trim());
      } else {
        await auth.signIn(_email.text.trim(), _password.text);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter your email first.');
      return;
    }
    await context.read<AuthService>().sendPasswordReset(_email.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password reset email sent')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_isSignUp ? 'Create your account' : 'Football Pool',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Display name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isSignUp ? 'Sign up' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(_isSignUp ? 'Have an account? Sign in' : 'New here? Create an account'),
                    ),
                    if (!_isSignUp)
                      TextButton(onPressed: _reset, child: const Text('Forgot password?')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
