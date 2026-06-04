package com.aethertek.tekswing

/**
 * 影片輸出品質模式。
 *
 * SMALL    — 低位元率，檔案最小，適合網路傳輸 / 分享
 * STANDARD — 預設，平衡畫質與檔案大小
 * HIGH     — 高位元率，最佳畫質，適合本機保存
 */
enum class ExportQuality {
    SMALL, STANDARD, HIGH;

    companion object {
        fun fromString(value: String?): ExportQuality = when (value?.uppercase()) {
            "SMALL"    -> SMALL
            "HIGH"     -> HIGH
            else       -> STANDARD
        }
    }

    /** 位元率上限（bps） */
    val maxBitRate: Long get() = when (this) {
        SMALL    -> 10_000_000L
        STANDARD -> 20_000_000L
        HIGH     -> 40_000_000L
    }

    /** 每像素位元係數（bpp × fps，用於動態計算） */
    val bppCoeff: Double get() = when (this) {
        SMALL    -> 0.5
        STANDARD -> 0.75
        HIGH     -> 1.0
    }

    /** 最低位元率保底（bps），避免極低解析度時位元率過低 */
    val minBitRate: Long get() = when (this) {
        SMALL    -> 4_000_000L
        STANDARD -> 6_000_000L
        HIGH     -> 8_000_000L
    }
}
