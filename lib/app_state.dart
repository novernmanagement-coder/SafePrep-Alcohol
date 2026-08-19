import 'csv_loader.dart';

enum TestType { diagnostic, finalExam }

// ── Purchase type ─────────────────────────────────────────────
enum PurchaseType { none, sevenDay, fourteenDay, lifetime }

class TestResult {
  final DateTime timestamp;
  final TestType type;
  final int overallScore;
  final Map<String, int> categoryScores;
  final List<String> missedQuestionIds;

  TestResult({
    required this.timestamp,
    required this.type,
    required this.overallScore,
    required this.categoryScores,
    required this.missedQuestionIds,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'type': type.name,
    'overallScore': overallScore,
    'categoryScores': categoryScores,
    'missedQuestionIds': missedQuestionIds,
  };

  factory TestResult.fromJson(Map<String, dynamic> json) => TestResult(
    timestamp: DateTime.parse(json['timestamp']),
    type: TestType.values.firstWhere((e) => e.name == json['type']),
    overallScore: json['overallScore'],
    categoryScores: Map<String, int>.from(json['categoryScores']),
    missedQuestionIds: List<String>.from(json['missedQuestionIds']),
  );
}

class SubcategoryGap {
  final String category;
  final String subcategory;
  int questionsAsked;
  int questionsCorrect;

  SubcategoryGap({
    required this.category,
    required this.subcategory,
    this.questionsAsked = 0,
    this.questionsCorrect = 0,
  });

  int get scorePercent =>
      questionsAsked == 0 ? 0 : (questionsCorrect * 100) ~/ questionsAsked;
}

class ConceptProgress {
  final String category;
  bool seen;

  ConceptProgress({required this.category, this.seen = false});

  Map<String, dynamic> toJson() => {'category': category, 'seen': seen};

  factory ConceptProgress.fromJson(Map<String, dynamic> json) =>
      ConceptProgress(category: json['category'], seen: json['seen']);
}

/// Captures a mastered question's difficulty tier at the moment it
/// was earned, so scoring/credit logic doesn't need to reload CSV
/// data just to know whether a mastered question was Hard.
class QuestionMasteryRecord {
  final int difficulty; // 1=easy, 2=medium, 3=hard
  const QuestionMasteryRecord({required this.difficulty});

  Map<String, dynamic> toJson() => {'difficulty': difficulty};

  factory QuestionMasteryRecord.fromJson(Map<String, dynamic> json) =>
      QuestionMasteryRecord(difficulty: json['difficulty'] ?? 1);
}

class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // User
  String userName = '';
  bool hasSeenIntro = false;

  // ── Purchases ─────────────────────────────────────────────
  bool hasUnlockedApp = false;
  PurchaseType purchaseType = PurchaseType.none;
  DateTime? purchaseDate;

  bool get hasFullAccess => hasUnlockedApp;
  bool get hasUpgraded => hasUnlockedApp;
  bool get isLifetime => purchaseType == PurchaseType.lifetime;
  bool get isTimeLimited =>
      purchaseType == PurchaseType.sevenDay ||
      purchaseType == PurchaseType.fourteenDay;
  bool get canUpgradeToLifetime => isTimeLimited && hasUnlockedApp;

  DateTime? get expiryDate {
    if (!isTimeLimited || purchaseDate == null) return null;
    final days = purchaseType == PurchaseType.sevenDay ? 7 : 14;
    return purchaseDate!.add(Duration(days: days));
  }

  bool get isExpired {
    final expiry = expiryDate;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }

  int? get daysRemaining {
    final expiry = expiryDate;
    if (expiry == null) return null;
    final remaining = expiry.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }
  // ──────────────────────────────────────────────────────────

  // ── Trial tracking ──────────────────────────────────────────
  // True once the 'trial_started' Mixpanel event has fired for this
  // install. Prevents re-firing on every HomePage remount (navigation,
  // pushAndRemoveUntil, etc). Persists across reset() the same way the
  // purchase fields do. Same fix as SafePrep Manager — see App Manual
  // §16.2.
  bool trialStarted = false;
  // ──────────────────────────────────────────────────────────

