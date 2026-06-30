import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gameplay configuration derived from live DartStream services:
/// - feature flags re-theme the rules (twin cannons, swarm, extra shield),
/// - inventory grants the EMP smart-bomb (clears the screen),
/// - a cloud-save snapshot resumes the high score / lifetime kills.
///
/// NB: field names are kept identical to the previous game so the app shell
/// (`home_screen._buildConfig`) and the live experience/flag/inventory wiring
/// keep working unchanged — only the on-screen game is new.
class PilotConfig {
  const PilotConfig({
    this.startLives = 3,
    this.doubleScore = false,
    this.hardMode = false,
    this.swordCharges = 0,
    this.resumeHighScore = 0,
    this.resumeLifetimeCoins = 0,
    this.playerName = 'Player',
  });

  final int startLives;

  /// flag `double_score` → twin cannons + 2× score.
  final bool doubleScore;

  /// flag `hard_mode` → faster, denser enemy swarm.
  final bool hardMode;

  /// inventory `starter-sword` → EMP charges (clear the screen).
  final int swordCharges;
  final int resumeHighScore;
  final int resumeLifetimeCoins;
  final String playerName;
}

/// "Shard Pilot" — a forgiving top-down space shooter. Fly the ship, auto-fire
/// on the swarm, grab bonus shards, and EMP when overwhelmed. Every gameplay
/// beat is wired to a DartStream service via [onSnapshot] (cloud-save) and
/// [onEvent] (reactive event log).
class ShardPilotGame extends FlameGame
    with HasCollisionDetection, TapCallbacks, DragCallbacks, KeyboardEvents {
  ShardPilotGame({
    required this.config,
    required this.onSnapshot,
    required this.onEvent,
  });

  final PilotConfig config;
  final void Function(Map<String, dynamic> snapshot) onSnapshot;
  final void Function(String type, Map<String, dynamic> payload) onEvent;

  late ShipPlayer player;

  int score = 0;
  int level = 1;
  int kills = 0;
  int lives = 3;
  int highScore = 0;
  int lifetimeKills = 0;
  int empCharges = 0;
  bool gameOver = false;

  final _rng = math.Random();
  double _spawnTimer = 0;
  double _fireTimer = 0;
  double _shardTimer = 0;
  double _shake = 0;

  TextComponent? _hud;
  TextComponent? _modHud;
  TextComponent? _banner;

  // Gentler difficulty curve than the old game — accessible for a demo.
  double get _enemySpeed => (config.hardMode ? 125 : 92) + (level - 1) * 13;
  double get _spawnInterval =>
      math.max(0.5, (config.hardMode ? 0.85 : 1.05) - (level - 1) * 0.045);
  static const double _fireInterval = 0.16;
  static const int _killsPerLevel = 12;

  @override
  Color backgroundColor() => const Color(0xFF060912);

  @override
  Future<void> onLoad() async {
    lives = config.startLives;
    highScore = config.resumeHighScore;
    lifetimeKills = config.resumeLifetimeCoins;
    empCharges = config.swordCharges;

    add(Nebula()..priority = -20);
    add(Starfield(count: 95)..priority = -10);

    player = ShipPlayer()
      ..position = Vector2(size.x / 2, size.y - 64)
      ..invuln = 1.2;
    add(player);

    _hud = TextComponent(
      position: Vector2(12, 12),
      priority: 100,
      textRenderer: _text(16, const Color(0xFFFFFFFF), FontWeight.w700),
    );
    add(_hud!);
    _modHud = TextComponent(
      anchor: Anchor.topRight,
      position: Vector2(size.x - 12, 12),
      priority: 100,
      textRenderer: _text(12, const Color(0xFF8BA0C8)),
    );
    add(_modHud!);

    _updateHud();
    onEvent('game.start', {
      'player': config.playerName,
      'doubleScore': config.doubleScore,
      'hardMode': config.hardMode,
      'startLives': lives,
      'empCharges': empCharges,
    });
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      player.position.x = player.position.x.clamp(0, size.x);
      player.position.y = player.position.y.clamp(size.y * 0.5, size.y - 36);
      _modHud?.position = Vector2(size.x - 12, 12);
      _banner?.position = size / 2;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_shake > 0) _shake = math.max(0, _shake - dt * 60);
    if (gameOver) return;

    _spawnTimer += dt;
    if (_spawnTimer >= _spawnInterval) {
      _spawnTimer = 0;
      _spawnEnemy();
    }

    _fireTimer += dt;
    if (_fireTimer >= _fireInterval) {
      _fireTimer = 0;
      _fire();
    }

    // Bonus shards drift in every few seconds — pure upside, no penalty.
    _shardTimer += dt;
    if (_shardTimer >= 4.5) {
      _shardTimer = 0;
      _spawnShard();
    }
  }

  // Screen-shake the whole scene on impacts for "juice".
  @override
  void render(Canvas canvas) {
    if (_shake > 0) {
      canvas.save();
      canvas.translate(
        (_rng.nextDouble() - 0.5) * _shake,
        (_rng.nextDouble() - 0.5) * _shake,
      );
      super.render(canvas);
      canvas.restore();
    } else {
      super.render(canvas);
    }
  }

  void _spawnEnemy() {
    final x = 24 + _rng.nextDouble() * (size.x - 48);
    final big = _rng.nextDouble() < 0.18;
    add(Enemy(speed: _enemySpeed * (big ? 0.7 : 1), big: big)
      ..position = Vector2(x, -24));
  }

  void _spawnShard() {
    final x = 28 + _rng.nextDouble() * (size.x - 56);
    add(Shard(speed: 70 + _rng.nextDouble() * 30)..position = Vector2(x, -20));
  }

  void _fire() {
    final guns = config.doubleScore
        ? [
            player.position + Vector2(-12, -18),
            player.position + Vector2(12, -18),
          ]
        : [player.position + Vector2(0, -20)];
    for (final p in guns) {
      add(Bullet()..position = p.clone());
      add(MuzzleFlash(position: p.clone()));
    }
  }

  void destroyEnemy(Enemy e) {
    if (gameOver || e.dead) return;
    e.dead = true;
    final gain = (config.doubleScore ? 20 : 10) * (e.big ? 2 : 1);
    add(Burst(position: e.position.clone(), color: const Color(0xFFFFC857)));
    add(FloatingText(
      position: e.position.clone(),
      text: '+$gain',
      color: const Color(0xFFFFD479),
    ));
    e.removeFromParent();
    score += gain;
    kills += 1;
    lifetimeKills += 1;
    if (score > highScore) highScore = score;
    if (kills % _killsPerLevel == 0) {
      level += 1;
      onEvent('game.level.up', {'level': level, 'score': score});
    }
    _updateHud();
    _emitSnapshot();
  }

  void collectShard(Shard s) {
    if (gameOver || s.dead) return;
    s.dead = true;
    const gain = 25;
    add(Burst(position: s.position.clone(), color: const Color(0xFF5BE7C4)));
    add(FloatingText(
      position: s.position.clone(),
      text: '+$gain',
      color: const Color(0xFF7CF2D6),
    ));
    s.removeFromParent();
    score += gain;
    if (score > highScore) highScore = score;
    onEvent('game.bonus', {'kind': 'shard', 'score': score});
    _updateHud();
    _emitSnapshot();
  }

  // Only a direct collision with the ship costs a life (and only when the
  // ship isn't in its post-hit invulnerability window). Enemies that slip past
  // the bottom simply despawn — much more forgiving.
  void damagePlayer(Enemy e) {
    if (gameOver || e.dead) return;
    e.dead = true;
    add(Burst(position: e.position.clone(), color: const Color(0xFFE5484D)));
    e.removeFromParent();
    if (player.invuln > 0) return;
    lives -= 1;
    _shake = 14;
    player.invuln = 1.6;
    onEvent('game.hit', {'livesLeft': lives, 'score': score});
    _updateHud();
    if (lives <= 0) _endGame();
  }

  void useEmp() {
    if (gameOver || empCharges <= 0) return;
    final enemies = children.whereType<Enemy>().where((e) => !e.dead).toList();
    if (enemies.isEmpty) return;
    for (final e in enemies) {
      e.dead = true;
      final gain = (config.doubleScore ? 20 : 10) * (e.big ? 2 : 1);
      add(Burst(position: e.position.clone(), color: const Color(0xFF5BC0FF)));
      e.removeFromParent();
      score += gain;
      kills += 1;
      lifetimeKills += 1;
    }
    if (score > highScore) highScore = score;
    empCharges -= 1;
    _shake = 10;
    onEvent('game.emp.used', {'cleared': enemies.length, 'left': empCharges});
    _updateHud();
    _emitSnapshot();
  }

  void _endGame() {
    gameOver = true;
    for (final e in children.whereType<Enemy>().toList()) {
      e.removeFromParent();
    }
    _banner = TextComponent(
      text: 'GAME OVER\nScore $score · High $highScore\ntap / R to relaunch',
      anchor: Anchor.center,
      position: size / 2,
      priority: 100,
      textRenderer: _text(22, const Color(0xFFFFFFFF), FontWeight.w800),
    );
    add(_banner!);
    onEvent('game.over', {
      'score': score,
      'highScore': highScore,
      'level': level,
      'kills': kills,
      'lifetimeKills': lifetimeKills,
    });
    _emitSnapshot();
  }

  void _restart() {
    if (!gameOver) return;
    _banner?.removeFromParent();
    _banner = null;
    for (final b in children.whereType<Bullet>().toList()) {
      b.removeFromParent();
    }
    for (final s in children.whereType<Shard>().toList()) {
      s.removeFromParent();
    }
    score = 0;
    kills = 0;
    level = 1;
    lives = config.startLives;
    empCharges = config.swordCharges;
    gameOver = false;
    player.position = Vector2(size.x / 2, size.y - 64);
    player.invuln = 1.2;
    _updateHud();
    onEvent('game.start', {'player': config.playerName, 'restart': true});
  }

  void _emitSnapshot() {
    onSnapshot({
      'score': score,
      'highScore': highScore,
      'level': level,
      'lives': lives,
      'kills': kills,
      // Legacy key kept so resume (reads `lifetimeCoins`) keeps working.
      'lifetimeCoins': lifetimeKills,
      'lifetimeKills': lifetimeKills,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void _updateHud() {
    _hud?.text =
        'Score $score   Lv $level   Shields $lives\n'
        'High $highScore   Kills $lifetimeKills';
    final mods = <String>[
      if (config.doubleScore) 'double_score (twin cannons)',
      if (config.hardMode) 'hard_mode (swarm)',
    ];
    _modHud?.text = [
      config.playerName,
      if (mods.isNotEmpty) 'flags: ${mods.join(', ')}',
      if (empCharges > 0) 'EMP ×$empCharges (space)',
    ].join('\n');
  }

  TextPaint _text(double size, Color color, [FontWeight w = FontWeight.w500]) =>
      TextPaint(style: TextStyle(color: color, fontSize: size, fontWeight: w));

  // ---- input -------------------------------------------------------------

  @override
  void onTapDown(TapDownEvent event) {
    if (gameOver) {
      _restart();
    } else {
      useEmp();
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (gameOver) return;
    player.moveBy(event.localDelta);
  }

  @override
  KeyEventResult onKeyEvent(
      KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (gameOver) {
      if (event is KeyDownEvent &&
          (keysPressed.contains(LogicalKeyboardKey.enter) ||
              keysPressed.contains(LogicalKeyboardKey.keyR) ||
              keysPressed.contains(LogicalKeyboardKey.space))) {
        _restart();
      }
      return KeyEventResult.handled;
    }
    final left = keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);
    final right = keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);
    final up = keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW);
    final down = keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS);
    player.vx = (right ? 330.0 : 0) - (left ? 330.0 : 0);
    player.vy = (down ? 260.0 : 0) - (up ? 260.0 : 0);
    if (event is KeyDownEvent &&
        keysPressed.contains(LogicalKeyboardKey.space)) {
      useEmp();
    }
    return KeyEventResult.handled;
  }
}

