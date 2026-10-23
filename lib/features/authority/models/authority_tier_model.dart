/// Authority hierarchy tier entity mapped from public.authority_levels
class AuthorityTierModel {
  final String id;
  final int levelNumber;
  final String title;
  final int slaDays;
  final bool canResolve;

  const AuthorityTierModel({
    required this.id,
    required this.levelNumber,
    required this.title,
    required this.slaDays,
    this.canResolve = true,
  });

  factory AuthorityTierModel.fromJson(Map<String, dynamic> json) {
    return AuthorityTierModel(
      id: json['id'] as String,
      levelNumber: json['level_number'] as int,
      title: json['title'] as String,
      slaDays: json['sla_days'] as int,
      canResolve: json['can_resolve'] as bool? ?? true,
    );
  }
}
