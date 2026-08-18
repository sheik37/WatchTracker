import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/src/data/models/media_models.dart';

void main() {
  test('media type parsing fallback', () {
    expect(MediaType.fromString('movie'), MediaType.movie);
    expect(MediaType.fromString('tv'), MediaType.tv);
    expect(MediaType.fromString('x'), MediaType.movie);
  });
}
