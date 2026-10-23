import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/src/data/remote/tvdb_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('TvdbApiClient auth concurrency', () {
    test(
      'des appels concurrents ne déclenchent qu’un seul login TVDB',
      () async {
        var loginCalls = 0;
        final loginCompleters = <Completer<void>>[];

        final client = TvdbApiClient(
          apiKey: 'test-key',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              loginCalls++;
              final completer = Completer<void>();
              loginCompleters.add(completer);
              // Simule une latence réseau pour laisser le temps à un second
              // appel concurrent de déclencher (ou non) un autre login.
              await Future.delayed(const Duration(milliseconds: 20));
              return http.Response(
                jsonEncode({
                  'data': {'token': 'tok-123'},
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'data': {
                  'seasons': <dynamic>[],
                  'episodes': <dynamic>[],
                },
              }),
              200,
            );
          }),
        );

        // Deux appels qui déclenchent chacun _ensureAuth() en parallèle.
        final results = await Future.wait([
          client.getSeasonsWithCounts(1),
          client.getSeasonsWithCounts(2),
        ]);

        expect(results.length, 2);
        expect(
          loginCalls,
          1,
          reason:
              'un seul login TVDB doit être déclenché malgré deux appels '
              'concurrents',
        );
      },
    );
  });
}
