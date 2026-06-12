import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/export_spec.dart';
import '../theme/app_theme.dart';

/// 自訂匯出 sheet：勾選疊加元素（骨架 / 軌跡），浮水印由方案決定。
///
/// 回傳使用者選定的 [ExportSpec]，取消則回傳 null。
/// [isFree] 為 true 時浮水印強制開啟、UI 不可關。
class CustomExportSheet extends StatefulWidget {
  final bool hasSkeleton;
  final bool hasTrajectory;
  /// 是否具備擊球時刻（光暈/甜蜜點特效的前提）。
  final bool hasImpact;
  /// 是否具備擊球品質資料（甜蜜點色彩的前提）。
  final bool hasShotQuality;
  final bool isFree;
  const CustomExportSheet({
    super.key,
    required this.hasSkeleton,
    required this.hasTrajectory,
    this.hasImpact = false,
    this.hasShotQuality = false,
    required this.isFree,
  });

  @override
  State<CustomExportSheet> createState() => _CustomExportSheetState();
}

class _CustomExportSheetState extends State<CustomExportSheet> {
  bool _skeleton = false;
  bool _trajectory = false;
  bool _hitGlow = false;
  bool _sweetSpot = false;

  @override
  void initState() {
    super.initState();
    // 預設把可用的疊加元素都勾上
    _skeleton = widget.hasSkeleton;
    _trajectory = widget.hasTrajectory;
    // 擊球特效預設不勾（避免畫面太花），由使用者主動開啟
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, color: kBrandPrimary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l10n.exportCustomTitle,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l10n.exportCustomSubtitle,
                style: TextStyle(fontSize: 12, color: context.textSecondary)),
            const SizedBox(height: 12),

            if (widget.hasSkeleton)
              _toggleTile(
                icon: Icons.accessibility_new_rounded,
                title: l10n.exportElementSkeleton,
                subtitle: l10n.exportElementSkeletonDesc,
                value: _skeleton,
                onChanged: (v) => setState(() => _skeleton = v),
              ),
            if (widget.hasTrajectory)
              _toggleTile(
                icon: Icons.timeline_rounded,
                title: l10n.exportElementTrajectory,
                subtitle: l10n.exportElementTrajectoryDesc,
                value: _trajectory,
                onChanged: (v) => setState(() => _trajectory = v),
              ),
            if (widget.hasImpact)
              _toggleTile(
                icon: Icons.blur_on_rounded,
                title: l10n.exportElementGlow,
                subtitle: l10n.exportElementGlowDesc,
                value: _hitGlow,
                onChanged: (v) => setState(() => _hitGlow = v),
              ),
            if (widget.hasImpact && widget.hasShotQuality)
              _toggleTile(
                icon: Icons.adjust_rounded,
                title: l10n.exportElementSweetSpot,
                subtitle: l10n.exportElementSweetSpotDesc,
                value: _sweetSpot,
                onChanged: (v) => setState(() => _sweetSpot = v),
              ),
            if (!widget.hasSkeleton && !widget.hasTrajectory && !widget.hasImpact)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.exportNoOverlayMaterial,
                    style: TextStyle(fontSize: 13, color: context.textSecondary)),
              ),

            const SizedBox(height: 8),

            // 浮水印說明：免費版強制、付費版無浮水印
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (widget.isFree ? Colors.amber : kBrandPrimary)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isFree ? Icons.water_drop_outlined : Icons.verified_rounded,
                    size: 18,
                    color: widget.isFree ? Colors.amber[800] : kBrandPrimary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.isFree ? l10n.exportWatermarkFree : l10n.exportWatermarkPaid,
                      style: TextStyle(
                          fontSize: 12.5, color: context.textSecondary, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kBrandPrimary),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(l10n.exportComposeAndDownload),
                onPressed: () => Navigator.pop(
                  context,
                  ExportSpec(
                    skeleton: _skeleton,
                    trajectory: _trajectory,
                    hitGlow: _hitGlow,
                    sweetSpot: _sweetSpot,
                    watermark: widget.isFree, // 免費強制
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: kBrandPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kBrandPrimary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: context.textSecondary)),
              ],
            ),
          ),
          Switch(value: value, activeThumbColor: kBrandPrimary, onChanged: onChanged),
        ],
      ),
    );
  }
}
