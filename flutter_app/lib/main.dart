import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const SentinelApp());
}

// ─── APP ROOT ────────────────────────────────────────────────────────────────
class SentinelApp extends StatelessWidget {
  const SentinelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SENTINEL — Fraud Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF111827),
          primary: Color(0xFF3B82F6),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        fontFamily: 'monospace',
      ),
      home: const FraudDetectionScreen(),
    );
  }
}

// ─── COLORS ──────────────────────────────────────────────────────────────────
class AppColors {
  static const bg       = Color(0xFF0A0E1A);
  static const bg2      = Color(0xFF111827);
  static const bg3      = Color(0xFF1A2235);
  static const border   = Color(0xFF2A3A5C);
  static const text     = Color(0xFFE2E8F0);
  static const text2    = Color(0xFF94A3B8);
  static const text3    = Color(0xFF64748B);
  static const green    = Color(0xFF22C55E);
  static const amber    = Color(0xFFF59E0B);
  static const red      = Color(0xFFEF4444);
  static const blue     = Color(0xFF3B82F6);
  static const purple   = Color(0xFFA855F7);
  static const cyan     = Color(0xFF06B6D4);
}

// ─── RISK RESULT MODEL ───────────────────────────────────────────────────────
class RiskResult {
  final int riskScore;
  final String decision;
  final List<String> reasons;
  final Map<String, bool> flags;
  final Map<String, dynamic>? cluster;

  RiskResult({
    required this.riskScore,
    required this.decision,
    required this.reasons,
    required this.flags,
    this.cluster,
  });

  factory RiskResult.fromJson(Map<String, dynamic> json) {
    return RiskResult(
      riskScore: json['riskScore'] as int,
      decision: json['decision'] as String,
      reasons: List<String>.from(json['reasons'] ?? []),
      flags: Map<String, bool>.from(json['flags'] ?? {}),
      cluster: json['cluster'] as Map<String, dynamic>?,
    );
  }

  Color get statusColor {
    switch (decision) {
      case 'ALLOW':    return AppColors.green;
      case 'RESTRICT': return AppColors.amber;
      case 'BLOCK':    return AppColors.red;
      default:         return AppColors.text3;
    }
  }

  String get statusEmoji {
    switch (decision) {
      case 'ALLOW':    return '✅';
      case 'RESTRICT': return '⚠️';
      case 'BLOCK':    return '🔴';
      default:         return '—';
    }
  }
}

// ─── MAIN SCREEN ─────────────────────────────────────────────────────────────
class FraudDetectionScreen extends StatefulWidget {
  const FraudDetectionScreen({super.key});

  @override
  State<FraudDetectionScreen> createState() => _FraudDetectionScreenState();
}

class _FraudDetectionScreenState extends State<FraudDetectionScreen> {
  final _userIdCtrl   = TextEditingController(text: 'U123');
  final _deviceIdCtrl = TextEditingController(text: 'DEV-001');

  double _lat   = 28.61;
  double _lng   = 77.21;
  double _speed = 30;

  bool _loading = false;
  RiskResult? _result;

  int _total = 0, _allow = 0, _restrict = 0, _block = 0;
  final List<Map<String, dynamic>> _log = [];

  // ── BACKEND URL — change to your server IP if running on device ────────────
  static const _baseUrl = 'https://veritrust-engine.onrender.com';

  // ── SCENARIO PRESETS ───────────────────────────────────────────────────────
  void _loadScenario(String type) {
    final scenarios = {
      'normal':   {'uid':'U001','did':'DEV-001','lat':28.61,'lng':77.21,'spd':25.0},
      'speed':    {'uid':'U002','did':'DEV-002','lat':19.07,'lng':72.87,'spd':140.0},
      'teleport': {'uid':'U003','did':'DEV-003','lat':40.71,'lng':-74.00,'spd':30.0},
      'device':   {'uid':'U005','did':'DEV-SHARED','lat':12.97,'lng':77.59,'spd':20.0},
    };
    final s = scenarios[type]!;
    setState(() {
      _userIdCtrl.text   = s['uid'] as String;
      _deviceIdCtrl.text = s['did'] as String;
      _lat   = s['lat'] as double;
      _lng   = s['lng'] as double;
      _speed = s['spd'] as double;
    });
    Future.delayed(const Duration(milliseconds: 200), _simulate);
  }

