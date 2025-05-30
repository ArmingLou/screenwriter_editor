import 'package:screenwriter_editor/fountain_constants.dart';
import 'package:screenwriter_editor/statis.dart';

class ParserOutput {
  final List<FountainElement> elements;
  final Statis? statis;
  final double charsPerMinu; //按每分钟多少个字预估， （全文，不区分对白）。
  final double dialCharsPerMinu; //按每分钟多少个字预估, （只针对 对白）。
  final bool fisrtScencStarted;
  final int startChars; //第一个场景之前的字数，作用是预估时间需要减去。包含注解的字数。
  final bool canceled;
  final Set<String> dupSceneHeadings; // 包含 dupSceneNum 的场景头文本，去掉注释后的
  ParserOutput(
      this.elements,
      this.statis,
      this.charsPerMinu,
      this.dialCharsPerMinu,
      this.fisrtScencStarted,
      this.startChars,
      this.canceled,
      [this.dupSceneHeadings = const {}]);
}

class FountainElement {
  final String type;
  final String text;
  final String featureText; //方便实现某些功能的文本，每种type不一样。预留。
  final Range range;
  bool formated = false;

  FountainElement(this.type, this.text, this.featureText, this.range);
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

typedef CallbackParser = void Function(ParserOutput output);

class FountainParser {
  bool parseing = false;
  bool cancel = false;
  ParserOutput? result;
  int isEnglish = -1;

  List<CallbackParser> callbacks = [];

  Set<String> allSceneNum = {};
  Map<String, String> dupSceneNum = {};

  // 查找所有注释标记
  final commentPatterns = [
    ['[[', ']]'],
    ['/*', '*/'],
  ];
  int commentStarted = -1; // 0: [[]] ；1: /* */

