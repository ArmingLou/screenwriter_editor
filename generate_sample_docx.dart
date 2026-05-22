import 'dart:io';
import 'package:screenwriter_editor/bridge_generated.dart/api/docx_export.dart';
import 'package:screenwriter_editor/bridge_generated.dart/frb_generated.dart';

void main() async {
  // 初始化Rust库
  await RustLib.init();
  
  // 测试Fountain文本
  const fountainText = '''
Title: 黑色爱情诗
Author: 测试作者
Credit: 编剧
Source: 原创剧本

FADE IN:

INT. 咖啡厅 - 夜晚

昏暗的灯光下，一个男人独自坐在角落。雨水敲打着窗户，发出单调的节拍。

阿明
(自言自语)
爱情就像这杯咖啡，苦涩中带着一丝甜蜜。

他抬起头，看向窗外的雨夜。街上的霓虹灯在雨水中模糊成一片色彩。

阿明 (CONT'D)
但最终，都会变凉。

门铃响起，一个女人走进咖啡厅。她摘下雨衣的帽子，露出湿润的长发。

小雨
(对服务员)
一杯热巧克力，谢谢。

她环顾四周，目光与阿明相遇。时间仿佛停止了一秒。

阿明
(轻声)
有些人的出现，就像雨后的阳光。

小雨走向阿明的桌子。

小雨
这里可以坐吗？

阿明
当然。

她坐下，两人之间的空气中弥漫着一种微妙的张力。

小雨
你经常一个人来这里吗？

阿明
只有在想要逃避现实的时候。

小雨
(微笑)
那今晚你在逃避什么？

阿明
(停顿)
逃避一个没有你的世界。

雨声渐小，但两人的对话才刚刚开始。

FADE OUT.

THE END
''';

  try {
    // 创建中文配置
    final config = await createChineseConfig();
    print('配置创建成功: ${config.printProfile}');
    
    // 设置输出路径到当前目录
    final currentDir = Directory.current;
    final outputPath = '${currentDir.path}/黑色爱情诗.docx';
    
    print('开始导出DOCX文件到: $outputPath');
    
    // 导出DOCX文件
    final result = await exportToDocx(
      text: fountainText,
      outputPath: outputPath,
      config: config,
    );
    
    if (result.success) {
      print('✅ DOCX导出成功！');
      print('📄 文件路径: ${result.filePath}');
      
      // 检查文件是否存在
      final file = File(outputPath);
      if (file.existsSync()) {
        final fileSize = file.lengthSync();
        print('📊 文件大小: ${(fileSize / 1024).toStringAsFixed(2)} KB');
        print('🎉 您可以在以下位置找到导出的DOCX文件:');
        print('   $outputPath');
      } else {
        print('❌ 文件未找到');
      }
    } else {
      print('❌ 导出失败: ${result.message}');
    }
    
    // 测试解析功能
    print('\n📝 测试解析功能...');
    final parseResult = await parseFountainTextWithStats(text: fountainText);
    if (parseResult.success) {
      print('✅ 解析成功');
      print('📄 页数: ${parseResult.pageCount}');
      print('🔤 字符数: ${parseResult.characterCount}');
      print('📝 单词数: ${parseResult.wordCount}');
    } else {
      print('❌ 解析失败: ${parseResult.message}');
    }
    
  } catch (e) {
    print('❌ 发生错误: $e');
  }
}
