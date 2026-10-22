import 'package:web/web.dart' as web;

/// Dynamically inject Google Maps JavaScript SDK into `<head>` on Web platform
void loadWebGoogleMaps(String apiKey) {
  if (apiKey.isEmpty) return;
  if (web.document.getElementById('google-maps-sdk') != null) return;

  final script = web.HTMLScriptElement()
    ..id = 'google-maps-sdk'
    ..src = 'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeComponent(apiKey)}'
    ..async = true;

  web.document.head?.appendChild(script);
}
