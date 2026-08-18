import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'app_state.dart';
import 'app_state_persistence.dart';
import 'mixpanel_service.dart';
import 'home_page.dart';
import 'dashboard_page.dart';
import 'intro_page.dart';
import 'preview/preview_cinematic_splash.dart';
import 'splash_navigating_page.dart';

// SafePrep Alcohol — splash flow matches SafePrep Manager exactly.
// First-ever launch holds 15 seconds; every launch after holds 5 seconds.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const bool _debugBypassPreview = false;
  static const bool _debugShowPreview = false;

  static const String _seenSplashPrefKey = 'has_seen_splash_before';
  static const int _firstLaunchHoldSeconds = 15;
  static const int _returningHoldSeconds = 5;
  // How long before the countdown number starts ticking (orientation beat).
  static const int _orientationSeconds = 2;

  // Access code. Correct entry → SplashNavigatingPage (debug menu — jump
  // straight to FSME landing, the onboarding funnel, Home, or a
  // force-unlocked Dashboard without needing a real purchase). Ported
  // from SafePrep Manager's long-press-the-logo debug entry. Anything
  // else, blank, or dismissed → dialog just closes, normal splash
  // countdown/navigation continues underneath if it hasn't already fired.
  //
  // DEBUG ONLY — REMOVE BEFORE RELEASE.
  static const String _accessCode = 'Novern2026!';

  Timer? _displayTicker;
  int _secondsElapsed = 0;

  // Resolved once prefs are read. Null until then — build() shows no
  // countdown text during that brief window.
  int? _totalHoldSeconds;

  // Guards against the auto-navigate firing after a long-press has
  // already taken the user down the debug path.
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initHoldDuration();
  }

  Future<void> _initHoldDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenBefore = prefs.getBool(_seenSplashPrefKey) ?? false;
    final holdSeconds = hasSeenBefore
        ? _returningHoldSeconds
        : _firstLaunchHoldSeconds;

    if (!hasSeenBefore) {
      await prefs.setBool(_seenSplashPrefKey, true);
    }

    if (!mounted) return;
    setState(() => _totalHoldSeconds = holdSeconds);
    _startDisplayTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate(holdSeconds));
  }

  void _startDisplayTicker() {
    _displayTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsElapsed++);
    });
  }

  @override
  void dispose() {
    _displayTicker?.cancel();
    super.dispose();
  }

  // Seconds remaining in the baked-in countdown line, once the orientation
  // beat has passed. Clamped so it never shows a negative number.
  int get _countdownRemaining {
    final total = _totalHoldSeconds ?? _returningHoldSeconds;
    final remaining = total - _secondsElapsed;
    return remaining.clamp(0, total - _orientationSeconds);
  }

  Future<void> _navigate(int holdSeconds) async {
    final state = AppState();

    // Hard-lock hold — no skip, matches the visible countdown above.
    await Future.delayed(Duration(seconds: holdSeconds));
    if (!mounted || _navigated) return;

    // Clear stale debug state
    if (state.hasUnlockedApp && state.purchaseDate == null) {
      state.reset();
      await AppStatePersistence.delete();
    }
    if (!mounted || _navigated) return;

    if (_debugShowPreview) {
      _navigated = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PreviewCinematicSplash()),
      );
      return;
    }

    if (_debugBypassPreview) {
      state.hasUnlockedApp = true;
      state.purchaseType = PurchaseType.lifetime;
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
      return;
    }

    if (state.hasUnlockedApp && state.isExpired) {
      state.hasUnlockedApp = false;
      AppStatePersistence.save();
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PreviewCinematicSplash()),
      );
      return;
    }

    if (state.hasUnlockedApp) {
      if (!state.hasSeenIntro) {
        state.clearCurriculumProgress();
        state.hasSeenIntro = true;
        AppStatePersistence.save();
      }
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
      return;
    }

    // Trial mode — go straight to DashboardPage; the splash countdown already
    // sets the expectation ("Your dashboard opens in 3...2...1...") so this
    // delivers on that promise directly.
    // TrialTimerService will fire the paywall at 30 minutes
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DashboardPage()),
    );
  }

  /// Long-press on the splash logo — reaches the debug access-code
  /// prompt. Wrong, blank, or dismissed entry just closes the dialog;
  /// the normal timed navigation continues underneath if it hasn't
  /// already fired.
  Future<void> _debugEntry() async {
    final entered = await _promptAccessCode();
    if (!mounted || _navigated) return;

    if (entered == _accessCode) {
      _navigated = true;
      _displayTicker?.cancel();
      MixpanelService.instance.track(
        'SpOn_Splash_Route',
        properties: {'app_name': 'SA', 'path': 'debug_nav_longpress'},
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SplashNavigatingPage()),
      );
    }
    // Wrong/blank/dismissed: do nothing, let normal routing proceed.
  }

  /// Shows a modal asking for the access code. Returns the entered
  /// string, or null if dismissed.
  Future<String?> _promptAccessCode() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13130F),
          title: const Text(
            'Access code',
            style: TextStyle(color: Color(0xFFF0EDE8), fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            style: const TextStyle(color: Color(0xFFF0EDE8)),
            decoration: const InputDecoration(
              hintText: 'Enter code',
              hintStyle: TextStyle(color: Color(0x66F0EDE8)),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0x33D4AF37)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFD4AF37)),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text(
                'Continue',
                style: TextStyle(color: Color(0xFFD4AF37)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showCountdown =
        _totalHoldSeconds != null && _secondsElapsed >= _orientationSeconds;

    return Scaffold(
      backgroundColor: AppColors.servSafeBlue,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onLongPress: _debugEntry,
                child: Image.asset('Assets/splash.png', width: 80, height: 80),
              ),
              const SizedBox(height: 24),

              const Text(
                '100% Guaranteed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFB8860B),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pass the ServSafe® Alcohol exam or your money back.\nWe\'ll have you ready in less than 2 hours.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.strongText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'We\'ve pre-loaded your dashboard with national averages so you can start browsing right away — watch your Readiness Score adapt as you go.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.subtleText,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 28),

              // Baked-in countdown line — replaces a standalone numeral.
              // Blank during the 2-second orientation beat, then ticks live.
              AnimatedOpacity(
                opacity: showCountdown ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Text(
                  showCountdown
                      ? 'Your dashboard opens in $_countdownRemaining\u2026'
                      : ' ',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB8860B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
