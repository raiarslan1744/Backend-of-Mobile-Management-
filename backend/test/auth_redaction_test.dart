import 'package:test/test.dart';

import '../bin/server.dart';

void main() {
  test('redacts sensitive auth fields case-insensitively', () {
    const diagnostic =
        'password=plain-password Password: mixed-password PASSWORD = upper-password '
        'token=plain-token Token: mixed-token secret=plain-secret '
        'authorization: plain-authorization Authorization=upper-authorization '
        'Bearer plain-bearer-token {"password":"json-password",'
        '"authorization":"Bearer json-bearer-token"}';

    expect(() => redactSensitiveAuthText(diagnostic), returnsNormally);
    final redacted = redactSensitiveAuthText(diagnostic);
    expect(redacted, isNot(contains('plain-password')));
    expect(redacted, isNot(contains('mixed-password')));
    expect(redacted, isNot(contains('upper-password')));
    expect(redacted, isNot(contains('plain-token')));
    expect(redacted, isNot(contains('mixed-token')));
    expect(redacted, isNot(contains('plain-secret')));
    expect(redacted, isNot(contains('plain-authorization')));
    expect(redacted, isNot(contains('upper-authorization')));
    expect(redacted, isNot(contains('plain-bearer-token')));
    expect(redacted, isNot(contains('json-password')));
    expect(redacted, isNot(contains('json-bearer-token')));
    expect(redacted, contains('[redacted]'));
  });

  test(
    'redaction does not use unsupported inline regular expression flags',
    () {
      expect(
        redactSensitiveAuthText('PASSWORD=secret-value'),
        'PASSWORD=[redacted]',
      );
    },
  );
}
