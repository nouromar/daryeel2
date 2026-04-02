import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlLauncherOpenUrlHandler extends OpenUrlHandler {
  const UrlLauncherOpenUrlHandler();

  @override
  Future<void> openUrl(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok) {
      throw StateError('Could not launch url');
    }
  }
}
