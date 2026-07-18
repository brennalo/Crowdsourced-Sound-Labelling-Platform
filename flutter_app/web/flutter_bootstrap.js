// prettier-ignore
{{flutter_js}}
// prettier-ignore
{{flutter_build_config}}
// prettier-ignore
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "/canvaskit/",
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
  },
});
