import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

void main() {
  test('recommendation views do not access remote data sources directly', () {
    final violations = <String>[];
    for (final file in _dartFiles('lib/view/recommendation')) {
      final source = file.readAsStringSync();
      if (source.contains('supabase_flutter') ||
          source.contains('data_sources/remote')) {
        violations.add(file.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Views must call ViewModels, not Supabase data sources.',
    );
  });

  test('recommendation ViewModels depend only on repository interfaces', () {
    final files = <File>[
      ..._dartFiles('lib/viewmodel/recommendation'),
      File('lib/viewmodel/ar/ar_recommendation_vm.dart'),
    ];
    final violations = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      if (source.contains('data_sources/remote') ||
          source.contains('repositories/adapters')) {
        violations.add(file.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'ViewModels must receive repository interfaces by injection.',
    );
  });
}
