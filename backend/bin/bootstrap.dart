import 'dart:io';

import 'server.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || arguments.single != '--initialize-database') {
    stderr.writeln(
      'No database changes performed. Explicit setup requires: '
      'dart run bin/bootstrap.dart --initialize-database',
    );
    exitCode = 64;
    return;
  }
  await ServerApp.initializeDatabaseForSetup();
  stdout.writeln('Explicit database initialization completed.');
}
