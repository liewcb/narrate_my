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
/// FIXED (Foo: clicking the "I am human" checkbox showed hCaptcha's own
/// "Invalid data" error, then this widget's onError -> "Verification
/// failed. Please try again."). Root cause: `loadHtmlString` with no
/// `baseUrl` gives the WebView no real origin (`about:blank` on Android),
/// and hCaptcha's own JS needs a plausible `https://` document location to
/// compute internally before it will process a checkbox click — hCaptcha's
/// own official Flutter guide sidesteps this entirely by hosting the HTML
/// on a real domain and loading it via a URL instead of `loadHtmlString`.
/// Since this app has no static hosting to spare for one file, the
/// practical fix is passing a `baseUrl` below: the WebView never actually
/// makes a network request to it (hCaptcha's own requests still go to its
/// own API domains) — it only needs to look like a real HTTPS origin.
/// Domain allowlisting is OFF by default on hCaptcha sites, so this
/// placeholder domain does NOT need to be added anywhere on the hCaptcha
/// dashboard for this to work; it only matters if you deliberately turn
/// allowlisting on later, in which case add this same host there too.
class HCaptchaWidget extends StatefulWidget {
  final ValueChanged<String> onVerified;
  final VoidCallback? onError;

  const HCaptchaWidget({super.key, required this.onVerified, this.onError});

  @override
  State<HCaptchaWidget> createState() => _HCaptchaWidgetState();
}

class _HCaptchaWidgetState extends State<HCaptchaWidget> {
  static const _channelName = 'HCaptchaChannel';

  /// Placeholder HTTPS origin so the WebView isn't `about:blank` — see the
  /// class doc comment above. No network request is ever sent to this
  /// host; it exists purely so hCaptcha's JS has a real-looking
  /// `document.location` to work with.
  static const _baseUrl = 'https://narratemy-app.local/';

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
      ..loadHtmlString(_html, baseUrl: _baseUrl);
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