  var statis = Statis.empty();
  var preCharater = '';

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
          '', //注解不返回text内容。暂时不需要，看以后情况。
          Range(offset + idxStart, line.length - idxStart),
        ));
      } else {
        elements.add(FountainElement(
          type,
          '', //注解不返回text内容。暂时不需要，看以后情况。
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

  String trimCharacterName(String character) {
    var t =
        character.replaceAll(RegExp(r'^[ \t]*(@)?', unicode: true), '').trim();
    t = t
        .replaceAll(
            RegExp(r'[ \t]*(\(.*\)|（.*）)[ \t]*([ \t]*\^$)?', unicode: true), '')
        .trim();
    t = t.replaceAll(RegExp(r'[ \t]*\^$', unicode: true), '').trim();
    return t;
  }

  _processCharater(bool doStatis, String text) {
    if (doStatis) {
      final match = FountainConstants.regex['character']!.firstMatch(text);
      if (match != null) {
        var name = trimCharacterName(text);
        statis.addCharacterChars(
            name, 0); // 如果未开始第一额场景， 统计图标要将 0 的过滤； 但是 辅助自动输入需要可以 下拉选择。
        preCharater = name;
      }
    }
  }

  // 返回值表示该场景头是否包含 dupSceneNum
  bool _processScene(bool doStatis, String sceneHeading) {
    bool containsDupSceneNum = false;
    if (doStatis) {
      final sceneMatch =
          FountainConstants.regex['scene_heading']!.firstMatch(sceneHeading);

      if (sceneMatch == null || sceneMatch.groupCount < 2) {
        return containsDupSceneNum;
      }

      // 处理场景号
      var nb = (allSceneNum.length + 1).toString();
      var sceneNumber = sceneMatch.group(3) ?? '';
      if (sceneNumber.isNotEmpty) {
        final sceneNumberMatch =
            FountainConstants.regex['scene_number']!.firstMatch(sceneNumber);
        if (sceneNumberMatch != null && sceneNumberMatch.groupCount > 1) {
          var nb2 = sceneNumberMatch.group(2) ?? '';
          if (nb2.trim().isNotEmpty) {
            nb = nb2;
          }
        }
        if (sceneNumberMatch != null && sceneNumberMatch.groupCount > 0) {
          var nb2 = sceneNumberMatch.group(1) ?? '';
          if (nb2.trim().isNotEmpty) {
            if (dupSceneNum.containsKey(nb2.trim())) {
              nb = dupSceneNum[nb2.trim()]!;
            } else {
              dupSceneNum[nb2.trim()] = nb;
              containsDupSceneNum = true;
            }
          }
        }
      }
      if (allSceneNum.contains(nb)) {
        // 重复 场景号，免统计
        return containsDupSceneNum;
      } else {
        allSceneNum.add(nb);
      }

      if (isEnglish < 0) {
        // 只处理一次，只看第一个场景头，是否为英文，就确定显示中文还是英文统计。
        if (sceneHeading.trim().toLowerCase().startsWith('i') ||
            sceneHeading.trim().toLowerCase().startsWith('e')) {
          isEnglish = 1; //
        } else {
          isEnglish = 0;
        }
      }

      // 处理场景类型和内景/外景标记
      var locationText = sceneMatch.group(2) ?? '';
      var isInterior = sceneHeading.toLowerCase().contains('int');
      var isExterior = sceneHeading.toLowerCase().contains('ext');

      // 处理中文场景标记
      if (locationText.startsWith('(内景)') || locationText.startsWith('（内景）')) {
        locationText = locationText.substring(4).trim();
        isInterior = true;
      } else if (locationText.startsWith('(外景)') ||
          locationText.startsWith('（外景）')) {
        locationText = locationText.substring(4).trim();
        isExterior = true;
      } else if (locationText.startsWith('(内外景)') ||
          locationText.startsWith('（内外景）')) {
        locationText = locationText.substring(5).trim();
        isInterior = true;
        isExterior = true;
      }

      // 分割地点和时间
      final timeSplit = RegExp(r'[-–—−]').firstMatch(locationText);
      var locationPart = timeSplit != null
          ? locationText.substring(0, timeSplit.start).trim()
          : locationText.trim();
      final timePart = timeSplit != null
          ? locationText.substring(timeSplit.end).trim().toUpperCase()
          : '';

      // // 分割多个地点名称并生成Location列表
      // var names = locationPart
      //     .split('/')
      //     .map((name) => name.trim())
      //     .where((name) => name.isNotEmpty)
      //     .toList();

      var names = [locationPart.trim()];

      // 遍历names
      for (var name in names) {
        var tp = timePart.isNotEmpty
            ? timePart
            : isEnglish == 1
                ? 'Unclear'
                : '不确定';
        statis.addTimesScenes(tp, 1);
        statis.addLocationScenes(name, 1);

        if (isExterior && isInterior) {
          if (names.length > 1) {
            statis.addIntextsScenes(isEnglish == 1 ? 'Unclear' : '不确定', 1);
            statis.addLocationTimeScenes(
                name, isEnglish == 1 ? '-' : '-', tp, 1);
          } else {
            statis.addIntextsScenes(isEnglish == 1 ? 'INT/EXT.' : '内外景', 1);
            statis.addLocationTimeScenes(
                name, isEnglish == 1 ? 'I/E' : '内外', tp, 1);
          }
        } else if (isExterior) {
          statis.addIntextsScenes(isEnglish == 1 ? 'EXT.' : '外景', 1);
          statis.addLocationTimeScenes(
              name, isEnglish == 1 ? 'E' : '外', tp, 1);
        } else if (isInterior) {
          statis.addIntextsScenes(isEnglish == 1 ? 'INT.' : '内景', 1);
          statis.addLocationTimeScenes(
              name, isEnglish == 1 ? 'I' : '内', tp, 1);
        } else {
          statis.addIntextsScenes(isEnglish == 1 ? 'Unclear' : '不确定', 1);
          statis.addLocationTimeScenes(
              name, isEnglish == 1 ? '-' : '-', tp, 1);
        }
      }
    }
    return containsDupSceneNum;
  }

  ParserOutput parse(bool doStatis, String text) {
    if (parseing || cancel) {
      result = ParserOutput([], null, 0, 0, false, 0, true);
      return result!;
    }
    parseing = true;

    commentStarted = -1;
    statis = Statis.empty();

    final elements = <FountainElement>[];
    final lines = text.split('\n');
    int offset = 0;

    var dialogueStarted = false;
    var parentheticalStarted = "";
    var lastLineWasEmpty = true;

    var fisrtScencStarted = false;
    double charsPerMinu = 243.22; //按每分钟多少个字预估， （全文，不区分对白）。
    double dialCharsPerMinu = 171; //按每分钟多少个字预估, （只针对 对白）。
    int startChars = 0; //第一个场景之前的字数，作用是预估时间需要减去。

    allSceneNum.clear();
    dupSceneNum.clear();

    // 用于收集包含 dupSceneNum 的场景头文本
    final Set<String> dupSceneHeadings = {};

    for (var line in lines) {
      if (cancel) {
        result = ParserOutput([], null, 0, 0, false, 0, true);
        return result!;
      }

      final trimmedLine = line.trim();
      final length = line.length;
      var statisDial = false; //是否需要统计对话字数，需要在减去评论字数之后
      bool containsDupSceneNum = false;

      if (commentStarted < 0) {
        //注解最优先

        if (dialogueStarted) {
          //dialogue 永远最优先
          if (trimmedLine.isEmpty && length < 2) {
            dialogueStarted = false;
            parentheticalStarted = "";
            preCharater = '';
          } else {
            if (parentheticalStarted.isNotEmpty) {
              elements.add(FountainElement(
                'parenthetical',
                line,
                '',
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
                  '',
                  Range(offset, length),
                ));
              } else if (trimmedLine.startsWith('（')) {
                if (!trimmedLine.endsWith('）')) {
                  parentheticalStarted = '）';
                }
                elements.add(FountainElement(
                  'parenthetical',
                  line,
                  '',
                  Range(offset, length),
                ));
              } else {
                // 对话
                elements.add(FountainElement(
                  'dialogue',
                  line,
                  '',
                  Range(offset, length),
                ));
                if (doStatis && fisrtScencStarted) {
                  // 统计对话字数
                  statisDial = true;
                }
              }
            }
          }
        }
        // 以下都是 非dialogueStarted 情况
        // 场景标题
        else if (lastLineWasEmpty &&
            FountainConstants.regex['scene_heading']!.hasMatch(line)) {
          elements.add(FountainElement(
            'scene_heading',
            line,
            '',
            Range(offset, length),
          ));
          containsDupSceneNum = _processScene(doStatis, line);
          fisrtScencStarted = true;
        } else if (FountainConstants.regex['centered']!.hasMatch(line)) {
          elements.add(FountainElement(
            'center',
            line,
            '',
            Range(offset, length),
          ));
        } else if (lastLineWasEmpty &&
            FountainConstants.regex['transition']!.hasMatch(line)) {
          var group2 = FountainConstants.regex['transition']!.firstMatch(line);
          var group2Text = group2!.groupCount > 1 ? group2.group(2) : "";
          elements.add(FountainElement(
            'transition',
            line,
            group2Text ?? '',
            Range(offset, length),
          ));
        }
        // 动作
        else if (FountainConstants.blockRegex['action_force']!.hasMatch(line)) {
          dialogueStarted = false;
          parentheticalStarted = "";
          preCharater = '';
          elements.add(FountainElement(
            'action',
            line,
            '',
            Range(offset, length),
          ));
        } else if (FountainConstants.regex['section']!.hasMatch(line)) {
          elements.add(FountainElement(
            'sections',
            line,
            '',
            Range(offset, length),
          ));
        } else if (FountainConstants.regex['page_break']!.hasMatch(line)) {
          elements.add(FountainElement(
            'page_breaks',
            line,
            '',
            Range(offset, length),
          ));
        } else if (FountainConstants.regex['synopsis']!.hasMatch(line)) {
          elements.add(FountainElement(
            'synopses',
            line,
            '',
            Range(offset, length),
          ));
        } else if (FountainConstants.regex['lyric']!.hasMatch(line)) {
          elements.add(FountainElement(
            'lyrics',
            line,
            '',
            Range(offset, length),
          ));
        } else if (lastLineWasEmpty &&
            FountainConstants.regex['character']!.hasMatch(line)) {
          dialogueStarted = true;
          elements.add(FountainElement(
            'character',
            line,
            '',
            Range(offset, length),
          ));
          _processCharater(doStatis, line);
        } else if (trimmedLine.isNotEmpty) {
          elements.add(FountainElement(
            'action',
            line,
            '',
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
                '',
                Range(offset, length),
              ));
            } else {
              elements.add(FountainElement(
                'dialogue',
                line,
                '',
                Range(offset, length),
              ));
              if (doStatis && fisrtScencStarted) {
                // 统计对话字数
                statisDial = true;
              }
            }
          } else {
            elements.add(FountainElement(
              'action',
              line,
              '',
              Range(offset, length),
            ));
          }
        }
      }

      // 所有 元素，都要处理注解。需放到最后处理，包含判断空行逻辑。
      var cm = findCommond(line, offset);
      var textAfterComent = line;
      if (cm.elements.isNotEmpty) {
        elements.addAll(cm.elements);
        textAfterComent = cm.left;
        if (cm.left.trim().isEmpty) {
          // 继承之前的 lastLineWasEmpty 值，不处理
        } else {
          lastLineWasEmpty = false;
        }
      } else {
        // 本行没有任何注解
        lastLineWasEmpty = trimmedLine.isEmpty;
      }

      if (statisDial) {
        statis.addCharacterChars(preCharater, textAfterComent.trim().length);
      }
      if (containsDupSceneNum) {
        // 去掉注释后的场景头文本
        dupSceneHeadings.add(textAfterComent.trim());
      }

      if (!fisrtScencStarted) {
        startChars += length + 1; // 加上被split删去的换行符
        // 视为标题页处理
        // 简单地从metadata中找到 每分钟多少个字的配置。前提是这个json配置的字段，格式上要单独一行。
        int i = textAfterComent.indexOf('"chars_per_minu"');
        if (i > 0) {
          String s = textAfterComent.substring(i + 16);
          int j = s.indexOf(',');
          String v = '';
          if (j > 1) {
            v = s.substring(s.indexOf(':') + 1, j);
            charsPerMinu = double.parse(v.trim());
          } else if (j == -1) {
            v = s.substring(s.indexOf(':') + 1);
            charsPerMinu = double.parse(v.trim());
          }
        }
        // 简单地从metadata中找到 对白每分钟多少个字的配置。前提是这个json配置的字段，格式上要单独一行。
        int ii = textAfterComent.indexOf('"dial_chars_per_minu"');
        if (ii > 0) {
          String s = textAfterComent.substring(ii + 21);
          int jj = s.indexOf(',');
          String v = '';
          if (jj > 1) {
            v = s.substring(s.indexOf(':') + 1, jj);
            dialCharsPerMinu = double.parse(v.trim());
          } else if (jj == -1) {
            v = s.substring(s.indexOf(':') + 1);
            dialCharsPerMinu = double.parse(v.trim());
          }
        }
      }

      offset += length + 1; // +1 for newline
    }

    result = ParserOutput(elements, statis, charsPerMinu, dialCharsPerMinu,
        fisrtScencStarted, startChars, false, dupSceneHeadings);

    callAllCallbacks(result!);

    return result!;
  }

  void removeAllCallbacks() {
    callbacks.clear();
  }

  void addCallback(CallbackParser callback) {
    callbacks.add(callback);
  }

  void addAllCallbacks(List<CallbackParser> callbacks) {
    this.callbacks.addAll(callbacks);
  }

  void callAllCallbacks(ParserOutput result) {
    for (var callback in callbacks) {
      callback(result);
    }
  }
}
