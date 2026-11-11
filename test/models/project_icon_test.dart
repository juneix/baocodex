import 'package:baocode_mobile/models/project_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the four wire shapes of ProjectInfo.icon', () {
    expect(
      ProjectIcon.parse({'type': 'emoji', 'emoji': '📦'}),
      isA<ProjectEmojiIcon>().having((i) => i.emoji, 'emoji', '📦'),
    );
    expect(
      ProjectIcon.parse({'type': 'codicon', 'name': 'rocket', 'color': 'blue'}),
      isA<ProjectCodiconIcon>()
          .having((i) => i.name, 'name', 'rocket')
          .having((i) => i.color, 'color', 'blue'),
    );
    expect(
      ProjectIcon.parse({'type': 'image', 'id': 'abc'}),
      isA<ProjectImageIcon>().having((i) => i.id, 'id', 'abc'),
    );
    expect(
      ProjectIcon.parse({'type': 'brand', 'name': 'OpenAI'}),
      isA<ProjectBrandIcon>().having((i) => i.name, 'name', 'OpenAI'),
    );
  });

  test('null, malformed, and empty fields all parse to null', () {
    expect(ProjectIcon.parse(null), isNull);
    expect(ProjectIcon.parse('emoji'), isNull);
    expect(ProjectIcon.parse(<String, Object?>{}), isNull);
    expect(ProjectIcon.parse({'type': 'emoji'}), isNull);
    expect(ProjectIcon.parse({'type': 'emoji', 'emoji': ''}), isNull);
    expect(ProjectIcon.parse({'type': 'image'}), isNull);
    expect(ProjectIcon.parse({'type': 'image', 'id': 42}), isNull);
    expect(ProjectIcon.parse({'type': 'unknown'}), isNull);
  });
}
