import 'package:screenwriter_editor/fountain_docx_exporter.dart';

void main() async {
  // 创建导出器实例
  final exporter = FountainDocxExporter();
  
  // 测试连接
  print('测试Rust连接: ${exporter.testRustConnection()}');
  
  // 示例Fountain剧本内容
  const fountainScript = '''
Title: 测试剧本
Author: 编剧姓名
Draft date: 2024年5月28日

FADE IN:

EXT. 公园 - 日

阳光明媚的早晨，公园里鸟语花香。

小明走进公园，手里拿着一本书。

小明
(自言自语)
今天天气真好，适合在公园里读书。

他找了一张长椅坐下，打开书本。

突然，一阵风吹过，书页翻动。

小明
(惊讶)
咦？这是什么？

书页上出现了一行神秘的文字。

小明
(读出声)
"当你读到这句话时，奇迹就会发生。"

话音刚落，公园里的花朵开始发光。

小明
(震惊)
这...这是怎么回事？

FADE OUT.
''';

  try {
    // 解析Fountain文本
    print('\n正在解析Fountain文本...');
    final parseResult = await exporter.parseFountainText(fountainScript);
    
    if (parseResult.success) {
      print('解析成功！');
      print('页数: ${parseResult.pageCount}');
      print('字符数: ${parseResult.characterCount}');
      print('单词数: ${parseResult.wordCount}');
    } else {
      print('解析失败: ${parseResult.message}');
      return;
    }
    
    // 创建中文配置
    final config = exporter.createChineseConfig();
    print('\n使用中文配置:');
    print('打印标题页: ${config.printTitlePage}');
    print('打印配置: ${config.printProfile}');
    
    // 导出DOCX文档
    print('\n正在导出DOCX文档...');
    final exportResult = await exporter.exportToDocx(
      fountainScript,
      '/tmp/test_screenplay.docx',
      config: config,
    );
    
    if (exportResult.success) {
      print('导出成功！');
      print('文件路径: ${exportResult.filePath}');
      print('消息: ${exportResult.message}');
    } else {
      print('导出失败: ${exportResult.message}');
    }
    
  } catch (e) {
    print('发生错误: $e');
  }
}
