import 'package:flutter/material.dart';
import 'package:screenwriter_editor/statis.dart';
// import 'package:fl_chart/fl_chart.dart';
import 'package:fast_charts/fast_charts.dart';

class StatsPage extends StatelessWidget {
  final Statis statis;
  final double dialCharsPerMinu;

  const StatsPage(
      {super.key, required this.statis, this.dialCharsPerMinu = 171});

  Widget _buildChart(Map<String, int> data, String title, bool charsTime,
      bool colorName, BuildContext context) {
    // final number = NumberFormat.compact(locale: 'ru');
    // 过滤 value == 0
    data.removeWhere((key, value) => value == 0);
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    //sorted map to _data
    final data0 = sorted.map((entry) {
      return Series(
        data: {entry.key: entry.value},
        colorAccessor: (domain, value) =>
            colorName ? getColor(entry.key) : Colors.blue,
        measureAccessor: (value) => value.toDouble(),
        labelAccessor: (domain, value, percent) {
          var lb = value.toString();
          if (charsTime && value > 0) {
            double currMinu = value / dialCharsPerMinu;
            if (currMinu > 1) {
              int currM = currMinu.toInt();
              lb = "$lb [$currM’]";
            } else {
              int currSeconds = (currMinu * 60).toInt();
              int currS = currSeconds % 60;
              lb = "$lb [$currS”]";
            }
          }
          return ChartLabel(
            lb,
            style: TextStyle(fontSize: 10),
          );
        },
      );
    }).toList();
    // height:
    final h = 25 * data0.length.toDouble() + 25;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: h,
              child: BarChart(
                data: data0,
                // measureFormatter: number.format,
                valueAxis: Axis.horizontal,
                // inverted: true,
                minTickSpacing: 40,
                barPadding: 10,
                groupSpacing: 10,
                padding: const EdgeInsets.only(right: 16.0),
                radius: const Radius.circular(6),
                animationDuration: const Duration(milliseconds: 350),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //通过字符串hash值获取颜色
  Color getColor(String str) {
    if (str.contains('日') ||
        str.contains('上午') ||
        str.contains('正午') ||
        str.contains('下午') ||
        str.contains('午后') ||
        str.contains('白天') ||
        str.toLowerCase().contains('day')) {
      return const Color.fromARGB(255, 249, 91, 91);
    }
    if (str.contains('夜') ||
        str.contains('晚上') ||
        str.toLowerCase().contains('night')) {
      return const Color.fromARGB(255, 69, 68, 153);
    }
    if (str.contains('黎明') ||
        str.contains('拂晓') ||
        str.toLowerCase().contains('dawn')) {
      return const Color.fromARGB(255, 98, 56, 43);
    }
    if (str.contains('清晨') ||
        str.contains('早晨') ||
        str.contains('清早') ||
        str.contains('早上') ||
        str.toLowerCase().contains('morning')) {
      return const Color.fromARGB(255, 247, 171, 100);
    }
    if (str.contains('黄昏') ||
        str.contains('傍晚') ||
        str.toLowerCase().contains('evening') ||
        str.toLowerCase().contains('dusk')) {
      return const Color.fromARGB(255, 183, 65, 207);
    }
    if (str.contains('不确定') ||
        str.toLowerCase().contains('unclear') ||
        str.toLowerCase().contains('unknown') ||
        str.toLowerCase().contains('other')) {
      return const Color.fromARGB(255, 209, 210, 209);
    }
    int hash = str.hashCode;
    return Color((hash & 0xFFFFFF) + 0xFF000000);
  }

  Widget _buildStackChart(Map<String, Map<String, Map<String, int>>> data,
      String title, bool charsTime, BuildContext context) {
    Map<String, Color> colors = {};

    // final number = NumberFormat.compact(locale: 'ru');
    final sorted0 = data.entries.toList()
      ..sort((a, b) {
        // sum the values of the inner map
        int aSum = a.value.values
            .fold(0, (sum, e) => sum + e.values.fold(0, (sum, e) => sum + e));
        int bSum = b.value.values
            .fold(0, (sum, e) => sum + e.values.fold(0, (sum, e) => sum + e));
        return bSum.compareTo(aSum);
      });

    final List<MapEntry<String, Map<String, int>>> sorted = [];

    for (var entry in sorted0) {
      final sorted1 = entry.value.entries.toList()
        ..sort((a, b) {
          int aSum = a.value.values.reduce((a, b) => a + b);
          int bSum = b.value.values.reduce((a, b) => a + b);
          return bSum.compareTo(aSum);
        });
      for (var e in sorted1) {
        final newEntry = MapEntry('${entry.key} (${e.key})', e.value);
        sorted.add(newEntry);
      }
    }

    //sorted map to _data
    final List<Series<String, int>> data0 = [];
    for (var entry in sorted) {
      // sort the inner map by value
      final innerSorted = entry.value.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      // create a new map with sorted keys
      var ls = innerSorted.map((e) {
        colors[e.key] = getColor(e.key);
        return Series(
          data: {entry.key: e.value},
          // colorAccessor: (domain, value) => Colors.blue,
          colorAccessor: (domain, value) => colors[e.key]!,
          measureAccessor: (value) => value.toDouble(),
          labelAccessor: (domain, value, percent) {
            var lb = value.toString();
            if (charsTime && value > 0) {
              double currMinu = value / dialCharsPerMinu;
              if (currMinu > 1) {
                int currM = currMinu.toInt();
                lb = "$lb [$currM’]";
              } else {
                int currSeconds = (currMinu * 60).toInt();
                int currS = currSeconds % 60;
                lb = "$lb [$currS”]";
              }
            }
            // lb = '$lb [${e.key}]';
            return ChartLabel(
              lb,
              style: TextStyle(fontSize: 10),
            );
          },
        );
      }).toList();
      data0.addAll(ls);
    }
    // height:
    final h = 25 * sorted.length.toDouble() + 25;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // 颜色图例：
            Wrap(
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: colors.entries.map((e) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      color: e.value,
                    ),
                    const SizedBox(width: 4),
                    Text(e.key),
                    const SizedBox(width: 16),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: h,
              child: StackedBarChart(
                data: data0,
                // measureFormatter: number.format,
                valueAxis: Axis.horizontal,
                // inverted: true,
                minTickSpacing: 40,
                barPadding: 10,
                barSpacing: 10,
                padding: const EdgeInsets.only(right: 16.0, bottom: 0),
                radius: const Radius.circular(6),
                animationDuration: const Duration(milliseconds: 350),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('剧本统计')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildChart(statis.characters, '角色-对白字数 统计', true, false, context),
            _buildStackChart(statis.locationsTime, '地点-场次 统计', false, context),
            _buildChart(statis.times, '时分-场次 统计', false, true, context),
            _buildChart(statis.intexts, '内外景-场次 统计', false, false, context),
          ],
        ),
      ),
    );
  }
}
