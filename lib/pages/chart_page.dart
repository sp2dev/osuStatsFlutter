import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
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
  
  String _selectedRange = '全部';
  int _customDays = 0;
  final TextEditingController _customDaysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _processData();
  }
  
  @override
  void dispose() {
    _customDaysController.dispose();
    super.dispose();
  }

  /// Bumped on every [_processData] start; stale async parses are dropped so
  /// rapid range changes can never apply out-of-order results.
  int _processGeneration = 0;

  Future<void> _processData() async {
    final generation = ++_processGeneration;
    int? startTimeMs;
    final now = DateTime.now();

    if (_selectedRange == '1天') {
      startTimeMs = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    } else if (_selectedRange == '3天') {
      startTimeMs = now.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    } else if (_selectedRange == '7天') {
      startTimeMs = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    } else if (_selectedRange == '1个月') {
      startTimeMs = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    } else if (_selectedRange == '自定义' && _customDays > 0) {
      startTimeMs = now.subtract(Duration(days: _customDays)).millisecondsSinceEpoch;
    }

    // Heavy JSON decoding runs off the main isolate (shared util).
    final dataPoints = await compute(computeDataPoints, {
      'history': widget.history,
      'modeKey': widget.modeKey,
      'fieldKey': widget.fieldKey,
      'startTimeMs': startTimeMs,
    });

    if (!mounted || generation != _processGeneration) return;

    dataPoints.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));

    if (dataPoints.isEmpty) {
      setState(() {
        _spots = [];
        _times = [];
      });
      return;
    }

    List<FlSpot> spots = [];
    List<DateTime> times = [];

    double minY = dataPoints.first['value'];
    double maxY = dataPoints.first['value'];

    for (int i = 0; i < dataPoints.length; i++) {
      final val = dataPoints[i]['value'] as double;
      spots.add(FlSpot(i.toDouble(), val));
      times.add(DateTime.fromMillisecondsSinceEpoch(dataPoints[i]['time'] as int));

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
    if (widget.fieldKey == 'global_rank' || widget.fieldKey == 'country_rank') {
      return '#${formatNum(value.abs().toInt())}';
    } else if (widget.fieldKey == 'accuracy') {
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
        title: Text('${widget.username} 的数据'),
      ),
      body: Padding(
        padding: const EdgeInsets.only(right: 24, left: 16, top: 24, bottom: 24),
        child: Column(
          children: [
            Expanded(
              child: _spots.isEmpty
                  ? const Center(child: Text('暂无所选范围内的数据生成图表'))
                  : Column(
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('选择比对时间范围', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedRange,
                            isExpanded: true,
                            items: ['全部', '1天', '3天', '7天', '1个月', '自定义']
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedRange = val;
                                });
                                _processData();
                              }
                            },
                          ),
                        ),
                      ),
                      if (_selectedRange == '自定义') ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _customDaysController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '输入天数',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixText: '天',
                          ),
                          onChanged: (val) {
                            setState(() {
                              _customDays = int.tryParse(val) ?? 0;
                            });
                            _processData();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
