import 'package:flutter/material.dart';

/// 可橫向縮放 / 捲動的時間軸容器。
///
/// - 雙指 pinch：橫向拉寬 / 縮小（密集切片標記自然拉開）
/// - 單指拖曳：縮放後左右捲動
/// - 點擊：seek 到該時間點（縮放後不用拖曳滑桿，避免手勢衝突）
/// - +/- 按鈕：分級縮放
///
/// 內容寬度 = 視口寬 × zoom，[painterBuilder] 以該寬度繪製時間軸，
/// painter 內部以 size.width 定位的標記會隨之拉開。
class ZoomableTimeline extends StatefulWidget {
  final double height;
  final double totalSeconds;
  final double currentSeconds;
  final ValueChanged<double> onSeek;

  /// 依內容寬度建立 painter（每次 build 重建以反映資料 / 播放頭）。
  final CustomPainter Function(double contentWidth) painterBuilder;

  /// painter 內左右 padding（供點擊 seek 對位，預設 0）。
  final double horizontalPadding;
  final double maxZoom;
  final bool followPlayhead;
  final bool showButtons;

  const ZoomableTimeline({
    super.key,
    required this.height,
    required this.totalSeconds,
    required this.currentSeconds,
    required this.onSeek,
    required this.painterBuilder,
    this.horizontalPadding = 0,
    this.maxZoom = 8.0,
    this.followPlayhead = true,
    this.showButtons = true,
  });

  @override
  State<ZoomableTimeline> createState() => _ZoomableTimelineState();
}

class _ZoomableTimelineState extends State<ZoomableTimeline> {
  double _zoom = 1.0;
  double _pan = 0.0; // 內容已捲動的 px
  double _zoomStart = 1.0;
  double _viewportW = 1.0;
  bool _interacting = false;

  void _clampPan(double contentW) {
    final maxPan = (contentW - _viewportW).clamp(0.0, double.infinity);
    if (_pan < 0) _pan = 0;
    if (_pan > maxPan) _pan = maxPan;
  }

  void _applyZoom(double newZoom, double focalX) {
    newZoom = newZoom.clamp(1.0, widget.maxZoom);
    final before = _viewportW * _zoom;
    final after = _viewportW * newZoom;
    // 以 focal point 為錨保持穩定
    final ratio = before <= 0 ? 0.0 : (_pan + focalX) / before;
    _pan = ratio * after - focalX;
    _zoom = newZoom;
    _clampPan(after);
  }

  void _stepZoom(double factor) {
    setState(() => _applyZoom(_zoom * factor, _viewportW / 2));
  }

  void _seekAt(double localX, double contentW) {
    final usable = contentW - 2 * widget.horizontalPadding;
    final x = (_pan + localX - widget.horizontalPadding);
    final sec = (x / (usable <= 0 ? 1 : usable) * widget.totalSeconds)
        .clamp(0.0, widget.totalSeconds);
    widget.onSeek(sec);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _viewportW = c.maxWidth;
        final contentW = _viewportW * _zoom;

        // 播放時自動捲動讓播放頭保持可見（使用者操作中不搶）
        if (widget.followPlayhead && _zoom > 1.0 && !_interacting) {
          final cursorX = widget.totalSeconds > 0
              ? (widget.currentSeconds / widget.totalSeconds) * contentW
              : 0.0;
          if (cursorX < _pan + _viewportW * 0.12) {
            _pan = cursorX - _viewportW * 0.12;
          } else if (cursorX > _pan + _viewportW * 0.88) {
            _pan = cursorX - _viewportW * 0.88;
          }
          _clampPan(contentW);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _zoomStart = _zoom;
                _interacting = true;
              },
              onScaleUpdate: (d) {
                setState(() {
                  if (d.pointerCount >= 2) {
                    _applyZoom(_zoomStart * d.scale, d.localFocalPoint.dx);
                  } else {
                    _pan -= d.focalPointDelta.dx;
                    _clampPan(_viewportW * _zoom);
                  }
                });
              },
              onScaleEnd: (_) => _interacting = false,
              onTapUp: (d) => _seekAt(d.localPosition.dx, contentW),
              child: ClipRect(
                child: SizedBox(
                  height: widget.height,
                  width: _viewportW,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: -_pan,
                        top: 0,
                        width: contentW,
                        height: widget.height,
                        child: CustomPaint(
                          size: Size(contentW, widget.height),
                          painter: widget.painterBuilder(contentW),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.showButtons)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_zoom > 1.0)
                      Text('${_zoom.toStringAsFixed(1)}x',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    const SizedBox(width: 6),
                    _zoomBtn(Icons.remove, _zoom > 1.0, () => _stepZoom(1 / 1.6)),
                    const SizedBox(width: 4),
                    _zoomBtn(Icons.add, _zoom < widget.maxZoom,
                        () => _stepZoom(1.6)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _zoomBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 18,
      child: Container(
        width: 26,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.14 : 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 16,
            color: Colors.white.withValues(alpha: enabled ? 0.85 : 0.25)),
      ),
    );
  }
}
