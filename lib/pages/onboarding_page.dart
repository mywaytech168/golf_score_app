import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// 初次使用教學引導：全螢幕 PageView 介紹核心流程
/// （錄影 → 自動切片 → AI 分析 → 球數/獎勵）。
///
/// 首次進入主畫面時由 [maybeShow] 觸發，之後可從設定頁「重看教學引導」開啟。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  static const _seenKey = 'onboarding_seen_v1';

  /// 若使用者尚未看過教學引導，推入全螢幕導覽頁並於關閉時寫入旗標。
  static Future<void> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) ?? false) return;
    if (!context.mounted) return;
    await show(context);
  }

  /// 直接顯示教學引導（設定頁「重看教學引導」也走這裡），關閉時標記已看過。
  static Future<void> show(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const OnboardingPage(),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<_OnboardingStep> _steps(AppLocalizations l) => [
        _OnboardingStep(
          icon: Icons.videocam_rounded,
          title: l.onboardingRecordTitle,
          description: l.onboardingRecordDesc,
        ),
        _OnboardingStep(
          icon: Icons.content_cut_rounded,
          title: l.onboardingClipTitle,
          description: l.onboardingClipDesc,
        ),
        _OnboardingStep(
          icon: Icons.psychology_rounded,
          title: l.onboardingAiTitle,
          description: l.onboardingAiDesc,
        ),
        _OnboardingStep(
          icon: Icons.sports_golf_rounded,
          title: l.onboardingBallsTitle,
          description: l.onboardingBallsDesc,
        ),
      ];

  void _next(int stepCount) {
    if (_currentPage >= stepCount - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final steps = _steps(l);
    final isLast = _currentPage == steps.length - 1;

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // 跳過按鈕（最後一頁隱藏）
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: kSpaceSM, vertical: kSpaceXS),
                child: AnimatedOpacity(
                  opacity: isLast ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    onPressed:
                        isLast ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      l.onboardingSkip,
                      style: TextStyle(color: context.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: steps.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) =>
                    _OnboardingStepView(step: steps[index]),
              ),
            ),
            // 圓點指示器
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(steps.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: kSpaceXS),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? kBrandPrimary : context.borderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            // 下一步 / 開始使用
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kSpaceLG, kSpaceLG, kSpaceLG, kSpaceXL),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _next(steps.length),
                  child: Text(isLast ? l.onboardingStart : l.onboardingNext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStep {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _OnboardingStepView extends StatelessWidget {
  final _OnboardingStep step;

  const _OnboardingStepView({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceXL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: context.mintTint,
              borderRadius: BorderRadius.circular(kRadiusXL),
            ),
            child: Icon(step.icon, size: 72, color: kBrandPrimary),
          ),
          const SizedBox(height: kSpaceXL),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: kSpaceMD),
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
