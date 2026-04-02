/// Restrictive policy for allowing remote URIs.
///
/// Intended for schema-driven behaviors (open_url) and future remote assets.
/// Keep it simple and safe:
/// - default is allow-all (legacy), but apps should configure allowlists.
class UriPolicy {
  const UriPolicy({
    this.allowedSchemes,
    this.allowedHosts,
  });

  const UriPolicy.allowAll()
      : allowedSchemes = null,
        allowedHosts = null;

  /// Null means allow all.
  final Set<String>? allowedSchemes;

  /// Null means allow all.
  final Set<String>? allowedHosts;

  bool isAllowed(Uri uri) {
    final schemes = allowedSchemes;
    if (schemes != null && !schemes.contains(uri.scheme)) {
      return false;
    }
    final hosts = allowedHosts;
    if (hosts != null && !hosts.contains(uri.host)) {
      return false;
    }
    return true;
  }
}
