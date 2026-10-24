/// Keeps duplicate delivery of the same short-lived call offer from reopening
/// the incoming-call prompt during WebSocket + reconnect-queue delivery.
class IncomingCallWindow {
  IncomingCallWindow({
    this.ttl = const Duration(seconds: 65),
    this.maxEntries = 128,
  });

  final Duration ttl;
  final int maxEntries;
  final Map<String, DateTime> _seenUntil = {};

  bool shouldPresent(String callId, DateTime now) {
    _seenUntil.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
    if (_seenUntil.containsKey(callId)) return false;
    if (_seenUntil.length >= maxEntries) {
      final oldest = _seenUntil.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      _seenUntil.remove(oldest.key);
    }
    _seenUntil[callId] = now.add(ttl);
    return true;
  }
}