/// Soft nebula gradient behind the starfield for depth/mood. Cheap: two radial
/// gradients painted once per frame.
class Nebula extends PositionComponent with HasGameReference<ShardPilotGame> {
  @override
  void render(Canvas canvas) {
    final s = game.size;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.x, s.y),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(s.x * 0.3, s.y * 0.25),
          s.y * 0.9,
          [const Color(0xFF1B2A55).withValues(alpha: 0.55), const Color(0x00000000)],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.x, s.y),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(s.x * 0.8, s.y * 0.7),
          s.y * 0.8,
          [const Color(0xFF3A1B55).withValues(alpha: 0.45), const Color(0x00000000)],
        ),
    );
  }
}

/// Three-layer parallax starfield with gentle twinkle.
class Starfield extends PositionComponent with HasGameReference<ShardPilotGame> {
  Starfield({required this.count});

  final int count;
  final _rng = math.Random();
  final List<_Star> _field = [];
  double _t = 0;

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < count; i++) {
      _field.add(_newStar(initial: true));
    }
  }

  _Star _newStar({bool initial = false}) {
    final layer = _rng.nextInt(3); // 0 = far, 2 = near
    return _Star(
      x: _rng.nextDouble() * game.size.x,
      y: initial ? _rng.nextDouble() * game.size.y : -2,
      speed: 22.0 + layer * 34 + _rng.nextDouble() * 14,
      radius: 0.6 + layer * 0.7,
      alpha: 0.3 + layer * 0.22,
      phase: _rng.nextDouble() * 6.28,
    );
  }

  @override
  void update(double dt) {
    _t += dt;
    for (var i = 0; i < _field.length; i++) {
      final s = _field[i];
      s.y += s.speed * dt;
      if (s.y > game.size.y + 2) _field[i] = _newStar();
    }
  }

  @override
  void render(Canvas canvas) {
    for (final s in _field) {
      final twinkle = 0.75 + 0.25 * math.sin(_t * 2 + s.phase);
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.radius,
        Paint()
          ..color = const Color(0xFFCBD8FF).withValues(alpha: s.alpha * twinkle),
      );
    }
  }
}

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.speed,
    required this.radius,
    required this.alpha,
    required this.phase,
  });
  double x;
  double y;
  final double speed;
  final double radius;
  final double alpha;
  final double phase;
}

