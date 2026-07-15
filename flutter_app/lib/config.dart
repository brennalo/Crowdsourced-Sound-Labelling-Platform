class AppConfig {
  // Change to your Cloud Run URL in production
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080', // Android emulator localhost
  );

  //static const String baseUrl = 'baseUrl';

  static const Duration httpTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);

  // Labels
  static const List<String> labels = ['environment', 'chainsaw'];

  static const Map<String, String> labelDisplayNames = {
    'environment': 'Environment',
    'chainsaw': 'Chainsaw',
  };

  static const Map<String, String> labelDescriptions = {
    'environment': 'Natural forest sounds — wind, birds, rain, insects',
    'chainsaw': 'Chainsaw or mechanical logging sounds',
  };
}
