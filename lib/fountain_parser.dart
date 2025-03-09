class FountainElement {
  final String type;
  final String text;
  final Range range;

  FountainElement(this.type, this.text, this.range);
}

class Range {
  final int start;
  final int length;

  Range(this.start, this.length);
}

class FountainParser {
  List<FountainElement> findCommond(String line, int offset) {
    final elements = <FountainElement>[];

    // 查找所有注释标记
    final commentPatterns = [
      ['/*', '*/'],
      ['[[', ']]']
    ];

    for (final pattern in commentPatterns) {
      final startPattern = pattern[0];
      final endPattern = pattern[1];

      int startIndex = 0;
      while (true) {
        // 查找开始标记
        var startPos = line.indexOf(startPattern, startIndex);

        // 查找结束标记
        var endPos = line.indexOf(endPattern, startIndex);

        if (startPos == -1 && endPos == -1) {
          break;
        }

        if (startPos == -1 && endPos > -1) {
          // 没有开头
          startPos = startIndex;
        }

        if (startPos > -1 && endPos == -1) {
          // 没有闭合
          endPos = line.length - endPattern.length;
        }

        // 计算注释范围
        final commentLength = endPos + endPattern.length - startPos;
        final commentText =
            line.substring(startPos, endPos + endPattern.length);

        // 添加注释元素
        elements.add(FountainElement(
          'comment',
          commentText,
          Range(offset + startPos, commentLength),
        ));

        // 移动搜索位置
        startIndex = endPos + endPattern.length;
      }
    }

    // // 处理未闭合的注释
    // for (final pattern in commentPatterns) {
    //   final startPattern = pattern[0];
    //   final startPos = line.indexOf(startPattern);
    //   if (startPos != -1 && line.indexOf(pattern[1], startPos + startPattern.length) == -1) {
    //     // 只有开始标记没有结束标记
    //     final commentLength = line.length - startPos;
    //     final commentText = line.substring(startPos);

    //     elements.add(FountainElement(
    //       'comment',
    //       // 'unclosed_comment',
    //       commentText,
    //       Range(offset + startPos, commentLength),
    //     ));
    //   }
    // }

    return elements;
  }

  List<FountainElement> parse(String text) {
    final elements = <FountainElement>[];
    final lines = text.split('\n');
    int offset = 0;

    var dialogueStarted = false;
    var lastLineWasEmpty = true;
    for (var line in lines) {
      final trimmedLine = line.trim();
      final length = line.length;

      // 场景标题
      if (lastLineWasEmpty &&
          (trimmedLine.startsWith('INT.') ||
              trimmedLine.startsWith('EXT.') ||
              trimmedLine.startsWith('.'))) {
        elements.add(FountainElement(
          'scene_heading',
          line,
          Range(offset, length),
        ));
      }
      // 角色
      else if (lastLineWasEmpty &&
          (trimmedLine.startsWith('@') ||
              (trimmedLine.isNotEmpty &&
                  trimmedLine == trimmedLine.toUpperCase() &&
                  trimmedLine[0].toUpperCase() !=
                      trimmedLine[0].toLowerCase()))) {
        dialogueStarted = true;
        elements.add(FountainElement(
          'character',
          line,
          Range(offset, length),
        ));
      } else if (dialogueStarted) {
        if (trimmedLine.isNotEmpty || (trimmedLine.isEmpty && length > 1)) {
          // 对话
          elements.add(FountainElement(
            'dialogue',
            line,
            Range(offset, length),
          ));
        } else {
          dialogueStarted = false;
        }
      } else if (trimmedLine.startsWith('>') && trimmedLine.endsWith('<')) {
        elements.add(FountainElement(
          'center',
          line,
          Range(offset, length),
        ));
      } else if (trimmedLine.startsWith('>')) {
        elements.add(FountainElement(
          'transition',
          line,
          Range(offset, length),
        ));
      }
      // 动作
      else if (trimmedLine.startsWith('!')) {
        dialogueStarted = false;
        elements.add(FountainElement(
          'action',
          line,
          Range(offset, length),
        ));
      } else if (trimmedLine.startsWith('#')) {
        elements.add(FountainElement(
          'sections',
          line,
          Range(offset, length),
        ));
      } else if (trimmedLine.startsWith('===')) {
        elements.add(FountainElement(
          'page_breaks',
          line,
          Range(offset, length),
        ));
      } else if (trimmedLine.startsWith('=')) {
        elements.add(FountainElement(
          'synopses',
          line,
          Range(offset, length),
        ));
      } else if (trimmedLine.startsWith('~')) {
        elements.add(FountainElement(
          'lyrics',
          line,
          Range(offset, length),
        ));
      } else if (trimmedLine.isNotEmpty) {
        elements.add(FountainElement(
          'action',
          line,
          Range(offset, length),
        ));
      }

      // 所有 元素，都要处理注解。
      var cm = findCommond(line, offset);
      if (cm.isNotEmpty) {
        elements.addAll(cm);
      }

      offset += length + 1; // +1 for newline

      if ((trimmedLine.isEmpty && length < 2) ||
          (lastLineWasEmpty && trimmedLine.isEmpty)) {
        lastLineWasEmpty = true;
      } else {
        lastLineWasEmpty = false;
      }
    }

    return elements;
  }
}
