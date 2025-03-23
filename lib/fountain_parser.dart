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

class CommentResult {
  final List<FountainElement> elements;
  final String left; //注解之后，剩余的非注解字符串。

  CommentResult(this.elements, this.left);
}

class FountainParser {
  // 查找所有注释标记
  final commentPatterns = [
    ['[[', ']]'],
    ['/*', '*/'],
  ];
  int commentStarted = -1; // 0: [[]] ；1: /* */

  CommentResult findCommond(String line, int offset) {
    final elements = <FountainElement>[];
    var left = '';

    var idxStart = -1;
    if (commentStarted < 0) {
      for (var i = 0; i < commentPatterns.length; i++) {
        var idxT = line.indexOf(commentPatterns[i][0]);
        if (idxT >= 0) {
          if (idxStart < 0) {
            idxStart = idxT;
            commentStarted = i;
          } else {
            if (idxT < idxStart) {
              idxStart = idxT;
              commentStarted = i;
            }
          }
        }
      }
    }

    if (commentStarted >= 0) {
      if (idxStart < 0) {
        idxStart = 0;
      }
      if (idxStart > 0) {
        left += line.substring(0, idxStart);
      }

      //找到最早的 注解开口， 找下一个注解闭口
      String endTag = commentPatterns[commentStarted][1];
      String type = endTag == ']]' ? 'note' : 'comment';
      var idxEnd = line.indexOf(endTag, idxStart);
      if (idxEnd < 0) {
        // 非闭合注解行，剩下的都是注解
        // 添加注释元素
        elements.add(FountainElement(
          type,
          '', //注解不返回text内容。暂时不需要，看以后情况。
          Range(offset + idxStart, line.length - idxStart),
        ));
      } else {
        elements.add(FountainElement(
          type,
          '', //注解不返回text内容。暂时不需要，看以后情况。
          Range(offset + idxStart, idxEnd - idxStart + endTag.length),
        ));

        // 递归，继续找
        commentStarted = -1;
        final ls = findCommond(line.substring(idxEnd + endTag.length),
            offset + idxEnd + endTag.length);
        if (ls.elements.isNotEmpty) {
          elements.addAll(ls.elements);
        }
        left += ls.left;
      }
    } else {
      // 没有任何注释
      left = line;
    }
    return CommentResult(elements, left);
  }

  List<FountainElement> parse(String text) {
    commentStarted = -1;

    final elements = <FountainElement>[];
    final lines = text.split('\n');
    int offset = 0;

    var dialogueStarted = false;
    var parentheticalStarted = "";
    var lastLineWasEmpty = true;

    for (var line in lines) {
      final trimmedLine = line.trim();
      final length = line.length;

      if (commentStarted < 0) {
        //注解最优先

        if (!dialogueStarted &&
            lastLineWasEmpty &&
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
          //dialogue 永远最优先
          if (trimmedLine.isEmpty && length < 2) {
            dialogueStarted = false;
            parentheticalStarted = "";
          } else {
            if (parentheticalStarted.isNotEmpty) {
              elements.add(FountainElement(
                'parenthetical',
                line,
                Range(offset, length),
              ));
              if (trimmedLine.endsWith(parentheticalStarted)) {
                parentheticalStarted = "";
              }
            } else {
              if (trimmedLine.startsWith('(')) {
                if (!trimmedLine.endsWith(')')) {
                  parentheticalStarted = ')';
                }
                elements.add(FountainElement(
                  'parenthetical',
                  line,
                  Range(offset, length),
                ));
              } else if (trimmedLine.startsWith('（')) {
                if (!trimmedLine.endsWith('）')) {
                  parentheticalStarted = '）';
                }
                elements.add(FountainElement(
                  'parenthetical',
                  line,
                  Range(offset, length),
                ));
              } else {
                // 对话
                elements.add(FountainElement(
                  'dialogue',
                  line,
                  Range(offset, length),
                ));
              }
            }
          }
        }
        // 以下都是 非dialogueStarted 情况
        // 场景标题
        else if (lastLineWasEmpty &&
            (trimmedLine.startsWith('.') ||
                trimmedLine.toUpperCase().startsWith('INT.') ||
                trimmedLine.toUpperCase().startsWith('EXT.') ||
                trimmedLine.toUpperCase().startsWith('EST.') ||
                trimmedLine.toUpperCase().startsWith('INT ') ||
                trimmedLine.toUpperCase().startsWith('EXT ') ||
                trimmedLine.toUpperCase().startsWith('EST ') ||
                trimmedLine.toUpperCase().startsWith('INT./EXT.') ||
                trimmedLine.toUpperCase().startsWith('INT./EXT ') ||
                trimmedLine.toUpperCase().startsWith('INT/EXT.') ||
                trimmedLine.toUpperCase().startsWith('INT/EXT ') ||
                trimmedLine.toUpperCase().startsWith('I/E.') ||
                trimmedLine.toUpperCase().startsWith('I/E '))) {
          elements.add(FountainElement(
            'scene_heading',
            line,
            Range(offset, length),
          ));
        } else if (trimmedLine.startsWith('>') && trimmedLine.endsWith('<')) {
          elements.add(FountainElement(
            'center',
            line,
            Range(offset, length),
          ));
        } else if (lastLineWasEmpty &&
            (trimmedLine.startsWith('>') ||
                (trimmedLine == trimmedLine.toUpperCase() &&
                    trimmedLine.endsWith("TO:")))) {
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
      } else {
        // 注释闭合后，后段需要延续的样式
        if (trimmedLine.isNotEmpty) {
          if (dialogueStarted) {
            if (parentheticalStarted.isNotEmpty) {
              elements.add(FountainElement(
                'parenthetical',
                line,
                Range(offset, length),
              ));
            } else {
              elements.add(FountainElement(
                'dialogue',
                line,
                Range(offset, length),
              ));
            }
          } else {
            elements.add(FountainElement(
              'action',
              line,
              Range(offset, length),
            ));
          }
        }
      }

      // 所有 元素，都要处理注解。需放到最后处理，包含判断空行逻辑。
      var cm = findCommond(line, offset);
      if (cm.elements.isNotEmpty) {
        elements.addAll(cm.elements);
        if (cm.left.trim().isEmpty) {
          // 继承之前的 lastLineWasEmpty 值，不处理
        } else {
          lastLineWasEmpty = false;
        }
      } else {
        // 本行没有任何注解
        lastLineWasEmpty = trimmedLine.isEmpty;
      }

      offset += length + 1; // +1 for newline
    }

    return elements;
  }
}
