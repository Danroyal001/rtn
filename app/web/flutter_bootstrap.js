{{flutter_js}}
{{flutter_build_config}}

// CanvasKit is served from this site rather than a CDN, so the app works on a
// network that cannot reach one and nothing loads from a third party.
_flutter.loader.load({
  config: { canvasKitBaseUrl: 'canvaskit/' },
});
