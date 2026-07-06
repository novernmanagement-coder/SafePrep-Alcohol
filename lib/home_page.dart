import 'dart:async';
import 'package:flutter/material.dart';
import 'constants.dart';
import 'app_state.dart';
import 'csv_loader.dart';
import 'app_state_persistence.dart';
import 'readiness_engine.dart';
import 'assessment_info_page.dart';
import 'dashboard_page.dart';
import 'settings_page.dart';
import 'sixty_second_refresh_page.dart';
import 'about_proctors_page.dart';
import 'final_exam_intro_page.dart';
import 'peace_of_mind_page.dart';
import 'safe_prep_nav_bar.dart';
import 'trial_timer_service.dart';
import 'mixpanel_service.dart';
import 'preview/preview_reveal_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final AppState _state = AppState();
  String _currentFact = '';
  List<MilestoneModel> _milestones = [];

  Timer? _displayTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFacts();
    _loadMilestones();

    // Mixpanel app_name code for SafePrep Alcohol, following the same
    // SP / ES / SR taxonomy used across the ecosystem.
    MixpanelService.instance.track(
      'session_start',
      properties: {'is_unlocked': _state.hasUnlockedApp, 'app_name': 'SA'},
    );
    MixpanelService.instance.track(
      'home_viewed',
      properties: {'is_unlocked': _state.hasUnlockedApp, 'app_name': 'SA'},
    );

    if (!_state.hasUnlockedApp) {
      MixpanelService.instance.track(
        'trial_started',
        properties: {'app_name': 'SA'},
      );
      if (!TrialTimerService.instance.isExpired) {
        TrialTimerService.instance.onTrialExpired = _onTrialExpired;
        TrialTimerService.instance.start();
        _startDisplayTicker();
      } else {
        _onTrialExpired();
      }
    }
  }

  void _startDisplayTicker() {
    _displayTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _displayTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      MixpanelService.instance.track(
        'session_end',
        properties: {'app_name': 'SA'},
      );
    }
  }

  void _onTrialExpired() {
    MixpanelService.instance.track(
      'trial_expired',
      properties: {'app_name': 'SA'},
    );
    _displayTicker?.cancel();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PreviewRevealPage()),
      (route) => false,
    );
  }

  void _checkUnlockTrophy() {
    if (_state.hasUnlockedApp &&
        !_state.earnedTrophyIds.contains('AppUnlocked')) {
      _state.addEarnedMilestone('AppUnlocked', 'SafePrep Unlocked');
      AppStatePersistence.save();
    }
  }

  Future<void> _loadFacts() async {
    final facts = await FactLoader.loadAll();
    if (mounted) {
      setState(() {
        _currentFact = facts.map((f) => f.fact).join('  •  ');
      });
    }
  }

  Future<void> _loadMilestones() async {
    final all = await MilestoneLoader.loadAll();
    if (mounted) {
      _checkUnlockTrophy();
      _state.readinessScore = ReadinessEngine.calculate(_state);
      _state.readinessCoachMessage = ReadinessEngine.coachMessage(
        _state,
        _state.readinessScore,
      );
      _state.readinessCheerMessage = ReadinessEngine.cheerleaderMessage(
        _state,
        _state.readinessScore,
      );
      setState(() => _milestones = all);
    }
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.primaryButtonHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryButton,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.buttonCornerRadius),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: AppFonts.button)),
      ),
    );
  }

  // ── Trial countdown display (replaces the curriculum button during
  // trial) — PASSIVE, no tap action.
  Widget _buildTrialCountdown() {
    final remaining = TrialTimerService.instance.remainingSeconds;
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');

    return Container(
      width: double.infinity,
      height: AppSizes.primaryButtonHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(AppSizes.buttonCornerRadius),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
      ),
      child: Text(
        'Trial — $minutes:$seconds',
        style: const TextStyle(
          color: Color(0xFFD4AF37),
          fontSize: AppFonts.button,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTrophySection() {
    if (_milestones.isEmpty) return const SizedBox();

    final topTwo = _milestones.take(2).toList();
    final earnedCount = topTwo
        .where((m) => _state.earnedTrophyIds.contains(m.trigger))
        .length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8D5A0)),
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          const Text(
            'My Trophies',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const Spacer(),
          Text(
            '$earnedCount of ${topTwo.length} earned',
            style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterSection() {
    final state = _state;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        spacing: 2,
        children: [
          if (state.isLifetime)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '⭐ SafePrep™ Lifetime Member',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFF0C575),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Text(
            AppStrings.footerLine1,
            style: TextStyle(
              fontSize: AppFonts.footer,
              color: AppColors.footerText,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            AppStrings.footerLine2,
            style: TextStyle(
              fontSize: AppFonts.footer,
              color: AppColors.footerText,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            AppStrings.footerLine3,
            style: TextStyle(
              fontSize: AppFonts.footer,
              color: AppColors.starMotifBlue,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.servSafeBlue,
      body: SafeArea(
        child: Padding(
          padding: AppSizes.pageMargin,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Safe',
                      style: TextStyle(
                        fontSize: AppFonts.header,
                        fontWeight: FontWeight.w600,
                        color: AppColors.bodyText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Image.asset('Assets/splash.png', width: 36, height: 36),
                    const SizedBox(width: 6),
                    Text(
                      'Prep™',
                      style: TextStyle(
                        fontSize: AppFonts.header,
                        fontWeight: FontWeight.w600,
                        color: AppColors.bodyText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 32,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F0E8),
                  border: Border.all(color: const Color(0xFFC8B89A)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _currentFact.isEmpty
                      ? const SizedBox()
                      : Marquee(text: _currentFact),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    spacing: AppSizes.cardSpacing,
                    children: [
                      _state.hasUnlockedApp
                          ? Column(
                              spacing: 2,
                              children: [
                                _buildButton(
                                  'Create my personalized curriculum',
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AssessmentInfoPage(),
                                    ),
                                  ),
                                ),
                                Text(
                                  '(Recommended first step)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.subtleText,
                                  ),
                                ),
                              ],
                            )
                          : _buildTrialCountdown(),

                      _buildButton(
                        'The SafePrep™ Dashboard',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DashboardPage(),
                          ),
                        ),
                      ),
                      _buildButton(
                        'When Your Ready - Take the Exam',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FinalExamIntroPage(),
                          ),
                        ),
                      ),
                      _buildButton(
                        'Settings and information',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: AppSizes.primaryButtonHeight,
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PeaceOfMindPage(),
                            ),
                          ).then((_) => setState(() {})),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryButton,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppSizes.buttonCornerRadius,
                              ),
                            ),
                          ),
                          child: const Text(
                            '🔓 60 Second Trainers',
                            style: TextStyle(
                              fontSize: AppFonts.button,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: AppSizes.primaryButtonHeight,
                              child: ElevatedButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SixtySecondRefreshPage(),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryButton,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSizes.buttonCornerRadius,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  '⏱ 60-Second Refresh',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SizedBox(
                              height: AppSizes.primaryButtonHeight,
                              child: ElevatedButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AboutProctorsPage(),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryButton,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSizes.buttonCornerRadius,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  '👤 About Proctors',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      _buildTrophySection(),
                      _buildFooterSection(),
                    ],
                  ),
                ),
              ),
              const SafePrepNavBar(),
            ],
          ),
        ),
      ),
    );
  }
}

class Marquee extends StatefulWidget {
  final String text;
  const Marquee({super.key, required this.text});

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() async {
    await Future.delayed(const Duration(seconds: 2));
    const double pixelsPerSecond = 150; // tuned for long, growing fact lists

    while (mounted) {
      if (!_scrollController.hasClients) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      final durationSeconds = (maxExtent / pixelsPerSecond).clamp(5, 300);
      await _scrollController.animateTo(
        maxExtent,
        duration: Duration(milliseconds: (durationSeconds * 1000).round()),
        curve: Curves.linear,
      );
      if (!mounted) break;
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          widget.text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF4A3728)),
        ),
      ),
    );
  }
}
