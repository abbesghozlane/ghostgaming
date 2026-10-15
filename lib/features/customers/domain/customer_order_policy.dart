bool canAttachPreSessionOrder({
  required String requestStatus,
  required String? orderSessionId,
  required String? sessionStatus,
}) =>
    requestStatus == 'completed' &&
    orderSessionId == null &&
    (sessionStatus == 'active' || sessionStatus == 'paused');
