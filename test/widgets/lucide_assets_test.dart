import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('所有静态 LucideIcon 名称均有对应资源', () {
    final pattern = RegExp(r'''LucideIcon\(\s*['"]([^'"]+)['"]''');
    final missing = <String>{};
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        if (!File('assets/icons/lucide-${match[1]}.svg').existsSync()) {
          missing.add(match[1]!);
        }
      }
    }
    for (final name in ['chevron-down', 'chevron-up']) {
      expect(File('assets/icons/lucide-$name.svg').existsSync(), isTrue);
    }
    expect(missing, isEmpty);
  });
}
