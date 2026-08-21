import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/src/data/models/auth_models.dart';
import 'package:flutter_app/src/data/models/backend_models.dart';
import 'package:flutter_app/src/data/remote/backend_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('BackendApiClient success cases', () {
    test('login normalizes base URL and parses auth tokens', () async {
      late Uri capturedUri;
      late Map<String, String> capturedHeaders;
      late Map<String, dynamic> capturedBody;

      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net/',
        authToken: null,
        client: MockClient((request) async {
          capturedUri = request.url;
          capturedHeaders = request.headers;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'access_token': 'token-123',
              'refresh_token': 'refresh-123',
              'expires_in_seconds': 7200,
            }),
            200,
          );
        }),
      );

      final tokens = await client.login(
        'user@example.com',
        'Secret123!',
        otpCode: '123456',
      );

      expect(capturedUri.toString(), 'https://api.watchtracker.net/auth/login');
      expect(capturedHeaders['Content-Type'], 'application/json');
      expect(capturedBody, {
        'email': 'user@example.com',
        'password': 'Secret123!',
        'otp_code': '123456',
      });
      expect(tokens.accessToken, 'token-123');
      expect(tokens.refreshToken, 'refresh-123');
      expect(tokens.expiresInSeconds, 7200);
    });

    test('me parses the current user profile', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: 'abc',
        client: MockClient((request) async {
          expect(request.url.path, '/auth/me');
          return http.Response(
            jsonEncode({
              'user_id': 7,
              'email': 'user@example.com',
              'display_name': 'Sheik',
            }),
            200,
          );
        }),
      );

      final profile = await client.me();

      expect(profile.userId, 7);
      expect(profile.email, 'user@example.com');
      expect(profile.displayName, 'Sheik');
    });

    test('getSyncSnapshot parses nested sync payloads', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: 'abc',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://api.watchtracker.net/sync/snapshot?since=123',
          );
          return http.Response(
            jsonEncode({
              'snapshot_at': '2026-08-21T10:00:00Z',
              'watchlist': [
                {
                  'id': 99,
                  'title': 'Lost',
                  'poster_path': '/lost.jpg',
                  'media_type': 'tv',
                  'content_category': 'series',
                  'content_status': 'in_progress',
                  'total_episodes': 121,
                },
              ],
              'episode_progress': [
                {
                  'media_id': 99,
                  'season_number': 1,
                  'episode_number': 1,
                  'is_watched': true,
                },
              ],
              'watchlist_tombstones': [
                {
                  'id': 5,
                  'media_type': 'movie',
                  'content_category': 'films',
                  'deleted_at': '2026-08-20T10:00:00Z',
                },
              ],
              'episode_progress_tombstones': [
                {
                  'media_id': 99,
                  'season_number': 1,
                  'episode_number': 2,
                  'deleted_at': '2026-08-20T10:00:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );

      final snapshot = await client.getSyncSnapshot(sinceMillis: 123);

      expect(snapshot.watchlist.single.title, 'Lost');
      expect(snapshot.episodeProgress.single.isWatched, isTrue);
      expect(snapshot.watchlistTombstones.single.id, 5);
      expect(snapshot.episodeProgressTombstones.single.episodeNumber, 2);
      expect(snapshot.snapshotAtMillis, greaterThan(0));
    });

    test(
      'refresh accepts token fallback field and default expiration',
      () async {
        final client = BackendApiClient(
          baseUrl: 'https://api.watchtracker.net',
          authToken: null,
          client: MockClient(
            (_) async =>
                http.Response(jsonEncode({'token': 'legacy-token'}), 200),
          ),
        );

        final tokens = await client.refresh('refresh-token');

        expect(tokens.accessToken, 'legacy-token');
        expect(tokens.refreshToken, isNull);
        expect(tokens.expiresInSeconds, 3600);
      },
    );

    test('builds with the default HTTP client', () {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
      );

      expect(client, isA<BackendApiClient>());
    });

    test('updateMe sends a PATCH with display name payload', () async {
      late String method;
      late Uri uri;
      late Map<String, dynamic> body;

      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: 'token',
        client: MockClient((request) async {
          method = request.method;
          uri = request.url;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'user_id': 1,
              'email': 'user@example.com',
              'display_name': 'New Name',
            }),
            200,
          );
        }),
      );

      final profile = await client.updateMe('New Name');

      expect(method, 'PATCH');
      expect(uri.path, '/auth/me');
      expect(body, {'display_name': 'New Name'});
      expect(profile.displayName, 'New Name');
    });

    test('logout, deleteMe, resendVerification, forgotPassword and changePassword hit expected endpoints', () async {
      final requests = <String>[];

      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: 'token',
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path} ${request.body}');
          return http.Response(jsonEncode({'message': 'OK'}), 200);
        }),
      );

      await client.logout('refresh-token');
      await client.deleteMe();
      final resend = await client.resendVerification('user@example.com');
      final forgot = await client.forgotPassword('user@example.com');
      final changed = await client.changePassword('old', 'new');

      expect(resend, 'OK');
      expect(forgot, 'OK');
      expect(changed, 'OK');
      expect(
        requests,
        containsAll(<String>[
          'POST /auth/logout {"refresh_token":"refresh-token"}',
          'DELETE /auth/me ',
          'POST /auth/resend-verification {"email":"user@example.com"}',
          'POST /auth/forgot-password {"email":"user@example.com"}',
          'POST /auth/change-password {"current_password":"old","new_password":"new"}',
        ]),
      );
    });

    test('watchlist and episode methods serialize requests and parse lists', () async {
      final seen = <String>[];
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: 'token',
        client: MockClient((request) async {
          seen.add(
            '${request.method} ${request.url.toString()} ${request.body}',
          );
          switch (request.url.path) {
            case '/watchlist':
              if (request.method == 'GET') {
                return http.Response(
                  jsonEncode([
                    {
                      'id': 1,
                      'title': 'Title',
                      'poster_path': '/poster.jpg',
                      'media_type': 'tv',
                      'content_category': 'series',
                      'content_status': 'in_progress',
                      'total_episodes': 12,
                    },
                  ]),
                  200,
                );
              }
              return http.Response('{}', 200);
            case '/episode-progress/1':
              if (request.method == 'GET') {
                return http.Response(
                  jsonEncode([
                    {
                      'media_id': 1,
                      'season_number': 1,
                      'episode_number': 3,
                      'is_watched': true,
                    },
                  ]),
                  200,
                );
              }
              return http.Response('{}', 200);
            default:
              return http.Response('{}', 200);
          }
        }),
      );

      final watchlist = await client.getWatchlist(contentCategory: 'series');
      final progress = await client.getEpisodeProgress(1);
      await client.upsertWatchlist(
        const RemoteWatchlistItem(
          id: 1,
          title: 'Title',
          posterPath: null,
          mediaType: 'tv',
          contentCategory: 'series',
          contentStatus: 'in_progress',
          totalEpisodes: 12,
        ),
      );
      await client.deleteWatchlist(
        mediaId: 1,
        mediaType: 'tv',
        contentCategory: 'series',
      );
      await client.updateWatchStatus(
        mediaId: 1,
        mediaType: 'tv',
        contentCategory: 'series',
        contentStatus: 'completed',
      );
      await client.updateWatchTotal(
        mediaId: 1,
        mediaType: 'tv',
        contentCategory: 'series',
        totalEpisodes: 20,
      );
      await client.replaceEpisodeProgress(1, const [
        RemoteEpisodeProgress(
          mediaId: 1,
          seasonNumber: 1,
          episodeNumber: 3,
          isWatched: true,
        ),
      ]);
      await client.deleteEpisodeProgress(
        mediaId: 1,
        seasonNumber: 1,
        episodeNumber: 3,
      );

      expect(watchlist.single.title, 'Title');
      expect(progress.single.episodeNumber, 3);
      expect(
        seen,
        containsAll(<String>[
          'GET https://api.watchtracker.net/watchlist?content_category=series ',
          'GET https://api.watchtracker.net/episode-progress/1 ',
          'POST https://api.watchtracker.net/watchlist {"id":1,"title":"Title","poster_path":null,"media_type":"tv","content_category":"series","content_status":"in_progress","total_episodes":12}',
          'DELETE https://api.watchtracker.net/watchlist/1/tv/series ',
          'PATCH https://api.watchtracker.net/watchlist/1/tv/series/status {"content_status":"completed"}',
          'PATCH https://api.watchtracker.net/watchlist/1/tv/series/total-episodes {"total_episodes":20}',
          'PUT https://api.watchtracker.net/episode-progress/1 [{"media_id":1,"season_number":1,"episode_number":3,"is_watched":true}]',
          'DELETE https://api.watchtracker.net/episode-progress/1/1/3 ',
        ]),
      );
    });
  });

  group('BackendApiClient error mapping', () {
    test('register maps 400 to password policy guidance', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'detail': 'Password must contain at least 10 characters',
            }),
            400,
          ),
        ),
      );

      await expectLater(
        client.register('user@example.com', 'short'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Le mot de passe doit contenir au moins 10 caractères.',
          ),
        ),
      );
    });

    test('maps 401 with otp requirement and retry headers', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Two-factor code required'}),
            401,
            headers: {'retry-after': '10', 'x-auth-attempts-remaining': '2'},
          ),
        ),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>()
              .having(
                (e) => e.message,
                'message',
                'Le code 2FA est requis pour ce compte.',
              )
              .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 10)
              .having((e) => e.attemptsRemaining, 'attemptsRemaining', 2)
              .having((e) => e.requiresOtp, 'requiresOtp', isTrue),
        ),
      );
    });

    test('maps 429 to anti-bruteforce message', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: MockClient(
          (_) async => http.Response('{}', 429, headers: {'retry-after': '60'}),
        ),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>()
              .having(
                (e) => e.message,
                'message',
                'Identifiants invalides à répétition : protection anti-bruteforce activée.',
              )
              .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 60),
        ),
      );
    });

    test('maps TimeoutException to a friendly connectivity message', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: _ThrowingClient(TimeoutException('timeout')),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains(
              'Délai dépassé pour contacter l\'API (api.watchtracker.net:443)',
            ),
          ),
        ),
      );
    });

    test('maps SocketException on HTTP base URL to HTTPS guidance', () async {
      final client = BackendApiClient(
        baseUrl: 'http://api.watchtracker.net',
        authToken: null,
        client: _ThrowingClient(const SocketException('failed host lookup')),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Impossible de contacter l\'API (api.watchtracker.net:80). Utilise HTTPS pour Android release.',
          ),
        ),
      );
    });

    test('maps HandshakeException to TLS guidance', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: _ThrowingClient(HandshakeException('bad certificate')),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Certificat TLS invalide (api.watchtracker.net)'),
          ),
        ),
      );
    });

    test(
      'maps SocketException on HTTPS base URL to reachability guidance',
      () async {
        final client = BackendApiClient(
          baseUrl: 'https://api.watchtracker.net',
          authToken: null,
          client: _ThrowingClient(const SocketException('failed host lookup')),
        );

        await expectLater(
          client.login('user@example.com', 'Secret123!'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              contains(
                'Impossible de contacter l\'API (api.watchtracker.net:443). Vérifie que le serveur est accessible.',
              ),
            ),
          ),
        );
      },
    );

    test('maps 403 to unverified email message', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: MockClient((_) async => http.Response('{}', 403)),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Ton email n\'est pas encore vérifié.',
          ),
        ),
      );
    });

    test('maps 409 to duplicate email message', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: MockClient((_) async => http.Response('{}', 409)),
      );

      await expectLater(
        client.register('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Cet email est déjà utilisé.',
          ),
        ),
      );
    });

    test('maps 503 using friendly backend detail when present', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'detail': 'Invalid token'}), 503),
        ),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Session expirée. Reconnectez-vous et réessayez.',
          ),
        ),
      );
    });

    test(
      'throws when an object response is expected but list is returned',
      () async {
        final client = BackendApiClient(
          baseUrl: 'https://api.watchtracker.net',
          authToken: null,
          client: MockClient((_) async => http.Response(jsonEncode([]), 200)),
        );

        await expectLater(
          client.register('user@example.com', 'Secret123!'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Réponse backend invalide: objet attendu',
            ),
          ),
        );
      },
    );

    test(
      'throws when a list response is expected but object is returned',
      () async {
        final client = BackendApiClient(
          baseUrl: 'https://api.watchtracker.net',
          authToken: null,
          client: MockClient(
            (_) async => http.Response(jsonEncode({'bad': true}), 200),
          ),
        );

        await expectLater(
          client.getWatchlist(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Réponse backend invalide: liste attendue',
            ),
          ),
        );
      },
    );

    test('maps 500 to a generic server error', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: MockClient((_) async => http.Response('{}', 500)),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Erreur serveur (500).',
          ),
        ),
      );
    });

    test('throws when token is missing from auth response', () async {
      final client = BackendApiClient(
        baseUrl: 'https://api.watchtracker.net',
        authToken: null,
        client: MockClient(
          (_) async => http.Response(jsonEncode({'refresh_token': 'x'}), 200),
        ),
      );

      await expectLater(
        client.login('user@example.com', 'Secret123!'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Token backend manquant',
          ),
        ),
      );
    });

    test(
      'returns fallback success messages when backend omits message field',
      () async {
        final client = BackendApiClient(
          baseUrl: 'https://api.watchtracker.net',
          authToken: null,
          client: MockClient((_) async => http.Response('{}', 200)),
        );

        expect(
          await client.register('user@example.com', 'Secret123!'),
          'Inscription réussie',
        );
        expect(
          await client.resendVerification('user@example.com'),
          'Email envoyé',
        );
        expect(await client.forgotPassword('user@example.com'), 'Email envoyé');
        expect(
          await client.changePassword('old', 'new'),
          'Mot de passe modifié',
        );
      },
    );
  });
}

class _ThrowingClient extends http.BaseClient {
  _ThrowingClient(this.error);

  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future<http.StreamedResponse>.error(error);
  }
}
