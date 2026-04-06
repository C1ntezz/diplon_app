class AppUser {
  final String id;
  final String username;
  final String? displayName;

  AppUser({required this.id, required this.username, this.displayName});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        displayName: j['displayName']?.toString(),
      );

  String get title {
    final dn = (displayName ?? '').trim();
    return dn.isNotEmpty ? dn : '@';
  }
}
