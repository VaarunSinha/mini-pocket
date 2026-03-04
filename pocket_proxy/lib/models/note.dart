/// Note model — matches backend. Belongs to a device.
/// [syncedToDesktopAt] is local-only: set when desktop pulls notes via pairing.
class Note {
  Note({
    this.id,
    required this.deviceId,
    required this.content,
    this.transcription,
    this.todoList,
    this.summary,
    this.reminders,
    this.createdAt,
    this.updatedAt,
    this.syncedToDesktopAt,
  });

  final String? id;
  final String deviceId;
  final String content;
  final String? transcription;
  final List<String>? todoList;
  final String? summary;
  final List<String>? reminders;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  /// When the desktop app last pulled this note (local only).
  final DateTime? syncedToDesktopAt;

  bool get isSyncedToDesktop => syncedToDesktopAt != null;

  Note copyWith({
    String? id,
    String? deviceId,
    String? content,
    String? transcription,
    List<String>? todoList,
    String? summary,
    List<String>? reminders,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedToDesktopAt,
  }) =>
      Note(
        id: id ?? this.id,
        deviceId: deviceId ?? this.deviceId,
        content: content ?? this.content,
        transcription: transcription ?? this.transcription,
        todoList: todoList ?? this.todoList,
        summary: summary ?? this.summary,
        reminders: reminders ?? this.reminders,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncedToDesktopAt: syncedToDesktopAt ?? this.syncedToDesktopAt,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'device_id': deviceId,
        'content': content,
        if (transcription != null) 'transcription': transcription,
        if (todoList != null) 'todo_list': todoList,
        if (summary != null) 'summary': summary,
        if (reminders != null) 'reminders': reminders,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        if (syncedToDesktopAt != null)
          'synced_to_desktop_at': syncedToDesktopAt!.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String?,
        deviceId: json['device_id'] as String,
        content: json['content'] as String,
        transcription: json['transcription'] as String?,
        todoList: (json['todo_list'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        summary: json['summary'] as String?,
        reminders: (json['reminders'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
        syncedToDesktopAt: json['synced_to_desktop_at'] != null
            ? DateTime.parse(json['synced_to_desktop_at'] as String)
            : null,
      );
}
