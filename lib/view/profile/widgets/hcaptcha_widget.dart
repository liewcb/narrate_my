import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';

/// Renders hCaptcha's own JS challenge inside a WebView and reports the
/// solved token back via [onVerified]. There's no official Flutter SDK for
/// hCaptcha, so this hosts a minimal local HTML page carrying hCaptcha's
/// script and bridges the token out through a JavaScript channel — the
/// same approach the community `flutter_hcaptcha` packages use, done
/// directly here to avoid pulling in an extra third-party dependency for
/// one widget.
///
/// IMPORTANT — UNVERIFIED AGAINST A LIVE HCAPTCHA SITE: hCaptcha site keys
/// are normally restricted to the domain(s) registered for them in the
/// hCaptcha dashboard, and a WebView loaded via `loadHtmlString` (as this
/// widget does) has no real origin — platforms vary on what hCaptcha sees
/// (roughly `about:blank` on Android, sometimes treated as `file://`).
/// If the challenge fails to render or errors out immediately once you've
/// set a real `AppConfig.hcaptchaSiteKey`, the fix is almost certainly on
/// the hCaptcha dashboard side, not this widget: add "localhost" (hCaptcha
/// dashboard → your site → Hostnames) to the site's allowed hostnames, or
/// check hCaptcha's current docs for the recommended mobile-WebView setup
/// — this was written without a live site key to test against.
class HCaptchaWidget extends StatefulWidget {
  final ValueChanged<String> onVerified;
  final VoidCallback? onError;

  const HCaptchaWidget({super.key, required this.onVerified, this.onError});

  @override
  State<HCaptchaWidget> createState() => _HCaptchaWidgetState();
}

class _HCaptchaWidgetState extends State<HCaptchaWidget> {
  static const _channelName = 'HCaptchaChannel';

  late final WebViewController _controller;

  String get _html => '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script src="https://js.hcaptcha.com/1/api.js" async defer></script>
    <style>
      html, body {
        margin: 0; padding: 0;
        display: flex; align-items: center; justify-content: center;
        background: transparent;
      }
    </style>
  </head>
  <body>
    <div class="h-captcha"
         data-sitekey="${AppConfig.hcaptchaSiteKey}"
         data-callback="onHCaptchaVerified"
         data-error-callback="onHCaptchaError"></div>
    <script>
      function onHCaptchaVerified(token) {
        $_channelName.postMessage(token);
      }
      function onHCaptchaError() {
        $_channelName.postMessage('__error__');
      }
    </script>
  </body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..addJavaScriptChannel(
        _channelName,
        onMessageReceived: (message) {
          if (message.message == '__error__') {
            widget.onError?.call();
          } else {
            widget.onVerified(message.message);
          }
        },
      )
      ..loadHtmlString(_html);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 100,
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