  // ── Renewal explainer ─────────────────────────────────────────
  // True once the user has seen the one-time explainer describing how
  // the renewal purchase works. Ported from Manager — see
  // RenewPage/HomePage renewal button.
  bool hasSeenRenewalExplainer = false;
  // ──────────────────────────────────────────────────────────

  // ── Study landing modal ─────────────────────────────────────
  // One-time, GLOBAL (not per-category) flag — fires once on the
  // user's first-ever entry into the study module, then every
  // subsequent entry skips straight to CategoryStudyPage/
  // CategoryQuizPage. See navigateToStudy() in study_landing_page.dart.
  bool hasSeenStudyLanding = false;
  // ──────────────────────────────────────────────────────────

  // ── Final Exam review prompt (FSME) ──────────────────────────
  // One-time, ever — fires once on a Final Exam pass at 85%+ (see
  // FinalExamGradePage / ReviewPromptDialog). Preserved across
  // reset() same as hasSeenRenewalExplainer/hasSeenStudyLanding, so
  // a data reset doesn't let the ask fire a second time.
  bool hasSeenReviewPrompt = false;
  // ──────────────────────────────────────────────────────────

  // ── Fail-streak safety net (Retro→Proper→Full Study) ─────────────
  // Per-category, resets on any pass (>=75%) or when the counter is
  // consumed by a triggered switch — does NOT carry across different
  // categories.
  Map<String, int> categoryQuizFailStreak = {};

  // Per-category override that beats the onboarding-derived global
  // default once the safety net fires. Values: 'proper' or
  // 'fullStudy'. Absent key = no override.
  Map<String, String> categoryModeOverride = {};
  // ──────────────────────────────────────────────────────────

  // ── Study/Quiz toggle-session cache ─────────────────────────
  // CategoryStudyPage and CategoryQuizPage each pushReplacement to a
  // brand-new instance of the other when the user taps "Full Study
  // Mode" / "Quiz Mode" — neither page carries its in-progress state
  // to the new instance on its own. Without this cache,
  // CategoryQuizPage's initState re-rolls an entirely new random
  // 15-question draw every single time it's rebuilt, so bouncing
  // between modes silently swaps out the quiz (and can repeat
  // questions the user just answered). This cache lets both pages
  // resume the same in-progress session instead of starting over.
  //
  // Quiz side: the actual drawn+shuffled question list, current
  // index, and running correct count, keyed by category. Cleared by
  // clearQuizSession() once a quiz is genuinely completed (see
  // CategoryQuizPage._showResults), so the NEXT fresh entry into that
  // category still draws normally.
  Map<String, List<QuestionModel>> quizSessionQuestions = {};
  Map<String, int> quizSessionIndex = {};
  Map<String, int> quizSessionCorrectCount = {};

  void clearQuizSession(String category) {
    quizSessionQuestions.remove(category);
    quizSessionIndex.remove(category);
    quizSessionCorrectCount.remove(category);
  }

  // Study side: curriculum content order is deterministic (not
  // randomized like the quiz draw), so only the card position needs
  // remembering, not the content itself.
  Map<String, int> studySessionIndex = {};
  // ──────────────────────────────────────────────────────────

  // ── Question-level mastery ──────────────────────────────────
  // Distinct from the toggle-session cache above — this IS durable
  // progress (persisted), not a live in-session artifact.
  //
  // category -> questionId -> consecutive-correct streak. Resets to
  // 0 (entry removed) on any miss; a question is mastered the moment
  // it hits 3 consecutive correct answers.
  Map<String, Map<String, int>> questionStreaks = {};

  // category -> questionId -> mastery record. Presence in this map
  // means the question is retired from that category's live quiz
  // draw pool. Difficulty is captured at the moment mastery was
  // earned so scoring never needs to re-touch the CSV.
  Map<String, Map<String, QuestionMasteryRecord>> masteredQuestions = {};

