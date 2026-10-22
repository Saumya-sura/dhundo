import 'web_maps_loader_stub.dart'
    if (dart.library.js_interop) 'web_maps_loader_web.dart' as loader;

/// Initialize Google Maps JavaScript SDK dynamically on Web
void initWebGoogleMaps(String apiKey) {
  loader.loadWebGoogleMaps(apiKey);
}