class ShipPlayer extends PositionComponent
    with HasGameReference<ShardPilotGame>, CollisionCallbacks {
  ShipPlayer() : super(size: Vector2(42, 38), anchor: Anchor.center);

  double vx = 0;
  double vy = 0;
  double invuln = 0; // seconds of post-hit / spawn immunity
  double _thrust = 0;

  void moveBy(Vector2 delta) {
    x = (x + delta.x).clamp(size.x / 2, game.size.x - size.x / 2);
    y = (y + delta.y).clamp(game.size.y * 0.5, game.size.y - size.y / 2);
  }

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(size: Vector2(28, 26), anchor: Anchor.center)
      ..position = size / 2);
  }

  @override
  void update(double dt) {
    if (invuln > 0) invuln = math.max(0, invuln - dt);
    if (vx != 0) {
      x = (x + vx * dt).clamp(size.x / 2, game.size.x - size.x / 2);
    }
    if (vy != 0) {
      y = (y + vy * dt).clamp(game.size.y * 0.5, game.size.y - size.y / 2);
    }
    _thrust = (_thrust + dt * 12) % (2 * math.pi);
  }

  @override
  void render(Canvas canvas) {
    // Blink while invulnerable.
    if (invuln > 0 && ((invuln * 12).floor().isEven)) return;

    final w = size.x, h = size.y;
    // Engine glow / thrust flicker.
    final flame = 6 + 3 * math.sin(_thrust).abs();
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.38, h)
        ..lineTo(w * 0.5, h + flame)
        ..lineTo(w * 0.62, h)
        ..close(),
      Paint()..color = const Color(0xFFFF8A3D).withValues(alpha: 0.9),
    );
    // Hull (arrow pointing up) with a soft outer glow.
    final hull = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h * 0.85)
      ..lineTo(w * 0.5, h * 0.66)
      ..lineTo(0, h * 0.85)
      ..close();
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFF3DBEFF).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(hull, Paint()..color = const Color(0xFF3DBEFF));
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFFBDEBFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      Offset(w / 2, h * 0.42),
      4,
      Paint()..color = const Color(0xFF0B2740),
    );
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Enemy) {
      game.damagePlayer(other);
    } else if (other is Shard) {
      game.collectShard(other);
    }
  }
}

