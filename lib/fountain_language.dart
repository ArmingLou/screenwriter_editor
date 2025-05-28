import 'package:highlight/highlight.dart';

final Mode fountain = Mode(
  className: 'fountain',
  keywords: {
    'INT': Mode(className: 'scene-heading'),
    'EXT': Mode(className: 'scene-heading'),
    'INT./EXT': Mode(className: 'scene-heading'),
    'EST': Mode(className: 'scene-heading'),
    'INT/EXT': Mode(className: 'scene-heading'),
    'I/E': Mode(className: 'scene-heading'),
    'TO': Mode(className: 'transition'),
    'FADE IN': Mode(className: 'transition'),
    'FADE OUT': Mode(className: 'transition'),
    'CUT TO': Mode(className: 'transition'),
    'BACK TO': Mode(className: 'transition'),
    'THE END': Mode(className: 'transition')
  },
  contains: [
    Mode(
        className: 'scene-heading',
        begin: '^(INT|EXT|INT\\./EXT|EST|INT/EXT|I/E)\\b.*',
        relevance: 10),
    Mode(className: 'action', begin: '^[^\\n]+', end: '\n', relevance: 5),
    Mode(
        className: 'character',
        begin: '^\\s*@[^\\n]+',
        end: '\n',
        relevance: 7),
    Mode(
        className: 'dialogue',
        begin: '^\\s{2,}[^\\n]+',
        end: '\n',
        relevance: 5),
    Mode(
        className: 'parenthetical',
        begin: '^\\([^\\n]+\\)',
        end: '\n',
        relevance: 5),
    Mode(
        className: 'transition',
        begin: '^>\\s*[^\\n]+',
        end: '\n',
        relevance: 10),
    Mode(className: 'shot', begin: '^\\s*~[^\\n]+', end: '\n', relevance: 10),
  ],
);
