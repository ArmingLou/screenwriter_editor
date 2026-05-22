# Fountain DOCX 导出功能

这个项目现在支持将Fountain格式的剧本导出为DOCX文档。该功能使用Rust后端处理，通过Flutter Rust Bridge与Flutter前端集成。

## 功能特性

- ✅ **Fountain文本解析**: 解析标准Fountain格式的剧本文本
- ✅ **DOCX文档导出**: 将解析后的剧本导出为DOCX格式
- ✅ **多种配置选项**: 支持中文、英文等不同的导出配置
- ✅ **统计信息**: 提供页数、字符数、单词数等统计信息
- ✅ **错误处理**: 完善的错误处理和用户反馈

## 快速开始

### 1. 基本使用

```dart
import 'package:screenwriter_editor/fountain_docx_exporter.dart';

// 创建导出器实例
final exporter = FountainDocxExporter();

// 测试连接
String connectionResult = exporter.testRustConnection();
print(connectionResult);
```

### 2. 解析Fountain文本

```dart
const fountainText = '''
Title: 我的剧本
Author: 编剧姓名

FADE IN:

EXT. 公园 - 日

小明走进公园。

小明
今天天气真好！

FADE OUT.
''';

// 解析文本
final parseResult = await exporter.parseFountainText(fountainText);

if (parseResult.success) {
  print('页数: ${parseResult.pageCount}');
  print('字符数: ${parseResult.characterCount}');
  print('单词数: ${parseResult.wordCount}');
}
```

### 3. 导出DOCX文档

```dart
// 创建配置
final config = exporter.createChineseConfig(); // 中文配置
// 或者
// final config = exporter.createEnglishConfig(); // 英文配置
// final config = exporter.createDefaultConfig(); // 默认配置

// 导出文档
final exportResult = await exporter.exportToDocx(
  fountainText,
  '/path/to/output.docx',
  config: config,
);

if (exportResult.success) {
  print('导出成功: ${exportResult.filePath}');
} else {
  print('导出失败: ${exportResult.message}');
}
```

## 配置选项

### SimpleConf 配置类

```dart
class SimpleConf {
  final bool printTitlePage;        // 是否打印标题页
  final String printProfile;        // 打印配置文件
  final bool doubleSpaceBetweenScenes; // 场景间双倍行距
  final bool printSections;         // 是否打印章节
  final bool printSynopsis;         // 是否打印概要
  final bool printActions;          // 是否打印动作描述
  final bool printHeaders;          // 是否打印页眉
  final bool printDialogues;        // 是否打印对话
  final bool numberSections;        // 是否给章节编号
  final bool useDualDialogue;       // 是否使用双栏对话
  final bool printNotes;            // 是否打印注释
  final String printHeader;         // 页眉内容
  final String printFooter;         // 页脚内容
  final String printWatermark;      // 水印内容
  final String scenesNumbers;       // 场景编号方式
  final bool eachSceneOnNewPage;    // 每个场景新页
}
```

### 预设配置

- `createDefaultConfig()`: 默认配置
- `createChineseConfig()`: 中文配置，适合中文剧本
- `createEnglishConfig()`: 英文配置，适合英文剧本

## 返回类型

### ParseResult - 解析结果

```dart
class ParseResult {
  final bool success;           // 是否成功
  final String message;         // 结果消息
  final int pageCount;          // 页数
  final int characterCount;     // 字符数
  final int wordCount;          // 单词数
}
```

### ExportResult - 导出结果

```dart
class ExportResult {
  final bool success;           // 是否成功
  final String message;         // 结果消息
  final String? filePath;       // 输出文件路径
}
```

## 运行示例

项目包含一个完整的示例，展示如何使用所有功能：

```bash
dart run example/docx_export_example.dart
```

## 测试

运行测试以验证功能：

```bash
flutter test test/docx_export_test.dart
```

## 技术架构

- **前端**: Flutter/Dart
- **后端**: Rust
- **桥接**: Flutter Rust Bridge 2.10.0
- **构建系统**: Cargo (Rust) + Flutter

## 构建说明

1. 确保安装了Rust工具链
2. 构建Rust库：
   ```bash
   cd rust
   cargo build --release
   ```
3. 复制动态库到正确位置：
   ```bash
   cp rust/target/release/librust_lib_screenwriter_editor.dylib rust_lib_screenwriter_editor.framework/rust_lib_screenwriter_editor
   ```

## 注意事项

- 目前导出的是简化版本的文本文件，未来将支持真正的DOCX格式
- 需要先构建Rust库才能运行测试和示例
- 支持macOS平台，其他平台需要相应的动态库文件

## 未来计划

- [ ] 支持真正的DOCX格式导出
- [ ] 添加更多导出选项和样式
- [ ] 支持更多平台（Windows、Linux）
- [ ] 添加更多Fountain语法支持
- [ ] 性能优化和错误处理改进
