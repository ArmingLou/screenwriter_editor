import 'package:flutter/material.dart';
import 'package:screenwriter_editor/statis.dart';
import 'package:fl_chart/fl_chart.dart';

class StatsPage extends StatelessWidget {
  final Statis statis;

  const StatsPage({super.key, required this.statis});

  List<BarChartGroupData> _buildBarGroups(Map<String, int> data) {
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return List.generate(sorted.length, (index) {
      final entry = sorted[index];
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: entry.value.toDouble(),
            color: Colors.blue,
            width: 20,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
        showingTooltipIndicators: [0],
      );
    });
  }

  Widget _buildChart(Map<String, int> data, String title, BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barGroups: _buildBarGroups(data),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final entry = data.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value));
                          if (value.toInt() < entry.length) {
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                entry[value.toInt()].key,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                ),
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
            _buildChart(statis.characters, '角色时间统计', context),
            _buildChart(statis.locations, '地点场次统计', context),
            _buildChart(statis.times, '日夜场次统计', context),
            _buildChart(statis.intexts, '内外场次统计', context),
          ],
        ),
      ),
    );
  }
}