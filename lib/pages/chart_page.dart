import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils.dart';

class ChartPage extends StatefulWidget {
  final String username;
  final String statLabel;
  final String fieldKey;
  final String modeKey;
  final List<Map<String, dynamic>> history;

  const ChartPage({
    super.key,
    required this.username,
    required this.statLabel,
    required this.fieldKey,
    required this.modeKey,
    required this.history,
  });

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  List<FlSpot> _spots = [];
  List<DateTime> _times = [];
  double _minY = 0;
  double _maxY = 0;

  @override
  void initState() {
    super.initState();
    _processData();
  }

  void _processData() {
    List<Map<String, dynamic>> dataPoints = [];

    for (final record in widget.history) {
      final jsonStr = record[widget.modeKey] as String?;
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final stats = data['statistics'] as Map<String, dynamic>? ?? {};
          final value = stats[widget.fieldKey];
          if (value != null) {
            num numValue = value as num;
            if (widget.fieldKey == 'accuracy') {
              numValue = numValue * 100;
            } else if (widget.fieldKey == 'play_time') {
              numValue = numValue / 3600.0; // hours
            }

            dataPoints.add({
              'time': DateTime.fromMillisecondsSinceEpoch(record['updated_at'] as int),
              'value': numValue.toDouble(),
            });
          }
        } catch (_) {}
      }
    }

    dataPoints.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

    if (dataPoints.isEmpty) return;

    List<FlSpot> spots = [];
    List<DateTime> times = [];
    
    // We can use the index as x-axis, or time since first record
    // Since records might not be evenly spaced, using time since first record is better
    // But fl_chart can handle X as timestamp as long as we format it correctly.
    // However, timestamp can be very large numbers. Better to use index, or hours since first.
    // Let's use milliseconds since epoch / 1000000 to keep it manageable, 
    // or just index if there are few points. Wait, using index is simpler, but doesn't reflect time gaps.
    // Let's use the actual timestamp / (1000 * 60) (minutes since epoch)
    // Wait, let's just map x to index, and use the times list to get the date for tooltip.
    
    double minY = dataPoints.first['value'];
    double maxY = dataPoints.first['value'];

    for (int i = 0; i < dataPoints.length; i++) {
      final val = dataPoints[i]['value'] as double;
      spots.add(FlSpot(i.toDouble(), val));
      times.add(dataPoints[i]['time'] as DateTime);

      if (val < minY) minY = val;
      if (val > maxY) maxY = val;
    }
    
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    } else {
      double diff = maxY - minY;
      minY -= diff * 0.1;
      maxY += diff * 0.1;
    }

    setState(() {
      _spots = spots;
      _times = times;
      _minY = minY;
      _maxY = maxY;
    });
  }

  String _formatY(double value) {
    if (widget.fieldKey == 'accuracy') {
      return '${value.toStringAsFixed(2)}%';
    } else if (widget.fieldKey == 'play_time') {
      return '${value.toStringAsFixed(1)}h';
    } else {
      return formatNum(value.toInt());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.username} 数据的变化情况'),
      ),
      body: _spots.isEmpty
          ? const Center(child: Text('暂无足够的数据生成图表'))
          : Padding(
              padding: const EdgeInsets.only(right: 24, left: 16, top: 24, bottom: 24),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          widget.statLabel,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: LineChart(
                      LineChartData(
                        minY: _minY,
                        maxY: _maxY,
                        minX: -0.2,
                        maxX: (_spots.length - 1).toDouble() + 0.2,
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((LineBarSpot touchedSpot) {
                                final index = touchedSpot.x.toInt();
                                if (index < 0 || index >= _times.length) return null;
                                final time = _times[index];
                                final timeStr = '${time.month}-${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                return LineTooltipItem(
                                  '$timeStr\n${_formatY(touchedSpot.y)}',
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= _times.length || value != index.toDouble()) {
                                  return const SizedBox.shrink();
                                }
                                final time = _times[index];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '${time.month}-${time.day}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  _formatY(value),
                                  style: const TextStyle(fontSize: 10),
                                  textAlign: TextAlign.right,
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _spots,
                            isCurved: false,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) {
                                return FlDotCirclePainter(
                                  radius: 4,
                                  color: Theme.of(context).colorScheme.primary,
                                  strokeWidth: 2,
                                  strokeColor: Theme.of(context).colorScheme.surface,
                                );
                              },
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                      ],
                    ),
                  ),
                  const Expanded(
                    child: SizedBox(),
                  ),
                ],
              ),
            ),
    );
  }
}
