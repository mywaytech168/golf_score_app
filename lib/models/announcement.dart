import 'package:flutter/material.dart';

enum AnnouncementType {
  info,
  important,
  event,
  update;

  String get label => switch (this) {
    info      => '通知',
    important => '重要',
    event     => '活動',
    update    => '更新',
  };

  Color get color => switch (this) {
    info      => const Color(0xFF2E8EFF),
    important => const Color(0xFFE05252),
    event     => const Color(0xFFFF9800),
    update    => const Color(0xFF1AA87C),
  };

  IconData get icon => switch (this) {
    info      => Icons.info_outline_rounded,
    important => Icons.warning_amber_rounded,
    event     => Icons.celebration_rounded,
    update    => Icons.system_update_rounded,
  };

  static AnnouncementType fromString(String? s) => switch (s) {
    'important' => important,
    'event'     => event,
    'update'    => update,
    _           => info,
  };
}

class Announcement {
  final String id;
  final String title;
  final String body;
  final AnnouncementType type;
  final DateTime publishedAt;
  final DateTime? expiresAt;
  final String? imageUrl;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.publishedAt,
    this.expiresAt,
    this.imageUrl,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id:          json['id']?.toString()    ?? '',
      title:       json['title']  as String? ?? '',
      body:        json['body']   as String? ?? '',
      type:        AnnouncementType.fromString(json['type'] as String?),
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? '') ??
                   DateTime.now(),
      expiresAt:   json['expiresAt'] != null
                   ? DateTime.tryParse(json['expiresAt'] as String)
                   : null,
      imageUrl:    json['imageUrl'] as String?,
    );
  }

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
}