  /// Call after every answered question in a category quiz (never
  /// the Final Exam — question-level mastery is category-quiz-only
  /// by design). Advances or resets the per-question streak; on
  /// hitting 3 consecutive correct, retires the question from the
  /// live pool via masteredQuestions.
  void recordQuestionAnswer({
    required String category,
    required String questionId,
    required int difficulty,
    required bool correct,
  }) {
    if (isQuestionMastered(category, questionId)) return;

    final streaks = questionStreaks.putIfAbsent(category, () => {});
    if (!correct) {
      streaks.remove(questionId);
      return;
    }
    final next = (streaks[questionId] ?? 0) + 1;
    if (next >= 3) {
      streaks.remove(questionId);
      masteredQuestions.putIfAbsent(category, () => {})[questionId] =
          QuestionMasteryRecord(difficulty: difficulty);
    } else {
      streaks[questionId] = next;
    }
  }

  bool isQuestionMastered(String category, String questionId) =>
      masteredQuestions[category]?.containsKey(questionId) ?? false;

  int hardMasteredCount(String category) =>
      masteredQuestions[category]?.values
          .where((r) => r.difficulty == 3)
          .length ??
      0;

  int masteredQuestionCount(String category) =>
      masteredQuestions[category]?.length ?? 0;

  /// Wipes all question-level mastery/streak data for ONE category —
  /// its full question pool goes live again. Called automatically
  /// from two places: (1) the moment a category newly crosses into
  /// category-level Mastered (see CategoryQuizResultsPage), and (2)
  /// whenever the user re-enters Study/Quiz for a category that's
  /// ALREADY mastered (see navigateToStudy() in study_landing_page
  /// .dart) — re-selecting an already-mastered category is a
  /// deliberate "start over" signal by design; nothing persists.
  void clearQuestionMasteryForCategory(String category) {
    questionStreaks.remove(category);
    masteredQuestions.remove(category);
  }

  /// Full wipe, every category — called only from the Final Exam's
  /// fail-reset path (see FinalStepExamPage._submitExam()), since a
  /// failed Final Exam invalidates question-level mastery signal
  /// everywhere, not just in categories that scored low on that exam.
  void clearAllQuestionMastery() {
    questionStreaks.clear();
    masteredQuestions.clear();
  }
  // ──────────────────────────────────────────────────────────

  // ── Readiness Index ───────────────────────────────────────
  int readinessScore = 0;
  String readinessCoachMessage =
      'Take the diagnostic assessment to start building your readiness score.';
  String readinessCheerMessage =
      'SafePrep was built for one purpose — to get you ready. Let\'s get started.';
  double extraCreditPoints = 0.0;
  int? finalExamScore;
  // ──────────────────────────────────────────────────────────

  // Test History
  List<TestResult> testHistory = [];

  // Category Scores
  Map<String, int> categoryQuizScores = {};
  Map<String, int> categoryBaselineScores = {};
  Map<String, int> categoryQuizAttempts = {};

  // Milestones & Trophies
  List<String> earnedMilestones = [];
  Set<String> earnedTrophyIds = {};
  int perfectCategoryCount = 0;

  // Missed questions
  List<String> missedFinalExamQuestionIds = [];

  // Study Progress
  List<String> studiedCategories = [];
  Map<String, int> curriculumProgress = {};
  int studyStreak = 0;
  DateTime? lastLaunchDate;

  // Concept Progress
  Map<int, ConceptProgress> conceptProgressRecords = {};

  // Subcategory Gaps
  Map<String, List<SubcategoryGap>> subcategoryGaps = {};

  // Constants
  static const int masteryThreshold = 85;
  static const int minAnswersForRawScores = 30;

  // ── Category list — pulled directly from FinalTestQuestions5.csv's
  // real Category column for SafePrep Alcohol. ──────────────────────
  static const List<String> allCategories = [
    'Legal Liability',
    'BAC & Physiology',
    'Intervention & Refusal',
    'Signs of Intoxication',
    'Responsible Service',
    'ID Verification',
  ];