  // ── SIMULATE (calls backend) ───────────────────────────────────────────────
  Future<void> _simulate() async {
    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId':   _userIdCtrl.text,
          'deviceId': _deviceIdCtrl.text,
          'lat':      _lat,
          'lng':      _lng,
          'speed':    _speed.round(),
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = RiskResult.fromJson(data);

      setState(() {
        _result = result;
        _total++;
        if (result.decision == 'ALLOW')    _allow++;
        if (result.decision == 'RESTRICT') _restrict++;
        if (result.decision == 'BLOCK')    _block++;
        _log.insert(0, {
          'uid': _userIdCtrl.text,
          'did': _deviceIdCtrl.text,
          'score': result.riskScore,
          'decision': result.decision,
          'time': TimeOfDay.now().format(context),
        });
        if (_log.length > 20) _log.removeLast();
      });
    } catch (e) {
      // Offline mode: run scoring locally
      _simulateOffline();
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── OFFLINE FALLBACK (same logic as backend) ───────────────────────────────
  void _simulateOffline() {
    int risk = 0;
    final flags = <String, bool>{'speedViolation': false, 'teleportation': false, 'deviceMismatch': false};
    final reasons = <String>[];

    if (_speed > 80) {
      risk += 30; flags['speedViolation'] = true;
      reasons.add('Speed ${_speed.round()} km/h exceeds threshold');
    }

    String decision;
    if (risk >= 70)      decision = 'BLOCK';
    else if (risk >= 30) decision = 'RESTRICT';
    else                 decision = 'ALLOW';

    final result = RiskResult(
      riskScore: min(risk, 100),
      decision: decision,
      reasons: reasons,
      flags: flags,
    );

    setState(() {
      _result = result;
      _total++;
      if (decision == 'ALLOW')    _allow++;
      if (decision == 'RESTRICT') _restrict++;
      if (decision == 'BLOCK')    _block++;
      _log.insert(0, {
        'uid': _userIdCtrl.text,
        'did': _deviceIdCtrl.text,
        'score': result.riskScore,
        'decision': decision,
        'time': TimeOfDay.now().format(context),
      });
    });
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ── SIDEBAR ──
          SizedBox(
            width: 300,
            child: Container(
              color: AppColors.bg2,
              child: _buildSidebar(),
            ),
          ),
          // ── MAIN ──
          Expanded(
            child: _buildMain(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.bg3,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.blue.withOpacity(.4)),
                ),
                child: const Icon(Icons.shield, color: AppColors.blue, size: 18),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SENTINEL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 1)),
                  Text('Fraud Detection v2.0', style: TextStyle(color: AppColors.text3, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('User Identity'),
                _textInput('User ID', _userIdCtrl),
                const SizedBox(height: 10),
                _textInput('Device ID', _deviceIdCtrl),
                const SizedBox(height: 16),

                _sectionLabel('Location'),
                _sliderField('Latitude', _lat, -90, 90, (v) => setState(() => _lat = v)),
                _sliderField('Longitude', _lng, -180, 180, (v) => setState(() => _lng = v)),
                const SizedBox(height: 16),

                _sectionLabel('Movement'),
                _sliderField('Speed (km/h)', _speed, 0, 300, (v) => setState(() => _speed = v)),
                const SizedBox(height: 20),

                _sectionLabel('Demo Scenarios'),
                _scenarioBtn('✅', 'Normal User', 'Low risk → ALLOW', () => _loadScenario('normal')),
                _scenarioBtn('⚠️', 'High Speed', 'Movement anomaly → RESTRICT', () => _loadScenario('speed')),
                _scenarioBtn('🚨', 'Teleportation', 'Impossible travel → BLOCK', () => _loadScenario('teleport')),
                _scenarioBtn('💥', 'Device Fraud Ring', 'Shared device → BLOCK', () => _loadScenario('device')),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _simulate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('▶ SIMULATE ACTIVITY', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMain() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: const Row(
              children: [
                Text('Risk Analysis Console', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                SizedBox(width: 8),
                Text('Real-time fraud detection', style: TextStyle(color: AppColors.text3, fontSize: 12)),
              ],
            ),
          ),

          // Stats
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statCard('Total', _total.toString(), Colors.white),
                const SizedBox(width: 10),
                _statCard('Allowed', _allow.toString(), AppColors.green),
                const SizedBox(width: 10),
                _statCard('Restricted', _restrict.toString(), AppColors.amber),
                const SizedBox(width: 10),
                _statCard('Blocked', _block.toString(), AppColors.red),
              ],
            ),
          ),

