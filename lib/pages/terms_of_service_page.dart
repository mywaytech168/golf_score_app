import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:golf_score_app/l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'login_page.dart';

const _kPrivacyPolicyUrl = 'https://orvia.atk.tw/privacy.html';
const _kTermsUrl = 'https://orvia.atk.tw/terms.html';

/// 隱私政策網址（供其他頁面使用，例如設定頁）
const String kPrivacyPolicyUrl = _kPrivacyPolicyUrl;

/// 使用條款網址（供其他頁面使用，例如設定頁）
const String kTermsUrl = _kTermsUrl;

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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認離開'),
        content: const Text('不同意使用者條款將無法使用 ORVIA。確定要離開嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => exit(0),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('離開'),
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
        const SnackBar(content: Text('無法開啟隱私政策頁面，請稍後再試')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            // 深色模式用深綠→墨黑，避免黑卡片浮在亮綠背景上
            colors: context.isDarkMode
                ? const [Color(0xFF0E2B22), kOrviaInk]
                : const [Color(0xFF1AA87C), Color(0xFF0F5C46)],
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
                    Image.asset('assets/branding/logo_icon.png', width: 36, height: 36),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ORVIA',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('使用者條款與隱私政策',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),

              // ── 條款內文 ─────────────────────────────────────
              Expanded(
                child: Container(
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
                            const Icon(Icons.info_outline, size: 16, color: Color(0xFF1AA87C)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '請閱讀以下條款後，勾選同意即可開始使用',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF1AA87C)),
                              ),
                            ),
                            if (!_hasScrolledToBottom)
                              const Icon(Icons.keyboard_arrow_down,
                                  size: 18, color: Color(0xFF1AA87C)),
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
                            child: _buildTermsContent(theme),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                            activeColor: const Color(0xFF1AA87C),
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
                                  const TextSpan(text: '我已閱讀並同意《使用者條款》與《'),
                                  TextSpan(
                                    text: '隱私政策',
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
                                  const TextSpan(text: '》'),
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
                          activeColor: const Color(0xFF1AA87C),
                          checkColor: Colors.white,
                          side: const BorderSide(color: Colors.white70, width: 1.5),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                '允許使用統計追蹤（選用）',
                                style: TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              Text(
                                '協助我們改善 App 體驗，不包含個人身份資訊',
                                style: TextStyle(color: Colors.white60, fontSize: 11),
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
                          '請先滑動閱讀完整條款後方可勾選同意',
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
                            child: const Text('不同意'),
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
                            child: const Text('同意並繼續',
                                style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildTermsContent(ThemeData theme) {
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
            border: Border.all(color: const Color(0xFF1AA87C).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 18, color: Color(0xFF1AA87C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('已閱讀至條款末端，請返回頂部勾選同意。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF1AA87C))),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 條款各段落（同意頁與設定頁唯讀檢視共用）
  static List<Widget> _termsSections(BuildContext context) {
    return [
        _section(context, '一、服務說明', '''
ORVIA（以下簡稱「本服務」）由 ORVIA 團隊提供，旨在協助使用者透過行動裝置錄製、分析高爾夫揮桿動作，並提供相關數據統計與建議。

使用本服務前，請仔細閱讀以下條款。一旦您開始使用本服務，即表示您已閱讀、理解並同意本條款之所有內容。'''),
        _section(context, '二、帳號與安全', '''
1. 您須透過電子郵件或 Google 帳號完成註冊，方可使用完整功能。
2. 您有責任妥善保管帳號密碼，並對所有使用您帳號進行的活動負責。
3. 若發現帳號遭未授權使用，請立即通知我們。
4. 您不得將帳號轉讓予他人。'''),
        _section(context, '三、使用者行為規範', '''
使用本服務時，您同意：

1. 僅上傳您本人拍攝或擁有合法授權的影片內容。
2. 不上傳任何違法、侵權或不當內容。
3. 不干擾或破壞本服務的正常運作。
4. 不嘗試未授權存取本服務的系統或資料。'''),
        _section(context, '四、影片與資料處理', '''
1. 您上傳的影片與分析資料將儲存於本服務的雲端系統，以提供揮桿分析功能。
2. 分享功能產生的分享連結有效期為 1 天，到期後將自動刪除相關檔案。
3. 您可隨時在 App 內刪除個人資料及錄影記錄。
4. 我們不會將您的個人影片提供給未經授權的第三方。'''),
        _section(context, '五、隱私政策', '''
我們重視您的隱私，並依照以下原則收集與使用您的資訊：

收集的資訊：
• 帳號資訊（電子郵件、顯示名稱）
• 揮桿影片及分析結果
• 裝置資訊與使用紀錄

使用統計追蹤（需您同意）：
• 我們可能收集匿名使用資料（功能點擊、頁面瀏覽等）
• 用於改善 App 體驗與功能設計
• 不包含個人身份資訊，可隨時在設定中關閉

資料保護：
• 所有資料傳輸採用 TLS 加密
• 伺服器端資料進行加密儲存
• 定期進行安全稽核

完整隱私政策請見：$_kPrivacyPolicyUrl'''),
        _section(context, '六、智慧財產權', '''
1. 本服務的軟體、介面設計、商標及所有相關內容均屬 ORVIA 所有，受著作權法保護。
2. 您上傳的影片著作權歸您所有，但您授予本服務使用這些內容以提供分析服務的有限授權。
3. 未經授權，您不得複製、修改或散布本服務的任何部分。'''),
        _section(context, '七、免責聲明', '''
1. 本服務提供的揮桿分析結果僅供參考，不構成專業運動指導建議。
2. 本服務以「現狀」提供，不保證服務永遠不間斷或無誤差。
3. 對於因使用本服務所產生的任何直接或間接損失，本服務不負賠償責任。
4. 揮桿練習涉及身體活動，請在安全環境下進行，並自行評估身體狀況。'''),
        _section(context, '八、服務變更與終止', '''
1. 我們保留在任何時間修改、暫停或終止本服務的權利。
2. 若本條款有重大變更，我們將透過 App 通知您。
3. 繼續使用本服務視為接受更新後的條款。'''),
        _section(context, '九、聯絡我們', '''
若您對本條款有任何疑問，請透過以下方式聯絡我們：

電子郵件：support@atk.tw
服務網站：https://orvia.atk.tw
隱私政策：$_kPrivacyPolicyUrl

本條款最後更新日期：2026 年 5 月 25 日'''),
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
                color: context.isDarkMode ? kPrimaryLight : kPrimaryDark,
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
        backgroundColor: context.isDarkMode ? context.bgPage : const Color(0xFF1AA87C),
        foregroundColor: context.isDarkMode ? context.textPrimary : Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('使用者條款與隱私政策',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
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
                label: const Text('開啟完整隱私政策'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1AA87C),
                  side: const BorderSide(color: Color(0xFF1AA87C)),
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
