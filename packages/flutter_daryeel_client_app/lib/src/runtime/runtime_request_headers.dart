Map<String, String> mergeRuntimeRequestHeaders({
  required Map<String, String> correlationHeaders,
  Map<String, String> Function()? requestHeadersProvider,
}) {
  Map<String, String> extra;
  try {
    extra = requestHeadersProvider?.call() ?? const <String, String>{};
  } catch (_) {
    extra = const <String, String>{};
  }

  if (extra.isEmpty) return correlationHeaders;
  if (correlationHeaders.isEmpty) return extra;

  // Let the runtime keep control of correlation IDs.
  return <String, String>{...extra, ...correlationHeaders};
}
