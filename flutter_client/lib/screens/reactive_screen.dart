import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter/material.dart';

import '../state/session.dart';
import '../widgets/resource_crud_section.dart';

/// Live demo of ds-reactive-dataflow: log an event + view the event log, and
/// manage event subscriptions, streaming channels, notification configs, and
/// lifecycle hooks. Every backend error is surfaced in a SnackBar.
class ReactiveScreen extends StatelessWidget {
  const ReactiveScreen({super.key, required this.session});
  final Session session;

  ResourceCrudSection _crud({
    required String title,
    required String inputLabel,
    required String path,
    required Map<String, dynamic> Function(String) body,
    required String Function(Map) titleOf,
  }) {
    final s = session;
    return ResourceCrudSection(
      title: title,
      inputLabel: inputLabel,
      titleOf: titleOf,
      fetch: () => s.client!.reactive.list(s.ds!, path),
      onCreate: (v) async =>
          s.client!.reactive.create(s.ds!, path, body: body(v)),
      onDelete: (item) => s.client!.reactive.delete(
          s.ds!,
          // path may carry a trailing slash (e.g. '/lifecycle/'); avoid '//'.
          path.endsWith('/') ? '$path${item['id']}' : '$path/${item['id']}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _EventsPanel(session: session),
        _crud(
          title: 'Event subscriptions',
          inputLabel: 'event_type',
          path: '/events/subscriptions',
          body: (v) => {'event_type': v, 'subscription_name': v},
          titleOf: (m) =>
              (m['event_type'] ?? m['subscription_name'] ?? m['id']).toString(),
        ),
        _crud(
          title: 'Streaming channels',
          inputLabel: 'channel_name',
          path: '/streaming/channels',
          body: (v) => {'channel_name': v},
          titleOf: (m) => (m['channel_name'] ?? m['name'] ?? m['id']).toString(),
        ),
        _crud(
          title: 'Notification configs',
          inputLabel: 'name',
          path: '/notifications/configs',
          body: (v) => {
            'name': v,
            'provider_type': 'webhook',
            'config': {'url': 'https://example.test/hook'},
            'enabled': true,
          },
          titleOf: (m) => (m['name'] ?? m['id']).toString(),
        ),
        _crud(
          title: 'Lifecycle hooks',
          inputLabel: 'hook_name',
          path: '/lifecycle/',
          body: (v) => {'hook_name': v, 'hook_type': 'custom'},
          titleOf: (m) => (m['hook_name'] ?? m['id']).toString(),
        ),
      ],
    );
  }
}

/// Log a reactive event and show the recent event log.
class _EventsPanel extends StatefulWidget {
  const _EventsPanel({required this.session});
  final Session session;

  @override
  State<_EventsPanel> createState() => _EventsPanelState();
}

class _EventsPanelState extends State<_EventsPanel> {
  DartStreamClient get _client => widget.session.client!;
  DartStreamSession get _ds => widget.session.ds!;

  bool _loading = true;
  List<dynamic> _events = const [];
  bool _logging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final events = await _client.reactive.list(_ds, '/events/log');
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(context, 'Load events failed — $e', error: true);
      }
    }
  }

  Future<void> _logEvent() async {
    setState(() => _logging = true);
    try {
      await _client.reactive.logEvent(
        _ds,
        eventType: 'demo.button.click',
        payload: {'at': DateTime.now().toUtc().toIso8601String()},
      );
      if (mounted) _snack(context, 'Event logged.');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Log event failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Events (${_events.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _logging ? null : _logEvent,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text(_logging ? 'Logging…' : 'Log event'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_events.isEmpty)
              const Text('(no events logged yet)')
            else
              for (final e in _events.take(10))
                if (e is Map)
                  Text('• ${e['event_type'] ?? e['eventType'] ?? '?'}'
                      '  ${e['created_at'] ?? e['createdAt'] ?? ''}'),
          ],
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
