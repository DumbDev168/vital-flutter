import 'package:chopper/chopper.dart';
import 'package:fimber/fimber.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:vital_core/environment.dart';
import 'package:vital_core/exceptions.dart';
import 'package:vital_core/region.dart';
import 'package:vital_core/services/activity_service.dart';
import 'package:vital_core/services/body_service.dart';
import 'package:vital_core/services/data/link.dart';
import 'package:vital_core/services/data/user.dart';
import 'package:vital_core/services/link_service.dart';
import 'package:vital_core/services/profile_service.dart';
import 'package:vital_core/services/providers_service.dart';
import 'package:vital_core/services/sleep_service.dart';
import 'package:vital_core/services/testkits_service.dart';
import 'package:vital_core/services/user_service.dart';
import 'package:vital_core/services/utils/vital_interceptor.dart';
import 'package:vital_core/services/vitals_service.dart';
import 'package:vital_core/services/workout_service.dart';

export 'environment.dart';
export 'region.dart';
export 'core.dart';
export 'provider.dart';
export 'client_status.dart';

class VitalClient {
  late final http.Client _httpClient;
  late final Uri _baseUrl;
  late final RequestInterceptor _authInterceptor;

  // ignore: unused_field
  late final Region _region;

  // ignore: unused_field
  late final Environment _environment;

  late final activityService =
      ActivityService.create(_httpClient, _baseUrl, _authInterceptor);
  late final bodyService =
      BodyService.create(_httpClient, _baseUrl, _authInterceptor);
  late final linkService =
      LinkService.create(_httpClient, _baseUrl, _authInterceptor);
  late final profileService =
      ProfileService.create(_httpClient, _baseUrl, _authInterceptor);
  late final providersService =
      ProvidersService.create(_httpClient, _baseUrl, _authInterceptor);
  late final sleepService =
      SleepService.create(_httpClient, _baseUrl, _authInterceptor);
  late final testkitsService =
      TestkitsService.create(_httpClient, _baseUrl, _authInterceptor);
  late final userService =
      UserService.create(_httpClient, _baseUrl, _authInterceptor);
  late final vitalsService =
      VitalsService.create(_httpClient, _baseUrl, _authInterceptor);
  late final workoutService =
      WorkoutService.create(_httpClient, _baseUrl, _authInterceptor);

  // Unnamed constructor for source compatibility.
  VitalClient();

  /// Access Vital APIs through a Vital API Key. Not recommended for usage in
  /// production mobile apps.
  ///
  /// When adopting the Vital Sign-In Token scheme, use `VitalClient.forSignedInUser(...)`
  /// instead, which would perform Vital API requests on behalf of the signed-in user.
  ///
  /// https://docs.tryvital.io/wearables/sdks/authentication#vital-sign-in-token
  void init({
    required Region region,
    required Environment environment,
    required String apiKey,
  }) {
    _httpClient = http.Client();
    _baseUrl = _resolveUrl(region, environment);
    _authInterceptor = VitalInterceptor(false, apiKey);
    _region = region;
    _environment = environment;
  }

  /// Access Vital APIs on behalf of the signed-in Vital user.
  ///
  /// Note that only resources owned by the signed-in Vital user would be
  /// accessible by the Vital SDK. There are also restricted methods that are
  /// inaccessible when being authenticated as an individual user,
  /// e.g., user deletion.
  ///
  /// This only works for applications that have adopted the Vital Sign-In Token
  /// scheme.
  ///
  /// https://docs.tryvital.io/wearables/sdks/authentication#vital-sign-in-token
  VitalClient.forSignedInUser({
    required Region region,
    required Environment environment,
  }) {
    _httpClient = http.Client();
    _baseUrl = _resolveUrl(region, environment);
    _authInterceptor = VitalInterceptor(true, null);
    _region = region;
    _environment = environment;
  }

  Uri _resolveUrl(Region region, Environment environment) {
    final urls = {
      Region.eu: {
        Environment.production: 'https://api.eu.tryvital.io',
        Environment.dev: 'https://api.dev.eu.tryvital.io',
        Environment.sandbox: 'https://api.sandbox.eu.tryvital.io',
      },
      Region.us: {
        Environment.production: 'https://api.tryvital.io',
        Environment.dev: 'https://api.dev.tryvital.io',
        Environment.sandbox: 'https://api.sandbox.tryvital.io',
      }
    };
    return Uri.parse('${urls[region]![environment]!}/v2');
  }

  Future<bool> linkProvider(User user, String provider, String callback) {
    return linkService
        .createLink(user.userId!, provider, callback)
        .then((tokenResponse) {
          if (!tokenResponse.isSuccessful || tokenResponse.body == null) {
            throw VitalHTTPStatusException(
                tokenResponse.statusCode, "${tokenResponse.error}");
          }
          return tokenResponse.body!.linkToken;
        })
        .then((linkToken) => linkService.oauthProvider(
              provider: provider,
              linkToken: linkToken,
            ))
        .then((oauthResponse) => launchUrlString(oauthResponse.body!.oauthUrl!,
            mode: LaunchMode.externalApplication))
        .catchError((e) {
          Fimber.e(e);
          return false;
        });
  }

  Future<void> exchangeOAuthCode(
      {required String userId,
      required String provider,
      required String authCode}) {
    return linkService
        // The Redirect URL here is just a placeholder value.
        // linkService.exchangeOAuthCode requests the API not to redirect.
        .createLink(userId, provider, "x-vital-noop://")
        .then((tokenResponse) {
          if (!tokenResponse.isSuccessful || tokenResponse.body == null) {
            throw VitalHTTPStatusException(
                tokenResponse.statusCode, "${tokenResponse.error}");
          }
          return tokenResponse.body!.linkToken;
        })
        .then((linkToken) {
          final request = IsLinkTokenValidRequest(linkToken: linkToken);
          return linkService
              .isTokenValid(request: request)
              .then((checkResponse) {
            if (!checkResponse.isSuccessful) {
              throw VitalHTTPStatusException(
                  checkResponse.statusCode, "${checkResponse.error}");
            }
            return linkToken;
          });
        })
        .then((linkToken) => linkService.exchangeOAuthCode(
              provider: provider,
              code: authCode,
              linkToken: linkToken,
            ))
        .then((exchangeResponse) {
          if (!exchangeResponse.isSuccessful) {
            throw VitalHTTPStatusException(
                exchangeResponse.statusCode, "${exchangeResponse.error}");
          }
        });
  }
}
