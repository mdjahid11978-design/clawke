import 'package:client/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug database file resolves under repo runtime directory', () async {
    final file = await resolveDatabaseFile('test_uid');

    expect(file.path, endsWith('/.runtime/db/clawke_test_uid.db'));
  });
}
