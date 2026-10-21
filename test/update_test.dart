import 'package:flutter_test/flutter_test.dart';
import 'package:photokeeper/update.dart';

void main() {
  test('release tag vs running version', () {
    expect(isNewer('v0.0.2', '0.0.1'), true);
    expect(isNewer('0.0.2', '0.0.1+1'), true, reason: 'the 0.0.1 release was tagged without a v');
    expect(isNewer('v0.0.10', '0.0.9'), true, reason: 'numeric, not string, compare');
    expect(isNewer('v1.0', '0.9.9'), true);
    expect(isNewer('v0.0.2', '0.0.2+5'), false, reason: 'build number is not a newer release');
    expect(isNewer('v0.0.1', '0.0.2'), false);
  });
}
