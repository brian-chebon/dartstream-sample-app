import 'package:flutter/material.dart';
import 'package:openfeature_provider_intellitoggle/openfeature_provider_intellitoggle.dart';

import '../intellitoggle/flag_aware.dart';
import '../intellitoggle/intellitoggle.dart';
import '../state/session.dart';

/// Live demo of **IntelliToggle** — Aortem's feature-flag SaaS — evaluated
/// through the standard OpenFeature provider (OAuth2 client-credentials). This
/// is distinct from the "Feature flags" screen, which drives DartStream's own
/// `platform.featureFlags` CRUD. Here we register the IntelliToggle provider,
/// score flags against the signed-in DartStream identity, and surface the full
/// evaluation result (value + reason + variant + any error).
class IntelliToggleScreen extends StatefulWidget {
  const IntelliToggleScreen({super.key, required this.session});
  final Session session;

  @override
  State<IntelliToggleScreen> createState() => _IntelliToggleScreenState();
}

enum _FlagType { boolean, string, integer, double_, object }

class _IntelliToggleScreenState extends State<IntelliToggleScreen> {
  bool _registering = true;
  Object? _registerError;

  final _keyController = TextEditingController(text: 'new-dashboard');
  _FlagType _type = _FlagType.boolean;
  bool _evaluating = false;
  String? _result;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _targeting => {
        if (widget.session.userId != null) 'userId': widget.session.userId,
        if (widget.session.email != null) 'email': widget.session.email,
        if (widget.session.tenantId != null) 'tenantId': widget.session.tenantId,
      };

  Future<void> _register() async {
    if (!IntelliToggle.instance.isConfigured) {
      setState(() => _registering = false);
      return;
    }
    setState(() {
      _registering = true;
      _registerError = null;
    });
    try {
      await IntelliToggle.instance.register(targeting: _targeting);
      if (mounted) setState(() => _registering = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _registerError = e;
          _registering = false;
        });
      }
    }
  }

  Future<void> _evaluate() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _evaluating = true;
      _result = null;
      _resultIsError = false;
    });
    try {
      final String text;
      switch (_type) {
        case _FlagType.boolean:
          text = _format(await IntelliToggle.instance.getBoolean(key));
        case _FlagType.string:
          text = _format(await IntelliToggle.instance.getString(key));
        case _FlagType.integer:
          text = _format(await IntelliToggle.instance.getInteger(key));
        case _FlagType.double_:
          text = _format(await IntelliToggle.instance.getDouble(key));
        case _FlagType.object:
          text = _format(await IntelliToggle.instance.getObject(key));
      }
      if (mounted) setState(() => _result = text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = e.toString();
          _resultIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _evaluating = false);
    }
  }

  String _format(FlagEvaluationResult res) {
    final lines = <String>[
      'value: ${res.value}',
      'reason: ${res.reason}',
      if (res.variant != null) 'variant: ${res.variant}',
      if (res.errorCode != null) 'errorCode: ${res.errorCode}',
      if (res.errorMessage != null) 'errorMessage: ${res.errorMessage}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    if (!IntelliToggle.instance.isConfigured) return _notConfigured();
    if (_registering) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_registerError != null) return _registerErrorView();
    return _ready();
  }

  // ---- states --------------------------------------------------------------

  Widget _notConfigured() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.toggle_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text('IntelliToggle is not configured',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Supply OAuth2 client-credentials at build time to evaluate '
                'flags from IntelliToggle:\n\n'
                '--dart-define=INTELLITOGGLE_CLIENT_ID=...\n'
                '--dart-define=INTELLITOGGLE_CLIENT_SECRET=...\n'
                '--dart-define=INTELLITOGGLE_TENANT_ID=...',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _registerErrorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not register the IntelliToggle provider:\n'
                  '$_registerError',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _register, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _ready() {
    final provider = IntelliToggle.instance.provider;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _statusCard(provider),
        const SizedBox(height: 16),
        _evaluatorCard(),
        const SizedBox(height: 16),
        _widgetDemoCard(),
      ],
    );
  }

  Widget _statusCard(FeatureProvider provider) {
    final ready = provider.state == ProviderState.READY;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Provider: ${provider.metadata.name}',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(provider.state.name),
                  backgroundColor: ready
                      ? Colors.green.withValues(alpha: 0.18)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Evaluating via OpenFeature with OAuth2 client-credentials. '
              'Targeting: ${_targeting.isEmpty ? '(anonymous)' : _targeting}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _evaluatorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Evaluate a flag',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyController,
                    decoration: const InputDecoration(
                      labelText: 'Flag key',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _evaluate(),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<_FlagType>(
                  value: _type,
                  onChanged: (t) => setState(() => _type = t!),
                  items: const [
                    DropdownMenuItem(
                        value: _FlagType.boolean, child: Text('boolean')),
                    DropdownMenuItem(
                        value: _FlagType.string, child: Text('string')),
                    DropdownMenuItem(
                        value: _FlagType.integer, child: Text('integer')),
                    DropdownMenuItem(
                        value: _FlagType.double_, child: Text('double')),
                    DropdownMenuItem(
                        value: _FlagType.object, child: Text('object')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _evaluating ? null : _evaluate,
                icon: _evaluating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_evaluating ? 'Evaluating…' : 'Evaluate'),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _resultIsError
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_result!,
                    style: const TextStyle(fontFamily: 'monospace')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _widgetDemoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flag-aware widgets',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'These widgets render straight from the live flag value '
              '(keys: "new-dashboard", "hero-variant").',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ItFlagAware(
              flagKey: 'new-dashboard',
              onChild: const ListTile(
                leading: Icon(Icons.dashboard, color: Colors.green),
                title: Text('New dashboard is ON'),
              ),
              offChild: const ListTile(
                leading: Icon(Icons.dashboard_outlined),
                title: Text('New dashboard is OFF (default)'),
              ),
            ),
            const Divider(),
            ItExperiment(
              flagKey: 'hero-variant',
              defaultVariant: 'control',
              variants: const {
                'control': ListTile(
                  leading: Icon(Icons.science_outlined),
                  title: Text('Hero: control'),
                ),
                'treatment': ListTile(
                  leading: Icon(Icons.science, color: Colors.blue),
                  title: Text('Hero: treatment'),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
