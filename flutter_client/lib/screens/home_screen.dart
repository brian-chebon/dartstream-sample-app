import 'dart:async';

import 'package:dartstream_client/dartstream_client.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/shard_pilot.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _SaveStatus { idle, saving, saved, error }

class _HomeScreenState extends State<HomeScreen> {
  static const _slotKey = 'flame';
  // DartStream Dash runs in its own experience scope — deliberately distinct
  // from the SaaS gaming samples (flame-game/production) so this client's
  // profile, inventory and cloud-saves are isolated and we verify the
  // project+environment scoping independently rather than mirroring them.
  static const _projectId = 'dartstream-dash';
  static const _environmentId = 'production';
  static const _scope = DartStreamScope(
    projectId: _projectId,
    environmentId: _environmentId,
  );

  late ShardPilotGame _game;
  bool _loading = true;
  Object? _bootstrapError;

  Map<String, dynamic>? _profile;
  List<dynamic> _flags = const [];
  List<dynamic> _inventory = const [];
  List<dynamic> _channels = const [];
  String _lastEvent = '—';
  _SaveStatus _saveStatus = _SaveStatus.idle;
  Timer? _saveDebounce;
  String _resumeSummary = 'new game';

  DartStreamClient get _client => widget.session.client!;
  DartStreamSession get _ds => widget.session.ds!;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Every gameplay input comes from a live DartStream service. The typed
      // experience/platform/reactive clients return the profile map, the flag
      // list, the inventory items, the cloud-save snapshot, and the channels.
      final results = await Future.wait<Object?>([
        _client.experience.profile(_ds, scope: _scope),
        _client.platform.listFeatureFlags(_ds),
        _client.experience.inventory(_ds, scope: _scope),
        _client.experience.loadSnapshot(_ds, scope: _scope, slotKey: _slotKey),
        _client.reactive.streamingChannels(_ds),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final flagsList = results[1] as List<dynamic>;
      final items = results[2] as List<dynamic>;
      final snapshot = results[3] as Map<String, dynamic>?;
      final channels = results[4] as List;

      final payload =
          (snapshot?['snapshot'] is Map &&
              (snapshot!['snapshot'] as Map)['payload'] is Map)
          ? (snapshot['snapshot'] as Map)['payload'] as Map
          : const {};
      final config = _buildConfig(flagsList, items, payload, profile);
      _resumeSummary =
          'high ${config.resumeHighScore} · '
          'coins ${config.resumeLifetimeCoins}';
      _game = ShardPilotGame(
        config: config,
        onSnapshot: _onSnapshot,
        onEvent: _onEvent,
      );
      setState(() {
        _profile = profile;
        _flags = flagsList;
        _inventory = items;
        _channels = channels;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _bootstrapError = e;
        _loading = false;
      });
    }
  }

  /// Maps live feature flags + inventory + a cloud-save snapshot into the
  /// gameplay config — this is where DartStream services drive the game.
  PilotConfig _buildConfig(
    List<dynamic> flags,
    List<dynamic> inventory,
    Map payload,
    Map<String, dynamic> profile,
  ) {
    final enabled = <String>{};
    for (final f in flags) {
      if (f is Map && (f['enabled'] == true || f['status'] == 'active')) {
        final key = (f['key'] ?? f['flag_key'] ?? f['flagKey'] ?? '')
            .toString();
        if (key.isNotEmpty) enabled.add(key);
      }
    }
    int swordCharges = 0;
    for (final item in inventory) {
      if (item is Map && (item['itemId'] ?? item['id']) == 'starter-sword') {
        final qty = item['quantity'];
        swordCharges = (qty is int && qty > 0) ? qty.clamp(1, 3) : 1;
      }
    }
    final p = (profile['profile'] is Map) ? profile['profile'] as Map : profile;
    final name = (p['displayName'] ?? p['display_name'] ?? 'Player').toString();
    int asInt(Object? v) => v is int ? v : 0;

    return PilotConfig(
      startLives: enabled.contains('extra_life') ? 4 : 3,
      doubleScore: enabled.contains('double_score'),
      hardMode: enabled.contains('hard_mode'),
      swordCharges: swordCharges,
      resumeHighScore: asInt(payload['highScore']),
      resumeLifetimeCoins: asInt(payload['lifetimeCoins']),
      playerName: name,
    );
  }

