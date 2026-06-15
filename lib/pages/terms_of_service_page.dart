import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:golf_score_app/l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_text.dart';
import 'login_page.dart';

const _kPrivacyPolicyUrl = 'https://orvia.atk.tw/privacy.html';
const _kTermsUrl = 'https://orvia.atk.tw/terms.html';

/// 隱私政策網址（供其他頁面使用，例如設定頁）
const String kPrivacyPolicyUrl = _kPrivacyPolicyUrl;

/// 使用條款網址（供其他頁面使用，例如設定頁）
const String kTermsUrl = _kTermsUrl;

/// 客服聯絡信箱（供其他頁面使用，例如設定頁）
const String kSupportEmail = 'support@atk.tw';

/// 以系統郵件 App 開啟聯絡客服（mailto）；失敗回傳 false
Future<bool> openContactSupport() async {
  final uri = Uri(scheme: 'mailto', path: kSupportEmail);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 以外部瀏覽器開啟隱私政策；失敗回傳 false
Future<bool> openPrivacyPolicy() async {
  final uri = Uri.parse(_kPrivacyPolicyUrl);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 以外部瀏覽器開啟使用條款；失敗回傳 false
Future<bool> openTermsOfService() async {
  final uri = Uri.parse(_kTermsUrl);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 首次啟動顯示使用者條款，同意後才進入登入流程
class TermsOfServicePage extends StatefulWidget {
  const TermsOfServicePage({super.key});

  /// 檢查是否已同意條款
  static Future<bool> isAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('terms_accepted') ?? false;
  }

  /// 記錄同意條款，並儲存使用統計追蹤偏好
  static Future<void> markAccepted({required bool analyticsConsent}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terms_accepted', true);
    await prefs.setBool('analytics_consent', analyticsConsent);
  }

  /// 設定頁可隨時變更使用統計追蹤偏好
  static Future<void> setAnalyticsConsent(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('analytics_consent', granted);
  }

  /// 取得使用者是否同意使用統計追蹤
  static Future<bool> analyticsConsentGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('analytics_consent') ?? false;
  }

  @override
  State<TermsOfServicePage> createState() => _TermsOfServicePageState();
}

class _TermsOfServicePageState extends State<TermsOfServicePage> {
  final _scrollController = ScrollController();
  bool _hasScrolledToBottom = false;
  bool _agreed = false;
  bool _analyticsConsent = true; // 預設同意（可自由取消勾選）

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('terms');
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasScrolledToBottom) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 40) {
      setState(() => _hasScrolledToBottom = true);
    }
  }

  Future<void> _accept() async {
    await TermsOfServicePage.markAccepted(analyticsConsent: _analyticsConsent);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _decline() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.termsDeclineTitle),
        content: Text(l10n.termsDeclineContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.termsDeclineBack),
          ),
          FilledButton(
            onPressed: () => exit(0),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(l10n.termsDeclineExit),
          ),
        ],
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(_kPrivacyPolicyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).termsPrivacyOpenFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            // 兩模式統一深靛→墨黑，讓品牌漸層 wordmark(Cyan→Blue→Purple)有足夠對比
            colors: [Color(0xFF13122E), kOrviaInk],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset('assets/branding/orvia_pwa_icon.png', fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GradientText('ORVIA',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold)),
                        Text(l10n.termsPageSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),

              // ── 條款內文 ─────────────────────────────────────
              // 本頁背景固定深靛→墨黑（兩模式皆深色），故卡片強制套深色主題，
              // 避免淺色主題下白底卡片與深色頁面對比過高刺眼。
              Expanded(
                child: Theme(
                  data: theme.copyWith(brightness: Brightness.dark),
                  child: Builder(builder: (context) {
                    return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      // 提示列
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.mintTint,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: kBrandPrimary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.termsReadPrompt,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: kBrandPrimary),
                              ),
                            ),
                            if (!_hasScrolledToBottom)
                              const Icon(Icons.keyboard_arrow_down,
                                  size: 18, color: kBrandPrimary),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // 條款文字
                      Expanded(
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(20),
                            child: _buildTermsContent(context, theme, l10n),
                          ),
                        ),
                      ),
                    ],
                  ),
                    );
                  }),
                ),
              ),

              // ── 底部操作區 ───────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 同意條款勾選（含隱私政策可點擊連結）──────
                    GestureDetector(
                      onTap: _hasScrolledToBottom
                          ? () => setState(() => _agreed = !_agreed)
                          : null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: _agreed,
                            onChanged: _hasScrolledToBottom
                                ? (v) => setState(() => _agreed = v ?? false)
                                : null,
                            activeColor: kBrandPrimary,
                            checkColor: Colors.white,
                            side: BorderSide(
                              color: _hasScrolledToBottom
                                  ? Colors.white
                                  : Colors.white38,
                              width: 1.5,
                            ),
                          ),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  color: _hasScrolledToBottom
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 13,
                                ),
                                children: [
                                  TextSpan(text: l10n.termsAgreePrefix),
                                  TextSpan(
                                    text: l10n.termsPrivacyLink,
                                    style: TextStyle(
                                      color: _hasScrolledToBottom
                                          ? Colors.lightGreenAccent
                                          : Colors.white38,
                                      decoration: TextDecoration.underline,
                                      decorationColor: _hasScrolledToBottom
                                          ? Colors.lightGreenAccent
                                          : Colors.white38,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = _openPrivacyPolicy,
                                  ),
                                  TextSpan(text: l10n.termsAgreeSuffix),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── 使用統計追蹤同意 ──────────────────────────
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _analyticsConsent,
                          onChanged: (v) =>
                              setState(() => _analyticsConsent = v ?? true),
                          activeColor: kBrandPrimary,
                          checkColor: Colors.white,
                          side: const BorderSide(color: Colors.white70, width: 1.5),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.termsAnalyticsTitle,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              Text(
                                l10n.termsAnalyticsDesc,
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (!_hasScrolledToBottom)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          l10n.termsScrollFirst,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                        ),
                      ),
                    const SizedBox(height: 10),

                    // ── 按鈕列 ────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _decline,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Colors.white54),
                              foregroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(l10n.termsDisagree),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: (_agreed && _hasScrolledToBottom) ? _accept : null,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F5C46),
                              disabledBackgroundColor: Colors.white24,
                              disabledForegroundColor: Colors.white38,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(l10n.termsAgreeAndContinue,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermsContent(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._termsSections(context),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.mintTint,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kGoodColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 18, color: kGoodColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.termsScrolledToBottom,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kGoodColor)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 條款各段落（同意頁與設定頁唯讀檢視共用）
  static List<Widget> _termsSections(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
        _section(context, l10n.termsSec1Title, l10n.termsSec1Body),
        _section(context, l10n.termsSec2Title, l10n.termsSec2Body),
        _section(context, l10n.termsSec3Title, l10n.termsSec3Body),
        _section(context, l10n.termsSec4Title, l10n.termsSec4Body),
        _section(context, l10n.termsSec5Title, l10n.termsSec5Body),
        _section(context, l10n.termsSec6Title, l10n.termsSec6Body),
        _section(context, l10n.termsSec7Title, l10n.termsSec7Body),
        _section(context, l10n.termsSec8Title, l10n.termsSec8Body),
        _section(context, l10n.termsSec9Title, l10n.termsSec9Body),
    ];
  }

  static Widget _section(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: context.isDarkMode ? kPrimaryLight : kBrandPrimaryDark,
              )),
          const SizedBox(height: 8),
          Text(body,
              style: TextStyle(
                fontSize: 13,
                color: context.textPrimary,
                height: 1.65,
              )),
        ],
      ),
    );
  }
}

/// 唯讀檢視使用者條款與隱私政策（從設定頁開啟，無同意流程）
class TermsViewPage extends StatelessWidget {
  const TermsViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        backgroundColor: context.isDarkMode ? context.bgPage : kBrandPrimary,
        foregroundColor: context.isDarkMode ? context.textPrimary : Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(AppLocalizations.of(context).termsPageSubtitle,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._TermsOfServicePageState._termsSections(context),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(AppLocalizations.of(context).termsOpenPrivacyFull),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kBrandPrimary,
                  side: const BorderSide(color: kBrandPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final ok = await openPrivacyPolicy();
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(
                          AppLocalizations.of(context).settingsPrivacyOpenFailed)),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
