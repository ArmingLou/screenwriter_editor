import 'package:flutter/material.dart';
import 'package:screenwriter_editor/statis.dart';
// import 'package:fl_chart/fl_chart.dart';
import 'package:fast_charts/fast_charts.dart';

class StatsPage extends StatelessWidget {
  final Statis statis;

  const StatsPage({super.key, required this.statis});

  Widget _buildChart(
      Map<String, int> data, String title, BuildContext context) {
    // final number = NumberFormat.compact(locale: 'ru');
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    //sorted map to _data
    final _data = sorted.map((entry) {
      return Series(
        data: {entry.key: entry.value},
        colorAccessor: (domain, value) => Colors.blue,
        measureAccessor: (value) => value.toDouble(),
        labelAccessor: (domain, value, percent) => ChartLabel(
          value.toString(),
          style: TextStyle(fontSize: 10),
        ),
      );
    }).toList();
    // height:
    final h = 25 * _data.length.toDouble() + 25;
    
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
                data: _data,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('剧本统计')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildChart(statis.characters, '角色-对白字数 统计', context),
            _buildChart(statis.locations, '地点-场次 统计', context),
            _buildChart(statis.intexts, '内外景-场次 统计', context),
            _buildChart(statis.times, '时分-场次 统计', context),
          ],
        ),
      ),
    );
  }
}