  // TODO: these are PLACEHOLDER industry-baseline scores, not real
  // alcohol-service exam data. Manager's equivalent map was informed by
  // real ServSafe food-safety pass-rate data — no equivalent source was
  // available for alcohol service, so these are estimated starting
  // points only. Replace with real figures if/when available.
  static const Map<String, int> servSafeIndustryBaseline = {
    'Legal Liability': 58,
    'BAC & Physiology': 54,
    'Intervention & Refusal': 61,
    'Signs of Intoxication': 65,
    'Responsible Service': 63,
    'ID Verification': 70,
  };

  // Exam weights — proportional to each category's real share of the
  // 175-question bank in FinalTestQuestions5.csv (35/33/29/27/26/25).
  static const Map<String, double> categoryExamWeights = {
    'Legal Liability': 0.20,
    'BAC & Physiology': 0.19,
    'Intervention & Refusal': 0.17,
    'Signs of Intoxication': 0.15,
    'Responsible Service': 0.15,
    'ID Verification': 0.14,
  };

  // Diagnostic question allocation — totals 30, matching Manager's
  // 30-question diagnostic pattern, distributed proportionally to the
  // exam weights above.
  static const Map<String, int> categoryMaxQuestions = {
    'Legal Liability': 6,
    'BAC & Physiology': 6,
    'Intervention & Refusal': 5,
    'Signs of Intoxication': 5,
    'Responsible Service': 4,
    'ID Verification': 4,
  };

  // Convenience getters
  bool get isNewUser => userName.isEmpty;
  bool get hasTakenAssessment =>
      testHistory.isNotEmpty || categoryQuizScores.isNotEmpty;

