Map<String, dynamic>? selectCustomerSession({
  required List<Map<String, dynamic>> sessions,
  String? requestedSessionId,
  String? selectedSessionId,
}) {
  final preferredSessionId = requestedSessionId ?? selectedSessionId;
  return sessions
          .where((session) => session['id'] == preferredSessionId)
          .firstOrNull ??
      sessions.firstOrNull;
}