          // Result
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildResultCard(),
          ),

          // Cluster
          if (_result?.cluster != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildClusterCard(_result!.cluster!),
            ),

          // Log
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildLog(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final r = _result;
    final statusColor = r?.statusColor ?? AppColors.text3;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border(top: BorderSide(color: statusColor, width: 3)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DECISION ENGINE', style: TextStyle(color: AppColors.text3, fontSize: 10, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Text(
                    r != null ? '${r.statusEmoji} ${r.decision}' : 'WAITING...',
                    style: TextStyle(color: statusColor, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r?.reasons.firstOrNull ?? 'Simulate an activity to see results',
                    style: const TextStyle(color: AppColors.text3, fontSize: 11),
                  ),
                ],
              ),
              Column(
                children: [
                  Text(
                    r != null ? '${r.riskScore}' : '--',
                    style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w700, height: 1),
                  ),
                  const Text('RISK SCORE', style: TextStyle(color: AppColors.text3, fontSize: 10, letterSpacing: 1)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Risk bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (r?.riskScore ?? 0) / 100,
              backgroundColor: AppColors.bg3,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 14),

          // Factor chips
          Row(
            children: [
              _factorChip('Speed', r?.flags['speedViolation'] ?? false),
              const SizedBox(width: 8),
              _factorChip('Teleportation', r?.flags['teleportation'] ?? false),
              const SizedBox(width: 8),
              _factorChip('Device Mismatch', r?.flags['deviceMismatch'] ?? false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClusterCard(Map<String, dynamic> cluster) {
    final users = List<String>.from(cluster['users'] ?? []);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.purple.withOpacity(.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub, color: AppColors.purple, size: 14),
              const SizedBox(width: 6),
              Text('CLUSTER ${cluster['clusterId']}', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700, fontSize: 12)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF1A0530), borderRadius: BorderRadius.circular(3), border: Border.all(color: AppColors.purple)),
                child: Text('${users.length} USERS', style: const TextStyle(color: AppColors.purple, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Fraud ring detected on device: ${cluster['deviceId']}', style: const TextStyle(color: AppColors.text3, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: users.map((u) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AppColors.red.withOpacity(.5)),
              ),
              child: Text(u, style: const TextStyle(color: AppColors.red, fontSize: 11)),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ACTIVITY LOG', style: TextStyle(color: AppColors.text3, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 10),
        if (_log.isEmpty)
          const Text('No activity yet', style: TextStyle(color: AppColors.text3, fontSize: 12))
        else
          ..._log.take(8).map((entry) {
            final decision = entry['decision'] as String;
            final color = decision == 'ALLOW' ? AppColors.green : decision == 'RESTRICT' ? AppColors.amber : AppColors.red;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bg2,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${entry['uid']}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12))),
                  Text('${entry['did']}', style: const TextStyle(color: AppColors.text3, fontSize: 11)),
                  const SizedBox(width: 12),
                  Text('${entry['score']}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(.1),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: color.withOpacity(.4)),
                    ),
                    child: Text(decision, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .5)),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ─── REUSABLE WIDGETS ──────────────────────────────────────────────────────
  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label.toUpperCase(), style: const TextStyle(color: AppColors.text3, fontSize: 10, letterSpacing: 1)),
  );

  Widget _textInput(String hint, TextEditingController ctrl) => TextField(
    controller: ctrl,
    style: const TextStyle(color: AppColors.text, fontSize: 12),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.text3),
      filled: true, fillColor: AppColors.bg3,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.blue)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
  );

  Widget _sliderField(String label, double value, double min, double max, ValueChanged<double> onChanged) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 11)),
          Text(value.toStringAsFixed(1), style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          activeTrackColor: AppColors.blue,
          inactiveTrackColor: AppColors.border,
          thumbColor: Colors.white,
          overlayColor: AppColors.blue.withOpacity(.15),
        ),
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
      const SizedBox(height: 4),
    ],
  );

  Widget _scenarioBtn(String icon, String title, String sub, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg3,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 11)),
              Text(sub, style: const TextStyle(color: AppColors.text3, fontSize: 10)),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _statCard(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.bg2, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 9, letterSpacing: .5)),
        ],
      ),
    ),
  );

  Widget _factorChip(String label, bool triggered) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(color: AppColors.bg3, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 9, letterSpacing: .5)),
          const SizedBox(height: 3),
          Text(
            triggered ? 'TRIGGERED' : 'CLEAR',
            style: TextStyle(color: triggered ? AppColors.red : AppColors.green, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}
