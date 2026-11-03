/// Canonical peer DM conversation id — same format as Messenger/WhatsApp thread keys.
/// Always lowercased + sorted so A↔B and B↔A open the same history.
String canonicalPeerDmId(String userA, String userB) {
  final a = userA.trim().toLowerCase();
  final b = userB.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return '';
  final pair = [a, b]..sort();
  return 'peer_dm_${pair[0]}__${pair[1]}';
}

bool isSamePeerDm(String a, String b) {
  if (a == b) return true;
  if (!a.startsWith('peer_dm_') || !b.startsWith('peer_dm_')) return false;
  final cleanA = a.replaceFirst('peer_dm_', '').split('__');
  final cleanB = b.replaceFirst('peer_dm_', '').split('__');
  if (cleanA.length != 2 || cleanB.length != 2) return false;
  return cleanA.map((s) => s.toLowerCase().trim()).toSet().containsAll(
        cleanB.map((s) => s.toLowerCase().trim()),
      );
}
