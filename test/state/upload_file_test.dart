import 'package:baocode_mobile/state/upload_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isHostAbsolutePath', () {
    test('Unix 绝对路径算数', () {
      expect(isHostAbsolutePath('/Users/dev/project/file.txt'), isTrue);
      expect(isHostAbsolutePath('/tmp/file'), isTrue);
      expect(isHostAbsolutePath('relative/path.txt'), isFalse);
    });

    test('Windows 盘符和 UNC 路径算数', () {
      expect(isHostAbsolutePath(r'C:\Users\dev\file.txt'), isTrue);
      expect(isHostAbsolutePath('D:/repos/code.dart'), isTrue);
      expect(isHostAbsolutePath(r'\\server\share\file.txt'), isTrue);
      expect(isHostAbsolutePath(r'foo\bar.txt'), isFalse);
    });
  });

  group('fileMentionText', () {
    test('普通路径写成 @路径', () {
      expect(fileMentionText('/tmp/a.txt'), '@/tmp/a.txt');
    });

    test('带空格等特殊字符的路径加引号', () {
      expect(fileMentionText('/tmp/my file.txt'), '@"/tmp/my file.txt"');
    });
  });

  group('parseFileMention', () {
    test('读到路径的结束位置', () {
      const text = '看看 @/tmp/a.txt 这个文件';
      final mention = parseFileMention(text, 3);
      expect(mention, isNotNull);
      expect(mention!.path, '/tmp/a.txt');
      expect(text.substring(0, mention.end).endsWith('/tmp/a.txt'), isTrue);
    });

    test('不是路径的 @ 不算引用', () {
      expect(parseFileMention('@某人 你好', 0), isNull);
    });

    test('引号里可以有空格', () {
      const text = '@/tmp/my file.txt';
      expect(parseFileMention(text, 0)?.path, '/tmp/my file.txt');
    });
  });

  group('fileReferenceRegion', () {
    test('末尾独立的引用从正文里分出来', () {
      const text = '帮忙看下\n@/tmp/a.txt\n@/tmp/b.txt';
      final region = fileReferenceRegion(text);
      expect(region.body, '帮忙看下');
      expect(region.paths, ['/tmp/a.txt', '/tmp/b.txt']);
    });

    test('正文里的行内引用不动', () {
      const text = '看看 @/tmp/a.txt 这个文件';
      final region = fileReferenceRegion(text);
      expect(region.body, text);
      expect(region.paths, isEmpty);
    });

    test('代码块里的引用不动', () {
      const text = '示例：\n```\n@/tmp/a.txt\n```';
      final region = fileReferenceRegion(text);
      expect(region.paths, isEmpty);
    });

    test('相对路径不算', () {
      const text = '看看\n@lib/main.dart';
      expect(fileReferenceRegion(text).paths, isEmpty);
    });
  });

  test('fileReferenceName 取最后一段', () {
    expect(fileReferenceName('/Users/project/lib/app.dart'), 'app.dart');
    expect(fileReferenceName(r'C:\repo\app.dart'), 'app.dart');
  });
}
