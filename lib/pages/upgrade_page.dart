import 'package:flutter/material.dart';

class UpgradePage extends StatelessWidget {
  const UpgradePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade Plan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPlanBoard(context),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E8E5A),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _showPaySheet(context),
            child: const Text('Upgrade right now'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanBoard(BuildContext context) {
    final plans = [
      ('免設備', '免費版'),
      ('免設備', 'Upgrade'),
      ('IOS AppleWatch', '免費版'),
      ('IOS AppleWatch', 'Upgrade'),
      ('IOS/Android Tekswing 環', '免費版'),
      ('IOS/Android Tekswing 環', 'Upgrade'),
    ];
    const rowHeight = 42.0;
    final features = [
      '打擊錄影分享功能',
      '每日練習擊球資訊',
      '基礎參數分析',
      '自動比對歷史擊球數據',
      '姿態分析功能',
      '長打影片分片功能',
      '去廣告',
      '去浮水印',
      '飛行軌跡',
      'AI教練',
      '1TB雲端影片空間',
    ];
    final matrix = [
      ['O', 'O', 'O', 'O', 'O', 'O'],
      ['O', 'O', 'O', 'O', 'O', 'O'],
      ['O', 'O', 'O', 'O', 'O', 'O'],
      ['X', 'O', 'X', 'O', 'X', 'O'],
      ['X', 'O', 'X', 'O', 'X', 'O'],
      ['X', 'O', 'X', 'O', 'X', 'O'],
      ['X', 'O', 'X', 'O', 'X', 'O'],
      ['X', 'O', 'X', 'O', 'X', 'O'],
      ['X', 'O', 'X', 'O', 'X', 'O'],
      ['X', 'O', 'X', 'O', 'X', 'O'],
      ['X', 'O', 'X', 'O', 'X', 'O'],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('方案功能一覽', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 固定左欄
              SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('功能', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    for (final f in features)
                      SizedBox(
                        height: rowHeight,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(f),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 可水平捲動的方案欄
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var c = 0; c < plans.length; c++)
                        Container(
                          width: 130,
                          margin: EdgeInsets.only(right: c == plans.length - 1 ? 0 : 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(plans[c].$1,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(plans[c].$2, style: const TextStyle(color: Colors.black54)),
                              const Divider(),
                              for (var r = 0; r < features.length; r++)
                                SizedBox(
                                  height: rowHeight,
                                  child: Center(
                                    child: Icon(
                                      matrix[r][c] == 'O' ? Icons.circle : Icons.close,
                                      size: 18,
                                      color: matrix[r][c] == 'O'
                                          ? const Color(0xFF1E8E5A)
                                          : Colors.redAccent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPaySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('選擇付款方式', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _payOption(context, 'LINE Pay'),
              _payOption(context, 'Apple Pay'),
              _payOption(context, 'Google Pay'),
              _payOption(context, '信用卡'),
            ],
          ),
        );
      },
    );
  }

  Widget _payOption(BuildContext context, String label) {
    return ListTile(
      leading: const Icon(Icons.payment),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        _showSuccessDialog(context, label);
      },
    );
  }

  void _showSuccessDialog(BuildContext context, String method) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('付款成功'),
        content: Text('已透過 $method 完成升級。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
}
