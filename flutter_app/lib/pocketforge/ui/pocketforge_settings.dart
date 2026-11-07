// l10n:ignore-file — English-only PocketForge product, independent of Fa's app.
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/material.dart';

import '../pocketforge_model.dart';
import 'pocketforge_theme.dart';

Future<void> showPocketForgeSettings(
  BuildContext context,
  PocketForgeModel session,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 620),
  builder: (_) => PocketForgeSettings(session: session),
);

class PocketForgeSettings extends StatefulWidget {
  const PocketForgeSettings({super.key, required this.session});
  final PocketForgeModel session;

  @override
  State<PocketForgeSettings> createState() => _PocketForgeSettingsState();
}

class _PocketForgeSettingsState extends State<PocketForgeSettings> {
  late final _model = TextEditingController(text: widget.session.modelId);
  final _key = TextEditingController();
  late int _requests = widget.session.maxRequests;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_model.text.trim().isEmpty) {
      setState(() => _error = 'Enter a model ID.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.saveSettings(
        modelId: _model.text.trim(),
        apiKey: _key.text.trim().isEmpty ? null : _key.text.trim(),
        maxRequests: _requests,
      );
      if (mounted && widget.session.error == null) {
        Navigator.pop(context);
      } else if (mounted) {
        setState(() => _error = widget.session.error);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FahColors.of(context);
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, size: 20, color: colors.teal),
                  const SizedBox(width: 12),
                  Text(
                    'Model settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    tooltip: 'Close settings',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Your API account powers the agent. Your files stay in this workspace.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.dim),
              ),
              const SizedBox(height: 28),
              _label(context, 'PROVIDER'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.panelAlt,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hub_outlined, size: 20, color: colors.text),
                    const SizedBox(width: 12),
                    const Text('DeepSeek'),
                    const Spacer(),
                    Text(
                      'api.deepseek.com',
                      style: forgeMono(context, size: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _model,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Model ID',
                  hintText: 'deepseek-flash',
                ),
                style: forgeMono(context, color: colors.text, size: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _key,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: widget.session.hasApiKey
                      ? 'Replace API key'
                      : 'API key',
                  hintText: widget.session.hasApiKey
                      ? 'Leave blank to keep your key'
                      : 'Paste your DeepSeek API key',
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    widget.session.secureKeyStorage
                        ? Icons.lock_outline
                        : Icons.memory_rounded,
                    size: 15,
                    color: colors.teal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.session.secureKeyStorage
                          ? 'Stored in device Keychain. Your key is never added to the chat or project files.'
                          : 'This runtime keeps your key in session memory only. It is not saved in browser storage.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.dim,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.session.hasApiKey)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          await widget.session.removeApiKey();
                          _key.clear();
                          if (mounted) setState(() {});
                        },
                  child: const Text('Remove API key'),
                ),
              const SizedBox(height: 24),
              _label(context, 'RUN LIMIT'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_requests model requests',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: _saving || _requests <= 1
                        ? null
                        : () => setState(() => _requests--),
                    tooltip: 'Fewer requests',
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  IconButton(
                    onPressed: _saving || _requests >= 40
                        ? null
                        : () => setState(() => _requests++),
                    tooltip: 'More requests',
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              Text(
                'Provider API usage is billed to your account. Prompts and tool results are sent to DeepSeek.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.dim, height: 1.5),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || widget.session.isRunning ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save settings'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'PocketForge',
                    applicationVersion: '0.1.0',
                  ),
                  icon: const Icon(Icons.info_outline_rounded, size: 15),
                  label: const Text('Open source notices'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String label) => Text(
    label,
    style: forgeMono(context, size: 10).copyWith(letterSpacing: 1.5),
  );
}