  TestResult? get latestResult {
    if (testHistory.isEmpty) return null;
    return testHistory.reduce(
      (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
    );
  }

  TestResult? get baselineResult {
    if (testHistory.isEmpty) return null;
    return testHistory.reduce(
      (a, b) => a.timestamp.isBefore(b.timestamp) ? a : b,
    );
  }

  List<String> get masteredCategories => allCategories
      .where(
        (c) =>
            hasScoreForCategory(c) && getCategoryScore(c) >= masteryThreshold,
      )
      .toList();

  List<String> get studyCategories =>
      allCategories.where((c) => !masteredCategories.contains(c)).toList()
        ..sort((a, b) => getCategoryScore(a).compareTo(getCategoryScore(b)));

  // Methods
  void addEarnedMilestone(String triggerId, String milestoneMessage) {
    earnedTrophyIds.add(triggerId);
    earnedMilestones.insert(0, milestoneMessage);
    if (earnedMilestones.length > 5) earnedMilestones.removeAt(5);
  }

  void incrementCategoryQuizAttempts(String category) {
    categoryQuizAttempts[category] = (categoryQuizAttempts[category] ?? 0) + 1;
  }

  int getCategoryQuizAttempts(String category) =>
      categoryQuizAttempts[category] ?? 0;

  void saveCategoryQuizScore(String category, int percent) {
    categoryQuizScores[category] = percent;
    categoryBaselineScores.putIfAbsent(category, () => percent);
    // Mastering a category straight from an assessment (skipping the
    // study cards entirely) used to leave it out of studiedCategories
    // until the next app launch reconciled it via reconcileMasteredStudied()
    // in fromJson — so the Curriculum trophy count didn't include it
    // until a restart. Reconcile immediately instead, so mastering a
    // category always counts it toward Curriculum right away too.
    if (percent >= masteryThreshold) {
      markCategoryStudied(category);
    }
  }

  int getCategoryScore(String category) {
    if (categoryQuizScores.containsKey(category)) {
      return categoryQuizScores[category]!;
    }
    final latest = latestResult;
    if (latest != null && latest.categoryScores.containsKey(category)) {
      return latest.categoryScores[category]!;
    }
    return 0;
  }

  bool hasScoreForCategory(String category) =>
      categoryQuizScores.containsKey(category) ||
      (latestResult?.categoryScores.containsKey(category) ?? false);

  int getOverallScore() {
    if (latestResult != null) return latestResult!.overallScore;
    if (categoryQuizScores.isNotEmpty) {
      return categoryQuizScores.values.reduce((a, b) => a + b) ~/
          categoryQuizScores.length;
    }
    return 0;
  }

  int getBaselineScore(String category) {
    final baseline = baselineResult;
    if (baseline != null && baseline.categoryScores.containsKey(category)) {
      return baseline.categoryScores[category]!;
    }
    if (categoryBaselineScores.containsKey(category)) {
      return categoryBaselineScores[category]!;
    }
    return servSafeIndustryBaseline[category] ?? 60;
  }

  int getBlendedScore(String category, {required int totalAnswered}) {
    final baseline = servSafeIndustryBaseline[category] ?? 60;
    if (totalAnswered == 0) return baseline;
    if (!hasScoreForCategory(category)) return baseline;
    final rawScore = getCategoryScore(category);
    if (rawScore == 0 && !categoryQuizScores.containsKey(category)) {
      return baseline;
    }
    if (totalAnswered >= minAnswersForRawScores) return rawScore;
    final totalAssessmentQ = categoryMaxQuestions.values.fold(
      0,
      (sum, v) => sum + v,
    );
    final answeredFraction = (totalAnswered / totalAssessmentQ).clamp(0.0, 1.0);
    final examWeight = categoryExamWeights[category] ?? 0.10;
    final maxBoost = examWeight * (rawScore - baseline);
    return (baseline + (maxBoost * answeredFraction)).round();
  }

  int getBlendedOverallScore({required int totalAnswered}) {
    final scores = allCategories
        .map((c) => getBlendedScore(c, totalAnswered: totalAnswered))
        .toList();
    return scores.reduce((a, b) => a + b) ~/ scores.length;
  }

  bool hasStudiedCategory(String category) =>
      studiedCategories.any((c) => c.toLowerCase() == category.toLowerCase());

  int getCurriculumProgress(String category) =>
      curriculumProgress[category] ?? 0;

  bool isMastered(String category) => masteredCategories.contains(category);

  void markCategoryStudied(String category) {
    if (!hasStudiedCategory(category)) studiedCategories.add(category);
  }

  void reconcileMasteredStudied() {
    for (final category in masteredCategories) {
      markCategoryStudied(category);
    }
  }

  void markConceptReviewed(String category) {
    curriculumProgress[category] = (curriculumProgress[category] ?? 0) + 1;
  }

  void clearCurriculumProgress() {
    // Only clear studied/curriculum tracking for categories that DON'T
    // have a real quiz score. If a category was studied AND scored during
    // trial, that's genuine, earned progress — it survives purchase intact,
    // including its CURRICULUM trophy. Only incomplete/browsing-only state
    // gets reset, so purchasing never erases work the user actually did.
    studiedCategories.removeWhere((c) => !hasScoreForCategory(c));
    curriculumProgress.removeWhere((c, _) => !hasScoreForCategory(c));
  }

  int getOverallCurriculumPercent() {
    final total = allCategories.length;
    if (total == 0) return 0;
    final mastered = masteredCategories;
    final studiedOnly = studiedCategories
        .where((c) => !mastered.contains(c))
        .length;
    final weighted = (mastered.length * 100) + (studiedOnly * 50);
    return weighted ~/ total;
  }

  bool isCurriculumCompleteForCategory(String category) {
    return hasStudiedCategory(category) && hasScoreForCategory(category);
  }

  List<String> get curriculumCompletedCategories =>
      allCategories.where((c) => isCurriculumCompleteForCategory(c)).toList();

  void updateStreak() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (lastLaunchDate == null) {
      studyStreak = 1;
      lastLaunchDate = todayDate;
      return;
    }
    final last = DateTime(
      lastLaunchDate!.year,
      lastLaunchDate!.month,
      lastLaunchDate!.day,
    );
    if (last == todayDate) {
      return;
    } else if (last == todayDate.subtract(const Duration(days: 1))) {
      studyStreak++;
      lastLaunchDate = todayDate;
    } else {
      studyStreak = 1;
      lastLaunchDate = todayDate;
    }
  }

