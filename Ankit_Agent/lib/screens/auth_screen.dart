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
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final error = _registering
        ? await ref
            .read(authProvider)
            .register(_name.text, _email.text, _password.text)
        : await ref.read(authProvider).login(_email.text, _password.text);
    if (mounted && error != null)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
  }

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
                                  decoration: const InputDecoration(
                                      labelText: 'Email address')),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  onSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                      labelText: 'Password',
                                      suffixIcon: IconButton(
                                          onPressed: () => setState(
                                              () => _obscure = !_obscure),
                                          icon: Icon(_obscure
                                              ? Icons.visibility_outlined
                                              : Icons
                                                  .visibility_off_outlined)))),
                              const SizedBox(height: 22),
                              FilledButton(
                                  onPressed: auth.submitting ? null : _submit,
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
