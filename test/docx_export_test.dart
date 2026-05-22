import 'package:flutter_test/flutter_test.dart';
import 'package:screenwriter_editor/bridge_generated.dart/api/docx_export.dart';
import 'package:screenwriter_editor/bridge_generated.dart/frb_generated.dart';
import 'dart:io';

void main() {
  setUpAll(() async {
    // 初始化Rust库
    await RustLib.init();
  });

  group('DOCX Export Tests', () {

    test('测试连接功能', () async {
      final result = await testConnection();
      expect(result, equals("Rust bridge connection successful!"));
    });

    test('测试解析Fountain文本', () async {
      const fountainText = '''
Title: 测试剧本
Author: 测试作者

FADE IN:

EXT. 公园 - 日

一个美丽的公园场景。

小明
你好，世界！

小红
(微笑)
你好！

FADE OUT.
''';

      final result = await parseFountainTextWithStats(text: fountainText);

      expect(result.success, isTrue);
      expect(result.message, equals('Fountain文本解析成功'));
      expect(result.pageCount, greaterThanOrEqualTo(0));
      expect(result.characterCount, greaterThan(0));
      expect(result.wordCount, greaterThan(0));
    });

    test('测试导出DOCX - 空文本', () async {
      final result = await exportToDocx(text: '', outputPath: '/tmp/test.docx');

      expect(result.success, isFalse);
      expect(result.message, contains('不能为空'));
    });

    test('测试导出DOCX - 空路径', () async {
      const fountainText = 'EXT. 测试场景 - 日';
      final result = await exportToDocx(text: fountainText, outputPath: '');

      expect(result.success, isFalse);
      expect(result.message, contains('不能为空'));
    });

    test('测试导出DOCX - 正常情况', () async {
      const fountainText = '''
Title: 测试剧本

EXT. 公园 - 日

小明走进公园。

小明
今天天气真好！
''';

      final tempDir = Directory.systemTemp;
      final outputPath = '${tempDir.path}/test_screenplay.docx';

      final config = await createChineseConfig();
      final result = await exportToDocx(
        text: fountainText,
        outputPath: outputPath,
        config: config,
      );

      expect(result.success, isTrue);
      expect(result.message, contains('成功'));
      expect(result.filePath, equals(outputPath));

      // 检查文件是否真的被创建
      final file = File(outputPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));

      // 清理测试文件
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    test('测试自定义配置', () async {
      final chineseConfig = await createChineseConfig();
      expect(chineseConfig.printTitlePage, isTrue);
      expect(chineseConfig.printProfile, equals("中文a4"));

      final englishConfig = await createEnglishConfig();
      expect(englishConfig.printTitlePage, isTrue);
      expect(englishConfig.printProfile, equals("英文letter"));
      expect(englishConfig.doubleSpaceBetweenScenes, isTrue);
    });

    test('测试Base64导出', () async {
      const fountainText = '''
Title: 测试剧本

EXT. 街道 - 白天

繁忙的街道上，人来人往。

小红
今天天气真好！
''';

      final result = await exportToDocxBase64(text: fountainText);
      expect(result.success, isTrue);
      expect(result.message, contains('成功'));
    });
  });
}