  void reset() {
    final savedHasUnlocked = hasUnlockedApp;
    final savedPurchaseType = purchaseType;
    final savedPurchaseDate = purchaseDate;
    final savedTrialStarted = trialStarted;
    final savedHasSeenRenewalExplainer = hasSeenRenewalExplainer;
    final savedHasSeenStudyLanding = hasSeenStudyLanding;
    final savedHasSeenReviewPrompt = hasSeenReviewPrompt;

    userName = '';
    hasSeenIntro = false;
    hasUnlockedApp = false;
    purchaseType = PurchaseType.none;
    purchaseDate = null;
    trialStarted = false;
    readinessScore = 0;
    readinessCoachMessage =
        'Take the diagnostic assessment to start building your readiness score.';
    readinessCheerMessage =
        'SafePrep was built for one purpose — to get you ready. Let\'s get started.';
    extraCreditPoints = 0.0;
    finalExamScore = null;
    testHistory.clear();
    subcategoryGaps.clear();
    studiedCategories.clear();
    curriculumProgress.clear();
    categoryQuizScores.clear();
    categoryBaselineScores.clear();
    categoryQuizAttempts.clear();
    missedFinalExamQuestionIds.clear();
    earnedMilestones.clear();
    earnedTrophyIds.clear();
    perfectCategoryCount = 0;
    conceptProgressRecords.clear();
    studyStreak = 0;
    lastLaunchDate = null;
    categoryQuizFailStreak.clear();
    categoryModeOverride.clear();
    quizSessionQuestions.clear();
    quizSessionIndex.clear();
    quizSessionCorrectCount.clear();
    studySessionIndex.clear();
    questionStreaks.clear();
    masteredQuestions.clear();

    hasUnlockedApp = savedHasUnlocked;
    purchaseType = savedPurchaseType;
    purchaseDate = savedPurchaseDate;
    trialStarted = savedTrialStarted;
    hasSeenRenewalExplainer = savedHasSeenRenewalExplainer;
    hasSeenStudyLanding = savedHasSeenStudyLanding;
    hasSeenReviewPrompt = savedHasSeenReviewPrompt;
  }

  Map<String, dynamic> toJson() => {
    'stateVersion': 2,
    'userName': userName,
    'hasSeenIntro': hasSeenIntro,
    'hasUnlockedApp': hasUnlockedApp,
    'purchaseType': purchaseType.name,
    'purchaseDate': purchaseDate?.toIso8601String(),
    'trialStarted': trialStarted,
    'hasSeenRenewalExplainer': hasSeenRenewalExplainer,
    'hasSeenStudyLanding': hasSeenStudyLanding,
    'hasSeenReviewPrompt': hasSeenReviewPrompt,
    'categoryQuizFailStreak': categoryQuizFailStreak,
    'categoryModeOverride': categoryModeOverride,
    'readinessScore': readinessScore,
    'readinessCoachMessage': readinessCoachMessage,
    'readinessCheerMessage': readinessCheerMessage,
    'extraCreditPoints': extraCreditPoints,
    'finalExamScore': finalExamScore,
    'testHistory': testHistory.map((t) => t.toJson()).toList(),
    'categoryQuizScores': categoryQuizScores,
    'categoryBaselineScores': categoryBaselineScores,
    'categoryQuizAttempts': categoryQuizAttempts,
    'earnedMilestones': earnedMilestones,
    'earnedTrophyIds': earnedTrophyIds.toList(),
    'perfectCategoryCount': perfectCategoryCount,
    'missedFinalExamQuestionIds': missedFinalExamQuestionIds,
    'studiedCategories': studiedCategories,
    'curriculumProgress': curriculumProgress,
    'studyStreak': studyStreak,
    'lastLaunchDate': lastLaunchDate?.toIso8601String(),
    'conceptProgressRecords': conceptProgressRecords.map(
      (k, v) => MapEntry(k.toString(), v.toJson()),
    ),
    'questionStreaks': questionStreaks,
    'masteredQuestions': masteredQuestions.map(
      (cat, qmap) =>
          MapEntry(cat, qmap.map((qid, rec) => MapEntry(qid, rec.toJson()))),
    ),
    // quizSessionQuestions / quizSessionIndex / quizSessionCorrectCount /
    // studySessionIndex are intentionally NOT persisted — they're a
    // live in-memory toggle cache for the current app session only,
    // not durable progress. A fresh app launch should always draw a
    // clean quiz. questionStreaks/masteredQuestions ARE persisted —
    // this is real long-term mastery progress, not a toggle artifact.
  };

