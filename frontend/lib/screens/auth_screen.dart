import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';
import '../widgets/agent_mark.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController();
  bool _registering = false, _obscure = true;
  String? _emailError, _passwordError, _authError;
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool get _validEmail => _emailPattern.hasMatch(_email.text.trim());
  bool get _canSubmit =>
      _validEmail && _password.text.isNotEmpty && _passwordError == null;

  void _validateEmail(String value) {
    final email = value.trim();
    setState(() {
      _emailError = email.isEmpty || _emailPattern.hasMatch(email)
          ? null
          : 'Enter a valid email address.';
      if (!_validEmail) {
        _passwordError = null;
      }
      _authError = null;
    });
  }

  void _validatePassword(String value) {
    setState(() {
      _passwordError = value.isEmpty ? 'Enter your password.' : null;
      _authError = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _validateEmail(_email.text);
    _validatePassword(_password.text);
    if (!_canSubmit) return;
    final error = _registering
        ? await ref
            .read(authProvider)
            .register(_name.text, _email.text, _password.text)
        : await ref.read(authProvider).login(_email.text, _password.text);
    if (mounted && error != null) setState(() => _authError = error);
  }

  // Future<void> _forgotPassword() async {
  //   final emailController = TextEditingController(text: _email.text);
  //   final passwordController = TextEditingController();
  //   final result = await showDialog<String>(
  //       context: context,
  //       builder: (context) => AlertDialog(
  //             title: const Text('Reset password'),
  //             content: Column(mainAxisSize: MainAxisSize.min, children: [
  //               TextField(
  //                   controller: emailController,
  //                   keyboardType: TextInputType.emailAddress,
  //                   decoration: const InputDecoration(labelText: 'Email')),
  //               TextField(
  //                   controller: passwordController,
  //                   obscureText: true,
  //                   decoration:
  //                       const InputDecoration(labelText: 'New password'))
  //             ]),
  //             actions: [
  //               TextButton(
  //                   onPressed: () => Navigator.pop(context),
  //                   child: const Text('Cancel')),
  //               FilledButton(
  //                   onPressed: () async {
  //                     final error = await ref.read(authProvider).forgotPassword(
  //                         emailController.text, passwordController.text);
  //                     if (context.mounted) Navigator.pop(context, error);
  //                   },
  //                   child: const Text('Update password'))
  //             ],
  //           ));
  //   emailController.dispose();
  //   passwordController.dispose();
  //   if (!mounted) return;
  //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  //       content: Text(result ?? 'Password updated. You can sign in now.')));
  // }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AgentMark(size: 56),
                              const SizedBox(height: 34),
                              Text(
                                  _registering
                                      ? 'Create your workspace'
                                      : 'Welcome back',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text(_registering
                                  ? 'Your research partner is ready when you are.'
                                  : 'Continue your conversations with Ankit’s Agent.'),
                              const SizedBox(height: 30),
                              if (_registering)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TextField(
                                        controller: _name,
                                        decoration: const InputDecoration(
                                            labelText: 'Your name'))),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                onChanged: _validateEmail,
                                decoration: const InputDecoration(
                                    labelText: 'Email address'),
                              ),
                              if (_emailError != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(_emailError!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: _password,
                                  enabled: _validEmail,
                                  obscureText: _obscure,
                                  onChanged: _validatePassword,
                                  onSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                      labelText: 'Password',
                                      errorText: _passwordError,
                                      suffixIcon: IconButton(
                                          onPressed: () => setState(
                                              () => _obscure = !_obscure),
                                          icon: Icon(_obscure
                                              ? Icons.visibility_outlined
                                              : Icons
                                                  .visibility_off_outlined)))),
                              const SizedBox(height: 22),
                              if (_authError != null)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(_authError!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              FilledButton(
                                  onPressed: auth.submitting || !_canSubmit
                                      ? null
                                      : _submit,
                                  style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(54)),
                                  child: auth.submitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Text(_registering
                                          ? 'Create account'
                                          : 'Sign in')),
                              const SizedBox(height: 14),
                              // if (!_registering)
                              //   Center(
                              //       child: TextButton(
                              //           onPressed: auth.submitting
                              //               ? null
                              //               : _forgotPassword,
                              //           child: const Text('Forgot password?'))),
                              Center(
                                  child: TextButton(
                                      onPressed: auth.submitting
                                          ? null
                                          : () => setState(() =>
                                              _registering = !_registering),
                                      child: Text(_registering
                                          ? 'Already have an account? Sign in'
                                          : 'New here? Create an account')))
                            ]))))));
  }
}
