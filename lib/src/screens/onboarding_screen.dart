import 'package:flutter/material.dart';

import '../state/vault_controller.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.controller,
    super.key,
  });

  final VaultController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _passcodeController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _passcodeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await widget.controller.setupPasscode(_passcodeController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build your private vault',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Images, videos, contacts, and app shortcuts are stored behind a local passcode and encrypted vault index.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passcodeController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Create passcode',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.length < 4) {
                          return 'Use at least 4 digits.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Confirm passcode',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if ((value?.trim() ?? '') != _passcodeController.text.trim()) {
                          return 'Passcodes do not match.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: widget.controller.busy ? null : _submit,
                        child: Text(widget.controller.busy ? 'Creating...' : 'Create vault'),
                      ),
                    ),
                    if (widget.controller.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.controller.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
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