  void fromJson(Map<String, dynamic> json) {
    final version = json['stateVersion'] ?? 1;
    if (version < 2) {
      studiedCategories.clear();
    }

    userName = json['userName'] ?? '';
    hasSeenIntro = json['hasSeenIntro'] ?? false;
    hasUnlockedApp = json['hasUnlockedApp'] ?? false;
    purchaseType = PurchaseType.values.firstWhere(
      (e) => e.name == (json['purchaseType'] ?? 'none'),
      orElse: () => PurchaseType.none,
    );
    if (hasUnlockedApp && purchaseType == PurchaseType.none) {
      purchaseType = PurchaseType.lifetime;
    }
    purchaseDate = json['purchaseDate'] != null
        ? DateTime.parse(json['purchaseDate'])
        : null;
    trialStarted = json['trialStarted'] ?? false;
    hasSeenRenewalExplainer = json['hasSeenRenewalExplainer'] ?? false;
    hasSeenStudyLanding = json['hasSeenStudyLanding'] ?? false;
    hasSeenReviewPrompt = json['hasSeenReviewPrompt'] ?? false;
    categoryQuizFailStreak = Map<String, int>.from(
      json['categoryQuizFailStreak'] ?? {},
    );
    categoryModeOverride = Map<String, String>.from(
      json['categoryModeOverride'] ?? {},
    );
    readinessScore = json['readinessScore'] ?? 0;
    readinessCoachMessage =
        json['readinessCoachMessage'] ??
        'Take the diagnostic assessment to start building your readiness score.';
    readinessCheerMessage =
        json['readinessCheerMessage'] ??
        'SafePrep was built for one purpose — to get you ready. Let\'s get started.';
    extraCreditPoints = (json['extraCreditPoints'] ?? 0.0).toDouble();
    finalExamScore = json['finalExamScore'];
    testHistory = (json['testHistory'] as List? ?? [])
        .map((t) => TestResult.fromJson(t))
        .toList();
    categoryQuizScores = Map<String, int>.from(
      json['categoryQuizScores'] ?? {},
    );
    categoryBaselineScores = Map<String, int>.from(
      json['categoryBaselineScores'] ?? {},
    );
    categoryQuizAttempts = Map<String, int>.from(
      json['categoryQuizAttempts'] ?? {},
    );
    earnedMilestones = List<String>.from(json['earnedMilestones'] ?? []);
    earnedTrophyIds = Set<String>.from(json['earnedTrophyIds'] ?? []);
    perfectCategoryCount = json['perfectCategoryCount'] ?? 0;
    missedFinalExamQuestionIds = List<String>.from(
      json['missedFinalExamQuestionIds'] ?? [],
    );
    studiedCategories = version >= 2
        ? List<String>.from(json['studiedCategories'] ?? [])
        : studiedCategories;
    curriculumProgress = Map<String, int>.from(
      json['curriculumProgress'] ?? {},
    );
    studyStreak = json['studyStreak'] ?? 0;
    lastLaunchDate = json['lastLaunchDate'] != null
        ? DateTime.parse(json['lastLaunchDate'])
        : null;
    conceptProgressRecords = (json['conceptProgressRecords'] as Map? ?? {}).map(
      (k, v) => MapEntry(int.parse(k), ConceptProgress.fromJson(v)),
    );

    questionStreaks = (json['questionStreaks'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, Map<String, int>.from(v as Map)),
    );
    masteredQuestions = (json['masteredQuestions'] as Map? ?? {}).map(
      (cat, qmap) => MapEntry(
        cat as String,
        (qmap as Map).map(
          (qid, rec) => MapEntry(
            qid as String,
            QuestionMasteryRecord.fromJson(Map<String, dynamic>.from(rec)),
          ),
        ),
      ),
    );

    reconcileMasteredStudied();
  }
}
