import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../services/share_service.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

/// 從分享碼取得影片頁面
class ShareImportPage extends StatefulWidget {
  /// 下載完成後呼叫（通知首頁刷新歷史）
  final VoidCallback? onImported;

  const ShareImportPage({super.key, this.onImported});

  @override
  State<ShareImportPage> createState() => _ShareImportPageState();
}

class _ShareImportPageState extends State<ShareImportPage> {
  final _codeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  _ImportPhase _phase = _ImportPhase.input;
  _DownloadSub _downloadSub = _DownloadSub.preparing;
  ShareGetResult? _info;
  double _downloadProgress = 0;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── 查詢分享碼 ───────────────────────────────────────────────

  Future<void> _lookup() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() { _phase = _ImportPhase.looking; _error = null; });

    try {
      final code = _codeCtrl.text.trim();
      final info = await ShareService.getShareInfo(code);
      if (mounted) setState(() { _phase = _ImportPhase.preview; _info = info; });
    } catch (e) {
      if (mounted) setState(() { _phase = _ImportPhase.input; _error = e.toString(); });
    }
  }

  // ── 下載並解壓縮 ────────────────────────────────────────────

  Future<void> _download() async {
    final info = _info!;
    final code = _codeCtrl.text.trim();

    setState(() {
      _phase = _ImportPhase.downloading;
      _downloadSub = _DownloadSub.preparing;
      _downloadProgress = 0;
    });

    try {
      await ShareService.downloadAndImport(
        info: info,
        shareCode: code,
        onDownloadProgress: (p) {
          if (mounted) {
            setState(() {
              _downloadSub = _DownloadSub.downloading;
              _downloadProgress = p;
            });
          }
        },
        onStatus: (s) {
          if (mounted && s.contains('解壓')) {
            setState(() => _downloadSub = _DownloadSub.extracting);
          }
        },
      );

      if (mounted) {
        setState(() => _phase = _ImportPhase.done);
        widget.onImported?.call();
      }
    } catch (e) {
      if (mounted) setState(() { _phase = _ImportPhase.preview; _error = e.toString(); });
    }
  }

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.shareImportTitle, style: const TextStyle(fontSize: 16)),
            Text(
              context.watch<UserProvider>().displayName,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: context.textSecondary),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: context.textPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _ImportPhase.input:
      case _ImportPhase.looking:
        return _buildInputSection();
      case _ImportPhase.preview:
        return _buildPreviewSection();
      case _ImportPhase.downloading:
        return _buildDownloadingSection();
      case _ImportPhase.done:
        return _buildDoneSection();
    }
  }

  // ── 輸入分享碼 ───────────────────────────────────────────────

  Widget _buildInputSection() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.download_for_offline_outlined, size: 64, color: kBrandPrimary),
        const SizedBox(height: 24),
        Text(
          l10n.shareImportEnterCodeTitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.shareImportEnterCodeDesc,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.textSecondary),
        ),
        const SizedBox(height: 32),
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _codeCtrl,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            maxLength: 16,
            decoration: InputDecoration(
              hintText: 'xxxxxxxxxxxxxxxx',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.key_outlined),
              counterText: '',
            ),
            style: const TextStyle(letterSpacing: 2, fontFamily: 'monospace', fontSize: 16),
            validator: (v) {
              if (v == null || v.trim().length != 16) return l10n.shareImportCodeValidator;
              return null;
            },
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _phase == _ImportPhase.looking ? null : _lookup,
          icon: _phase == _ImportPhase.looking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.search),
          label: Text(_phase == _ImportPhase.looking ? l10n.shareImportLooking : l10n.shareImportLookup),
          style: FilledButton.styleFrom(
            backgroundColor: kBrandPrimary,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  // ── 預覽 ─────────────────────────────────────────────────────

  Widget _buildPreviewSection() {
    final l10n = AppLocalizations.of(context);
    final info = _info!;
    final sizeMb = (info.sizeBytes / 1024 / 1024).toStringAsFixed(1);
    final expiryStr = DateFormat('MM/dd HH:mm').format(info.expiresAt.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.video_file_outlined, size: 64, color: Color(0xFF1565C0)),
        const SizedBox(height: 20),
        Text(
          info.title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        const SizedBox(height: 20),
        if (info.sharerName != null && info.sharerName!.isNotEmpty)
          _infoRow(Icons.person_outline, l10n.shareImportFrom, info.sharerName!),
        _infoRow(Icons.storage_outlined, l10n.shareImportSize, '$sizeMb MB'),
        _infoRow(Icons.schedule_outlined, l10n.shareImportExpiry, expiryStr),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() { _phase = _ImportPhase.input; _info = null; }),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.shareImportReenter),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download),
                label: Text(l10n.shareImportDownload),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.textHint),
          const SizedBox(width: 8),
          Text('$label：', style: TextStyle(color: context.textSecondary, fontSize: 14)),
          Text(value, style: TextStyle(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── 下載中 ───────────────────────────────────────────────────

  Widget _buildDownloadingSection() {
    final l10n = AppLocalizations.of(context);
    final label = switch (_downloadSub) {
      _DownloadSub.preparing   => l10n.shareImportPreparing,
      _DownloadSub.downloading => l10n.shareImportDownloading,
      _DownloadSub.extracting  => l10n.shareImportExtracting,
    };

    // preparing / extracting → 不定式；downloading → 顯示百分比
    final progressValue = _downloadSub == _DownloadSub.downloading
        ? _downloadProgress
        : null;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_download_outlined, size: 64, color: Color(0xFF1565C0)),
          const SizedBox(height: 24),
          Text(
            label,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.textPrimary),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progressValue,
            backgroundColor: context.bgInset,
            color: const Color(0xFF1565C0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          if (_downloadSub == _DownloadSub.downloading)
            Text(
              '${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            )
          else
            const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── 完成 ─────────────────────────────────────────────────────

  Widget _buildDoneSection() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: kGoodColor),
          const SizedBox(height: 24),
          Text(l10n.shareImportDoneTitle, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary)),
          const SizedBox(height: 8),
          Text(l10n.shareImportDoneDesc, style: TextStyle(color: context.textSecondary)),
          const SizedBox(height: 40),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: kBrandPrimary,
              minimumSize: const Size(200, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(l10n.shareImportBack),
          ),
        ],
      ),
    );
  }
}

enum _ImportPhase { input, looking, preview, downloading, done }

enum _DownloadSub { preparing, downloading, extracting }
