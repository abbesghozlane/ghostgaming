class CustomerQrToken {
  const CustomerQrToken._();

  static String? fromScannedValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    final token = uri != null && (uri.hasScheme || uri.hasAuthority)
        ? uri.queryParameters['token']
        : trimmed;
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }
}