class Bullet extends PositionComponent with CollisionCallbacks {
  Bullet() : super(size: Vector2(4, 14), anchor: Anchor.center);

  static const double _speed = 560;

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    y -= _speed * dt;
    if (y < -20) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-1, -1, size.x + 2, size.y + 2),
        const Radius.circular(3),
      ),
      Paint()
        ..color = const Color(0xFF9BE7FF).withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFD9F6FF),
    );
  }
}

/// Brief bright flash at the muzzle when a shot fires.
class MuzzleFlash extends PositionComponent {
  MuzzleFlash({required Vector2 position})
      : super(position: position, anchor: Anchor.center, priority: 5);

  double _age = 0;
  static const double _life = 0.09;

  @override
  void update(double dt) {
    _age += dt;
    if (_age >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (1 - _age / _life).clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset.zero,
      5 * t + 1,
      Paint()..color = const Color(0xFFBDEBFF).withValues(alpha: t),
    );
  }
}

class Enemy extends PositionComponent with CollisionCallbacks {
  Enemy({required this.speed, this.big = false})
      : super(
          size: big ? Vector2(42, 38) : Vector2(30, 28),
          anchor: Anchor.center,
        );

  final double speed;
  final bool big;
  bool dead = false;
  double _t = 0;

  @override
  Future<void> onLoad() async {
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    _t += dt;
    y += speed * dt;
    // Gentle weave so they don't all fall in straight lines.
    x += math.sin(_t * 2 + y * 0.01) * 18 * dt;
    final game = findGame() as ShardPilotGame?;
    if (game != null && !dead && y > game.size.y + 16) {
      removeFromParent(); // breach = despawn, no penalty
    }
  }

