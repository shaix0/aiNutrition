// report_page.dart
// 週報 / 月報 / 自訂報告頁面
// 結構：ReportLogic（純資料）+ ReportPage（純 UI）

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'models.dart';
import 'home/nutrition_helpers.dart';

// ════════════════════════════════════════════════════════════════════════════
// 資料層：ReportLogic
// ════════════════════════════════════════════════════════════════════════════

/// 報表期間摘要資料
class ReportData {
  final String period;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final int    totalMeals;
  final double totalWeight;
  final Map<String, double> dailyAverages; // protein / carbs / fat
  final List<MapEntry<DateTime, double>> topCalorieDays;
  final String aiFeedback;

  const ReportData({
    required this.period,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.totalMeals,
    required this.totalWeight,
    required this.dailyAverages,
    required this.topCalorieDays,
    required this.aiFeedback,
  });
}

/// 報表類型
enum ReportType { weekly, monthly, custom }

/// 純資料邏輯，不含任何 Widget
class ReportLogic {
  ReportLogic({required this.userId, DateTime? initialDate})
      : _referenceDate = initialDate ?? DateTime.now();

  final String   userId;
  DateTime?      _referenceDate;
  ReportType     reportType    = ReportType.weekly;
  DateTime?      customStart;
  DateTime?      customEnd;

  bool           isLoading     = true;
  ReportData?    reportData;
  List<FoodItem> foodList      = [];

  // ── 公開 getter ────────────────────────────────────────────────────────────

  DateTime get referenceDate => _referenceDate ?? DateTime.now();
  set referenceDate(DateTime d) => _referenceDate = d;

  /// 目前期間的顯示文字
  String get dateRangeText {
    final now = DateTime.now();
    switch (reportType) {
      case ReportType.weekly:
        final s = _weekStart(referenceDate);
        final e = _weekEnd(referenceDate);
        return '${_fmt(s)} - ${_fmt(e)}';
      case ReportType.monthly:
        return '${referenceDate.year}/${referenceDate.month.toString().padLeft(2, '0')}';
      case ReportType.custom:
        return (customStart != null && customEnd != null)
            ? '${_fmt(customStart!)} - ${_fmt(customEnd!)}'
            : '自訂範圍';
    }
  }

  // ── 資料載入 ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    isLoading = true;

    final now = DateTime.now();
    late DateTime start, end;

    switch (reportType) {
      case ReportType.weekly:
        start = _weekStart(referenceDate);
        end   = _weekEnd(referenceDate);
        break;
      case ReportType.monthly:
        start = DateTime(referenceDate.year, referenceDate.month, 1);
        end   = DateTime(referenceDate.year, referenceDate.month + 1, 0);
        break;
      case ReportType.custom:
        start = customStart ?? DateTime(now.year, now.month, now.day - 7);
        end   = customEnd   ?? now;
        break;
    }

    // 標準化時間
    start = DateTime(start.year, start.month, start.day, 0, 0, 0);
    end   = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

    final totalDays = end.difference(start).inDays + 1;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('analysis_records')
          .where('created_at', isGreaterThanOrEqualTo: start)
          .where('created_at', isLessThanOrEqualTo: end)
          .orderBy('created_at', descending: false)
          .get();

      final List<FoodItem>               foods        = [];
      final Map<DateTime, double>        dailyCals    = {};
      double tCal = 0, tP = 0, tC = 0, tF = 0, tW = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final ts   = data['created_at'] as Timestamp?;
        if (ts == null) continue;
        final time    = ts.toDate();
        final dateKey = DateTime(time.year, time.month, time.day);

        double mCal = 0, mP = 0, mC = 0, mF = 0, mW = 0;
        final ingSnap = await doc.reference.collection('ingredients').get();
        for (final ing in ingSnap.docs) {
          final d = ing.data();
          mCal += parseToDouble(d['熱量(kcal)']);
          mP   += parseToDouble(d['蛋白質(g)']);
          mC   += parseToDouble(d['碳水化合物(g)']);
          mF   += parseToDouble(d['脂肪(g)']);
          mW   += parseToDouble(d['重量(g)']);
        }

        dailyCals[dateKey] = (dailyCals[dateKey] ?? 0) + mCal;
        tCal += mCal; tP += mP; tC += mC; tF += mF; tW += mW;

        final mealType = (data['meal_type'] ?? '').toString().isNotEmpty
            ? data['meal_type'].toString()
            : mealTypeByTime(time);

