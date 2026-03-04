/// Device model — matches backend. One device can have many notes.
class Device {
  Device({
    this.id,
    required this.name,
    this.createdAt,
  });

  final String? id;
  final String name;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String?,
        name: json['name'] as String,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
      );
}