  @override
  void render(Canvas canvas) {
    final w = size.x, h = size.y;
    final base = big ? const Color(0xFFB23BD6) : const Color(0xFFE5484D);
    final edge = big ? const Color(0xFFE7B4FF) : const Color(0xFFFFB4B6);
    final body = Path()
      ..moveTo(w * 0.5, h)
      ..lineTo(0, h * 0.25)
      ..lineTo(w * 0.25, 0)
      ..lineTo(w * 0.75, 0)
      ..lineTo(w, h * 0.25)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..color = base.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(body, Paint()..color = base);
    canvas.drawPath(
      body,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final eye = Paint()..color = const Color(0xFF240612);
    canvas.drawCircle(Offset(w * 0.34, h * 0.32), big ? 3.2 : 2.4, eye);
    canvas.drawCircle(Offset(w * 0.66, h * 0.32), big ? 3.2 : 2.4, eye);
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (dead) return;
    final game = findGame() as ShardPilotGame?;
    if (game == null) return;
    if (other is Bullet) {
      other.removeFromParent();
      game.destroyEnemy(this);
    } else if (other is ShipPlayer) {
      game.damagePlayer(this);
    }
  }
}

/// A bonus collectible — fly into it for points. Missing it has no penalty.
class Shard extends PositionComponent with CollisionCallbacks {
  Shard({required this.speed}) : super(size: Vector2(20, 20), anchor: Anchor.center);

  final double speed;
  bool dead = false;
  double _t = 0;
  double _baseX = 0;

  @override
  Future<void> onLoad() async {
    _baseX = x;
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    _t += dt;
    y += speed * dt;
    x = _baseX + math.sin(_t * 3) * 16;
    final game = findGame() as ShardPilotGame?;
    if (game != null && y > game.size.y + 20) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final w = size.x, h = size.y;
    final pulse = 0.7 + 0.3 * math.sin(_t * 6);
    final gem = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.5)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.5)
      ..close();
    canvas.drawPath(
      gem,
      Paint()
        ..color = const Color(0xFF5BE7C4).withValues(alpha: 0.5 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(gem, Paint()..color = const Color(0xFF7CF2D6));
    canvas.drawPath(
      gem,
      Paint()
        ..color = const Color(0xFFEFFFFB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (dead) return;
    if (other is ShipPlayer) {
      (findGame() as ShardPilotGame?)?.collectShard(this);
    }
  }
}

/// Floating score popup that rises and fades.
class FloatingText extends PositionComponent {
  FloatingText({
    required Vector2 position,
    required this.text,
    required this.color,
  }) : super(position: position, anchor: Anchor.center, priority: 60);

  final String text;
  final Color color;
  double _age = 0;
  static const double _life = 0.7;

  @override
  void update(double dt) {
    _age += dt;
    position.y -= 30 * dt;
    if (_age >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (1 - _age / _life).clamp(0.0, 1.0);
    TextPaint(
      style: TextStyle(
        color: color.withValues(alpha: t),
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    ).render(canvas, text, Vector2.zero(), anchor: Anchor.center);
  }
}

/// A short-lived particle burst (expanding, fading sparks) for explosions.
class Burst extends PositionComponent {
  Burst({required Vector2 position, required this.color})
      : super(position: position, anchor: Anchor.center, priority: 40);

  final Color color;
  final _rng = math.Random();
  final List<_Spark> _sparks = [];
  double _age = 0;
  static const double _life = 0.45;

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < 10; i++) {
      final a = _rng.nextDouble() * 2 * math.pi;
      final speed = 40 + _rng.nextDouble() * 120;
      _sparks.add(_Spark(
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        radius: 1.5 + _rng.nextDouble() * 2,
      ));
    }
  }

  @override
  void update(double dt) {
    _age += dt;
    for (final s in _sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
    }
    if (_age >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (1 - _age / _life).clamp(0.0, 1.0);
    final paint = Paint()..color = color.withValues(alpha: t);
    for (final s in _sparks) {
      canvas.drawCircle(Offset(s.x, s.y), s.radius * t, paint);
    }
  }
}

class _Spark {
  _Spark({required this.vx, required this.vy, required this.radius});
  double x = 0;
  double y = 0;
  final double vx;
  final double vy;
  final double radius;
}
