// Who is logged in, which pharmacy they belong to, and their role.
// Passed to every screen so it knows whose data to show and what to allow.
class Session {
  final String uid;
  final String userName;
  final String pharmacyId;
  final String pharmacyName;
  final String inviteCode;
  final String role; // 'owner' or 'staff'
  // Every shop this person can open (the owner may have several).
  // Always includes pharmacyId.
  final List<String> shopIds;

  const Session({
    required this.uid,
    required this.userName,
    required this.pharmacyId,
    required this.pharmacyName,
    required this.inviteCode,
    required this.role,
    this.shopIds = const [],
  });

  bool get isOwner => role == 'owner';

  // True when the owner has more than one shop (shows "All shops" options)
  bool get hasManyShops => shopIds.length > 1;
}