  /// Debounced cloud-save of the full game state (called by the game).
  void _onSnapshot(Map<String, dynamic> snapshot) {
    _saveDebounce?.cancel();
    setState(() => _saveStatus = _SaveStatus.saving);
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _client.experience.saveSnapshot(
          _ds,
          scope: _scope,
          slotKey: _slotKey,
          payload: snapshot,
        );
        if (mounted) setState(() => _saveStatus = _SaveStatus.saved);
      } catch (_) {
        if (mounted) setState(() => _saveStatus = _SaveStatus.error);
      }
    });
  }

  /// Reactive event log (called by the game on start/level-up/hit/over/etc.).
  Future<void> _onEvent(String type, Map<String, dynamic> payload) async {
    _setLastEvent('$type @ ${_now()}');
    try {
      await _client.reactive.logEvent(
        _ds,
        eventType: type,
        payload: {...payload, 'source': 'dartstream-dash'},
      );
    } catch (e) {
      _setLastEvent('$type (log error: $e)');
    }
  }

  /// The game emits `game.start` during the GameWidget's first build (onLoad),
  /// so defer the rebuild to after the current frame to avoid setState-in-build.
  void _setLastEvent(String value) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _lastEvent = value);
    });
  }

  String _now() => DateTime.now().toIso8601String().substring(11, 19);

  @override
  Widget build(BuildContext context) {
    // The shell provides the Scaffold/AppBar; this screen renders body only.
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _bootstrapError != null
        ? _errorView()
        : _layout();
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Bootstrap failed: $_bootstrapError',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _bootstrapError = null;
              });
              _bootstrap();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _layout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 900;
        final gameWidget = GameWidget(game: _game);
        final gameDecoration = BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        );
        final panels = _panels();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hero(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Game fills the full height of the content area.
                          Expanded(
                            flex: 4,
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: gameDecoration,
                              child: gameWidget,
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 340,
                            // Panels can exceed the viewport height; let them scroll.
                            child: SingleChildScrollView(child: panels),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView(
                  children: [
                    _hero(),
                    const SizedBox(height: 12),
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: gameDecoration,
                      child: AspectRatio(aspectRatio: 4 / 3, child: gameWidget),
                    ),
                    const SizedBox(height: 16),
                    panels,
                  ],
                ),
        );
      },
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.16),
            AppColors.violet.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const DartStreamLogo(size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Shard Pilot',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Live demo game driven by DartStream — flags, inventory, '
                  'cloud-save & reactive events.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _heroStat(
            'HIGH',
            _resumeSummary.contains('high')
                ? _resumeSummary.split('·').first.replaceAll('high', '').trim()
                : '—',
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          title: 'Shard Pilot — how to play',
          child: const Text(
            'Drag (or ←/→/↑/↓, WASD) to fly; cannons fire automatically at the '
            'swarm. Tap or Space fires an EMP (from inventory) to clear the screen. '
            'Dodge enemies (a hit gives you brief shield-flash immunity) and grab '
            'the glowing cyan shards for bonus points.\n\n'
            'DartStream drives the rules: feature flags double_score (twin cannons) '
            '/ hard_mode (swarm) / extra_life (extra shield) change gameplay; '
            'inventory grants the EMP; cloud-save persists & resumes your high '
            'score; every beat logs a reactive event.',
          ),
        ),
        _panel(
          title: 'Cloud save · $_projectId/$_environmentId',
          child: Text(
            switch (_saveStatus) {
              _SaveStatus.idle =>
                'Resumed: $_resumeSummary (slot=$_slotKey, '
                    'scope=$_projectId/$_environmentId)',
              _SaveStatus.saving => 'Saving snapshot…',
              _SaveStatus.saved => 'Snapshot saved.',
              _SaveStatus.error => 'Snapshot save FAILED.',
            },
            style: TextStyle(
              color: _saveStatus == _SaveStatus.error
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        ),
        _panel(title: 'Last reactive event', child: Text(_lastEvent)),
        _panel(
          title: 'Profile (experience/profiles/me)',
          child: Text(
            _profile == null
                ? '—'
                : (_profile!['profile'] is Map
                      ? _kvLines(_profile!['profile'] as Map, const [
                          'displayName',
                          'providerKey',
                          'mode',
                        ])
                      : _profile!.toString()),
          ),
        ),
        _panel(
          title: 'Inventory (${_inventory.length})',
          child: _inventory.isEmpty
              ? const Text('(empty)')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in _inventory.take(8))
                      Text(_describeItem(item)),
                  ],
                ),
        ),
        _panel(
          title: 'Feature flags (${_flags.length})',
          child: _flags.isEmpty
              ? const Text('(none enabled)')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in _flags.take(8)) Text(f.toString()),
                  ],
                ),
        ),
        _panel(
          title: 'Streaming channels (${_channels.length})',
          child: _channels.isEmpty
              ? const Text('(none)')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in _channels.take(8)) Text(c.toString()),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 13,
              height: 1.4,
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  String _kvLines(Map m, List<String> keys) {
    final parts = <String>[];
    for (final k in keys) {
      if (m[k] != null) parts.add('$k: ${m[k]}');
    }
    return parts.join('\n');
  }

  String _describeItem(dynamic item) {
    if (item is Map) {
      final id = item['itemId'] ?? item['id'] ?? '?';
      final qty = item['quantity'] ?? 1;
      final type = item['itemType'] ?? '';
      return '• $id  ×$qty${type.toString().isEmpty ? '' : '  ($type)'}';
    }
    return '• ${item.toString()}';
  }
}
