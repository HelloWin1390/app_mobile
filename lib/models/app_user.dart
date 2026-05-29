class AppUser {
  final int userId;
  final String username;
  final String role;

  const AppUser({
    required this.userId,
    required this.username,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'operator',
    );
  }
}