        foods.add(FoodItem(
          reference:    doc.reference,
          id:           doc.id,
          name:         data['食物名'] ?? '未命名',
          calories:     '${mCal.toStringAsFixed(0)} 大卡',
          imagePath:    data['圖片_base64'] ?? data['圖片網址'] ?? '',
          grams:        mW.toStringAsFixed(1),
          protein:      mP.toStringAsFixed(1),
          carbs:        mC.toStringAsFixed(1),
          fat:          mF.toStringAsFixed(1),
          ingredients:  [],
          remark:       data['備註'] ?? '',
          aiSuggestion: data['AI分析建議'] ?? '',
          mealType:     mealType,
          createdAt:    time,
        ));
      }

      final recorded = dailyCals.length;
      reportData = ReportData(
        period:         dateRangeText,
        totalCalories:  tCal,
        totalProtein:   tP,
        totalCarbs:     tC,
        totalFat:       tF,
        totalMeals:     foods.length,
        totalWeight:    tW,
        dailyAverages: {
          'protein': recorded > 0 ? tP / recorded : 0,
          'carbs':   recorded > 0 ? tC / recorded : 0,
          'fat':     recorded > 0 ? tF / recorded : 0,
        },
        topCalorieDays: dailyCals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)),
        aiFeedback: _generateFeedback(
          tCal / totalDays, tP / totalDays, tC / totalDays, tF / totalDays),
      );
      foodList = foods;
    } catch (e) {
      debugPrint('ReportLogic.load 錯誤: $e');
    }

    isLoading = false;
  }

  // ── 私有輔助 ───────────────────────────────────────────────────────────────

  String _generateFeedback(double avgCal, double p, double c, double f) {
    if (avgCal == 0) return '目前尚無足夠數據。開始記錄餐點，AI 將為您分析飲食趨勢！';

    final buf = <String>[];

    if (avgCal > 2300) {
      buf.add('⚠️ 本期平均熱量攝取較高 (${avgCal.toStringAsFixed(0)} kcal)，建議控制精緻澱粉份量並增加活動量。');
    } else if (avgCal < 1200) {
      buf.add('ℹ️ 平均攝取熱量偏低，請確保攝取充足能量以維持基礎代謝。');
    } else {
      buf.add('✅ 平均攝取熱量穩定 (${avgCal.toStringAsFixed(0)} kcal)，請繼續保持良好習慣！');
    }

    final total = (p * 4) + (c * 4) + (f * 9);
    if (total > 0) {
      if ((p * 4) / total < 0.15) buf.add('🥚 蛋白質比例稍低，可以多補充豆魚蛋肉類。');
      if ((c * 4) / total > 0.65) buf.add('🍚 碳水比例偏高，建議減少精緻糖類攝取。');
      if ((f * 9) / total > 0.35) buf.add('🥑 脂質比例較高，建議多採用清蒸或水煮。');
    }

    if (buf.length == 1) buf.add('🌟 您的飲食比例均衡，目前維持得非常好！');
    return buf.join('\n');
  }

  static DateTime _weekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));
  static DateTime _weekEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day + (7 - d.weekday), 23, 59, 59);
  static String _fmt(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

// ════════════════════════════════════════════════════════════════════════════
// UI 層：ReportPage
// ════════════════════════════════════════════════════════════════════════════

class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    required this.userId,
    this.initialReferenceDate,
  });

  final String   userId;
  final DateTime? initialReferenceDate;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabController;
  late final ReportLogic   _logic;

  static const double spacing = 16.0;

  // ── 生命週期 ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _logic = ReportLogic(
      userId:      widget.userId,
      initialDate: widget.initialReferenceDate,
    );
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
    _reload();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  // ── 事件 ────────────────────────────────────────────────────────────────────

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _logic.reportType = ReportType.values[_tabController.index];
    _reload();
  }

  Future<void> _reload() async {
    await _logic.load();
    if (mounted) setState(() {});
  }

  /// 點擊日期區塊：週/月報選單一日期，自訂選日期範圍
  Future<void> _onDateRangeTap() async {
    if (_logic.reportType == ReportType.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(DateTime.now().year - 1),
        lastDate:  DateTime.now(),
      );
      if (range != null) {
        _logic.customStart = range.start;
        _logic.customEnd   = range.end;
        _reload();
      }
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: _logic.referenceDate,
        firstDate:   DateTime(DateTime.now().year - 5),
        lastDate:    DateTime.now(),
      );
      if (picked != null) {
        _logic.referenceDate = picked;
        _reload();
      }
    }
  }

  // ── 建構 ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('營養報告'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(child: Text('週報')),
                Tab(child: Text('月報')),
                Tab(child: Text('自訂')),
              ],
            ),
          ),
        ),
      ),
      body: _logic.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _summary(),
                      const SizedBox(height: spacing),
                      _avg(),
                      const SizedBox(height: spacing),
                      _ai(),
                      const SizedBox(height: spacing),
                      _list(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ── 區塊 builders ──────────────────────────────────────────────────────────

  /// 1. 營養摘要卡片
  Widget _summary() {
    final d = _logic.reportData;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('營養摘要',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              // 日期區間選擇器
              GestureDetector(
                onTap: _onDateRangeTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 157, 198, 194).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color.fromARGB(255, 157, 198, 194).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(_logic.dateRangeText,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700])),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_calendar,
                          size: 16,
                          color: Color.fromARGB(255, 157, 198, 194)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _summaryItem('總餐數',  '${d?.totalMeals ?? 0}',                                        Icons.restaurant,            Colors.blue)),
              Expanded(child: _summaryItem('總重量',  '${(d?.totalWeight ?? 0).toStringAsFixed(1)} g',                Icons.fitness_center,        Colors.green)),
              Expanded(child: _summaryItem('總熱量',  '${(d?.totalCalories ?? 0).toStringAsFixed(0)} kcal',           Icons.local_fire_department, Colors.orange)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _summaryItem('蛋白質', '${(d?.totalProtein ?? 0).toStringAsFixed(1)} g', Icons.restaurant_menu, const Color.fromARGB(255, 117, 181, 233))),
              Expanded(child: _summaryItem('碳水',   '${(d?.totalCarbs   ?? 0).toStringAsFixed(1)} g', Icons.water_drop,      const Color.fromARGB(255, 132, 202, 206))),
              Expanded(child: _summaryItem('脂質',   '${(d?.totalFat     ?? 0).toStringAsFixed(1)} g', Icons.opacity,         const Color.fromARGB(255, 245, 190, 118))),
            ],
          ),
        ],
      ),
    );
  }

  /// 2. 每日平均卡片
  Widget _avg() {
    final avgs = _logic.reportData?.dailyAverages ?? {};
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每日平均攝取',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              _avgColumn('${(avgs['protein'] ?? 0).toStringAsFixed(1)} g', '蛋白質',
                  const Color.fromARGB(255, 117, 181, 233)),
              _avgColumn('${(avgs['carbs']   ?? 0).toStringAsFixed(1)} g', '碳水',
                  const Color.fromARGB(255, 132, 202, 206)),
              _avgColumn('${(avgs['fat']     ?? 0).toStringAsFixed(1)} g', '脂質',
                  const Color.fromARGB(255, 245, 190, 118)),
            ],
          ),
        ],
      ),
    );
  }

  /// 3. AI 建議卡片
  Widget _ai() {
    final feedback = _logic.reportData?.aiFeedback;
    if (feedback == null) return const SizedBox.shrink();
    return _card(
      color: const Color(0xFFF1F8F7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.teal[600], size: 22),
              const SizedBox(width: 8),
              const Text('AI 營養觀察與建議',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D4F4B))),
            ],
          ),
          const Divider(height: 24, thickness: 0.8),
          Text(feedback,
              style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87)),
        ],
      ),
    );
  }

  /// 4. 餐點紀錄卡片
  Widget _list() {
    final foods = _logic.foodList;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_logic.reportData?.period ?? ''} 餐點紀錄',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          foods.isEmpty
              ? const Center(child: Text('本期尚無餐點紀錄'))
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: foods.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _foodRow(foods[i]),
                ),
        ],
      ),
    );
  }

  // ── 小型 Widget 輔助 ────────────────────────────────────────────────────────

  /// 通用卡片容器
  Widget _card({required Widget child, Color? color}) => Card(
        elevation: 4,
        color: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      );

  /// 摘要格子
  Widget _summaryItem(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration:
              BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center),
      ],
    );
  }

  /// 每日平均欄
  Widget _avgColumn(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  /// 單一餐點列
  Widget _foodRow(FoodItem item) {
    return Row(
      children: [
        _foodImage(item.imagePath, item.mealType),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '${_fmtDate(item.createdAt!)} • ${item.mealType}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        Text(item.calories,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// 餐點縮圖（base64 / http / icon 佔位）
  Widget _foodImage(String path, String mealType) {
    const size = 40.0;
    Widget img;

    if (path.startsWith('data:image') ||
        (path.length > 1000 && !path.startsWith('http'))) {
      try {
        img = Image.memory(
          base64Decode(path.replaceFirst('data:image/jpeg;base64,', '')),
          fit: BoxFit.cover, width: size, height: size,
        );
      } catch (_) {
        img = _mealIconPlaceholder(mealType, size);
      }
    } else if (path.startsWith('http')) {
      img = Image.network(
        path, fit: BoxFit.cover, width: size, height: size,
        errorBuilder: (_, __, ___) => _mealIconPlaceholder(mealType, size),
      );
    } else {
      img = _mealIconPlaceholder(mealType, size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: size, height: size, child: img),
    );
  }

  Widget _mealIconPlaceholder(String mealType, double size) {
    final color = _mealColor(mealType);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(_mealIcon(mealType), color: color, size: size * 0.5),
    );
  }

  // ── 靜態輔助 ────────────────────────────────────────────────────────────────

  static String _fmtDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  static IconData _mealIcon(String t) {
    switch (t) {
      case '早餐': return Icons.wb_twilight;
      case '午餐': return Icons.wb_sunny;
      case '晚餐': return Icons.nights_stay;
      default:    return Icons.cookie;
    }
  }

  static Color _mealColor(String t) {
    switch (t) {
      case '早餐': return Colors.amber;
      case '午餐': return Colors.orange;
      case '晚餐': return Colors.indigoAccent;
      default:    return Colors.pinkAccent;
    }
  }
}