// lib/home_simple.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import 'app_mode.dart';
import '../notifications/notification_handler.dart';
import '../notifications/notification_ui.dart';
import '../notifications/notification_bell.dart';
import 'nutrition_helpers.dart';
import 'nutrition_widgets.dart';
import 'food_edit_dialog.dart';
import '../widgets/family_switcher.dart';
import '../report.dart';

// ── 簡單模式餐別時間區間 ────────────────────────────────────────────────────────
//   早餐:  03:00 ~ 10:59
//   午餐:  11:00 ~ 16:59
//   晚餐:  17:00 ~ 02:59（隔天）
String _simpleMealTypeByTime(DateTime time) {
  final h = time.hour;
  if (h >= 3  && h < 11) return '早餐';
  if (h >= 11 && h < 17) return '午餐';
  return '晚餐';
}

// ── 每餐統計資料 ────────────────────────────────────────────────────────────────
class _MealStats {
  final String         label;
  final IconData       icon;
  final Color          color;
  final List<FoodItem> items; // 只存放最新一筆（最多 1 筆）

  const _MealStats({
    required this.label,
    required this.icon,
    required this.color,
    required this.items,
  });

  bool      get hasData => items.isNotEmpty;
  FoodItem? get first   => hasData ? items.first : null;
}

// ══════════════════════════════════════════════════════════════════════════════

class HomeSimple extends StatefulWidget {
  const HomeSimple({super.key});

  @override
  State<HomeSimple> createState() => _HomeSimpleState();
}

class _HomeSimpleState extends State<HomeSimple> {
  String?             _targetUid; // 目標 UID（預設為自己），現在看誰的資料
  String              _targetName = "我自己";
  DateTime            _selectedDate = DateTime.now();
  StreamSubscription? _foodSubscription;
  List<FoodItem>      _foodList  = [];
  bool                _isLoading = true;

  // ── 生命週期 ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _targetUid = FirebaseAuth.instance.currentUser?.uid;
    _targetName = "我自己";
    _selectedDate = DateTime.now();
    NotificationHandler.init();

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) _onSignOut(); else _listenToFirebaseData();
    });
  }

  @override
  void dispose() {
    _foodSubscription?.cancel();
    super.dispose();
  }

  // ── Firebase ──────────────────────────────────────────────────────────────────

  void _onSignOut() {
    _foodSubscription?.cancel();
    if (!mounted) return;
    setState(() { _foodList.clear(); _isLoading = false; });
  }

  void _listenToFirebaseData() {
    _foodSubscription?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _isLoading = false); return; }

    final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final end   = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59, 999);

    _foodSubscription = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('analysis_records')
        .where('created_at', isGreaterThanOrEqualTo: start)
        .where('created_at', isLessThanOrEqualTo: end)
        .orderBy('created_at', descending: true)
        .snapshots()
        .listen(_onSnapshot, onError: (e) {
          debugPrint('Firebase 錯誤: $e');
          if (mounted) setState(() => _isLoading = false);
        });
  }

  Future<void> _onSnapshot(QuerySnapshot snapshot) async {
    final List<FoodItem> result = [];
    for (final doc in snapshot.docs) {
      final item = await _parseFoodItem(doc);
      if (item != null) result.add(item);
    }
    if (mounted) setState(() { _foodList = result; _isLoading = false; });
  }

  Future<FoodItem?> _parseFoodItem(QueryDocumentSnapshot doc) async {
    final data     = doc.data() as Map<String, dynamic>;
    final foodName = data['食物名'] ?? '未命名';
    if (foodName == 'string' || foodName == '未命名') return null;

    String mealType = (data['meal_type'] ?? '').toString();
    if (mealType.isEmpty) {
      final ts = data['created_at'] as Timestamp?;
      mealType = _simpleMealTypeByTime(ts?.toDate() ?? DateTime.now());
    }
    if (mealType == '點心') mealType = '晚餐';

    double g = 0, cal = 0, p = 0, c = 0, f = 0;
    final List<Ingredient> ingredients = [];
    try {
      final snap = await doc.reference.collection('ingredients').get();
      for (final ing in snap.docs) {
        final d = ing.data();
        final grams    = parseToDouble(d['重量(g)']);
        final calories = parseToDouble(d['熱量(kcal)']);
        final protein  = parseToDouble(d['蛋白質(g)']);
        final carbs    = parseToDouble(d['碳水化合物(g)']);
        final fat      = parseToDouble(d['脂肪(g)']);
        g += grams; cal += calories; p += protein; c += carbs; f += fat;
        ingredients.add(Ingredient(
          id: ing.id, name: d['食材名'] ?? '未知食材',
          grams: grams, calories: calories,
          carbs: carbs, protein: protein, fat: fat,
        ));
      }
    } catch (e) { debugPrint('讀取食材錯誤: $e'); }

    return FoodItem(
      reference: doc.reference, id: doc.id, name: foodName,
      calories:  '${cal.toStringAsFixed(0)} 大卡',
      imagePath: data['圖片_base64'] ?? data['圖片網址'] ?? '',
      grams: g.toStringAsFixed(1), protein: p.toStringAsFixed(1),
      carbs: c.toStringAsFixed(1), fat: f.toStringAsFixed(1),
      ingredients: ingredients,
      remark: data['備註'] ?? '', aiSuggestion: data['AI分析建議'] ?? '',
      mealType: mealType,
    );
  }

  // ── 分組（每時段只保留最新一筆）─────────────────────────────────────────────────
  // snapshot 已按 descending 排序，第一個遇到的就是最新一筆

  List<_MealStats> _groupByMeal() {
    final map = <String, List<FoodItem>>{
      '早餐': [], '午餐': [], '晚餐': [],
    };
    for (final item in _foodList) {
      final key = map.containsKey(item.mealType) ? item.mealType : '晚餐';
      if (map[key]!.isEmpty) map[key]!.add(item); // 只取第一筆
    }
    return [
      _MealStats(label: '早餐', icon: Icons.wb_twilight, color: Colors.amber, items: map['早餐']!),
      _MealStats(label: '午餐', icon: Icons.wb_sunny,    color: Colors.orangeAccent, items: map['午餐']!),
      _MealStats(label: '晚餐', icon: Icons.nights_stay,  color: Colors.indigoAccent, items: map['晚餐']!),
    ];
  }

  // ── 導航 ──────────────────────────────────────────────────────────────────────

  Future<void> _openReportPage() async {
    final reportTargetUid =
        _targetUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportPage(
          userId: reportTargetUid,
          initialReferenceDate: _selectedDate, // 傳入目前選擇的日期
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    final d = _selectedDate;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}',
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        IconButton(
          icon: Icon(Icons.calendar_month_outlined, color: Colors.grey[700]),
          onPressed: _pickDate,
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(now.year - 5, now.month, now.day),
      lastDate: now,
    );
    if (picked != null && picked != _selectedDate && mounted) {
      setState(() { _selectedDate = picked; _isLoading = true; });
      _listenToFirebaseData();
    }
  }

  /// 無資料時點擊餐別卡片：帶著強制餐別參數跳到分析頁
  Future<void> _goAnalysisWithMeal(String mealLabel) async {
    final result = await Navigator.pushNamed(
      context,
      '/analysis',
      arguments: {'forceMealType': mealLabel},
    );
    if (result == true && mounted) {
      setState(() => _isLoading = true);
      _listenToFirebaseData();
    }
  }

  // ── 建構 ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(),
        ),
        floatingActionButton: _buildFab(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final d = _selectedDate;
    final dateStr =
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return AppBar(
      automaticallyImplyLeading: false,
      actions: [
        // 1. 家庭切換器 (來自 familysetting0402)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FamilySwitcher(
            currentName: _targetName,
            onSelected: (uid, name) {
              setState(() {
                _targetUid = uid;
                _targetName = name;
                  _isLoading = true; // 切換時顯示 loading
              });
              // 重新監聽資料流
              _listenToFirebaseData();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: NotificationBell(
            onPressed: () => NotificationUI.showTodayNotifications(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: const Icon(Icons.bar_chart),
            // onPressed: () => Navigator.pushNamed(context, '/reports'),
            onPressed: () => _openReportPage(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 25),
          child: IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    final meals = _groupByMeal();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildDateRow(),
          const SizedBox(height: 10),
          // 三張餐別卡片
          ...meals.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MealCard(
              stats:        m,
              selectedDate: _selectedDate,
              onDelete:     (item) => ConfirmDeleteDialog.show(context, item),
              onTapEmpty:   () => _goAnalysisWithMeal(m.label),
            ),
          )),

          const SizedBox(height: 4),

          // 今日完整紀錄列表
          DailyFoodList(
            isLoading:    _isLoading,
            foodList:     _foodList,
            onTapItem:    (item) => FoodEditDialog.show(
              context,
              item:         item,
              selectedDate: _selectedDate,
            ),
            onDeleteItem: (item) => ConfirmDeleteDialog.show(context, item),
          ),
        ],
      ),
    );
  }
  Widget _buildFab() {
    return Container(
      margin: const EdgeInsets.only(right: 20, bottom: 25),
      child: FloatingActionButton.small(
        elevation: 4,
        backgroundColor: const Color.fromARGB(255, 157, 198, 194),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 20),
        onPressed: () async {
          final result = await Navigator.pushNamed(context, '/analysis');
          if (result == true && mounted) {
            setState(() => _isLoading = true);
            _listenToFirebaseData();
          }
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 餐別卡片（無折疊，無資料↔有資料 兩種狀態）
// ══════════════════════════════════════════════════════════════════════════════

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.stats,
    required this.selectedDate,
    required this.onDelete,
    required this.onTapEmpty,
  });

  final _MealStats              stats;
  final DateTime                selectedDate;
  final void Function(FoodItem) onDelete;
  final VoidCallback             onTapEmpty;

  Color get _bg     => stats.hasData ? stats.color.withOpacity(0.07) : Colors.white;
  Color get _border => stats.hasData
      ? stats.color.withOpacity(0.30)
      : Colors.grey.withOpacity(0.20);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 無資料：整張卡片可點擊；有資料：由內部各元件各自處理
      onTap: stats.hasData ? null : onTapEmpty,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color:        _bg,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color:      Colors.grey.withOpacity(0.10),
              blurRadius: 8,
              offset:     const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 餐別 icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: stats.color.withOpacity(stats.hasData ? 0.18 : 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(stats.icon, size: 22, color: stats.color),
            ),
            const SizedBox(width: 14),

            // 中間內容
            Expanded(
              child: stats.hasData ? _FilledContent(stats: stats, selectedDate: selectedDate) : _EmptyContent(stats: stats),
            ),

            // 右側操作
            stats.hasData
                ? _DeleteButton(item: stats.first!, onDelete: onDelete)
                : Icon(Icons.add_circle_outline, color: Colors.grey[350], size: 22),
          ],
        ),
      ),
    );
  }
}

// ── 無資料狀態內容 ─────────────────────────────────────────────────────────────

class _EmptyContent extends StatelessWidget {
  const _EmptyContent({required this.stats});
  final _MealStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(stats.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('點擊新增${stats.label}',
            style: TextStyle(fontSize: 12, color: Colors.grey[400])),
      ],
    );
  }
}

// ── 有資料狀態內容 ─────────────────────────────────────────────────────────────

class _FilledContent extends StatelessWidget {
  const _FilledContent({required this.stats, required this.selectedDate});
  final _MealStats stats;
  final DateTime   selectedDate;

  @override
  Widget build(BuildContext context) {
    final item = stats.first!;
    return GestureDetector(
      onTap: () => FoodEditDialog.show(context, item: item, selectedDate: selectedDate),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 餐別小標 + 食物名
          Row(
            children: [
              Text(stats.label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: stats.color)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 熱量 + 三大營養素
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(item.calories,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: stats.color)),
              _MacroLabel('蛋白質', item.protein, const Color.fromARGB(255, 117, 181, 233)),
              _MacroLabel('碳水', item.carbs,   const Color.fromARGB(255, 132, 202, 206)),
              _MacroLabel('脂肪', item.fat,     const Color.fromARGB(255, 245, 190, 118)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 刪除按鈕 ───────────────────────────────────────────────────────────────────

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.item, required this.onDelete});
  final FoodItem                item;
  final void Function(FoodItem) onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.delete_outline, size: 20,
            color: Color.fromARGB(180, 26, 24, 23)),
        onPressed: () => onDelete(item),
      ),
    );
  }
}

// ── 三大營養素文字標籤 ─────────────────────────────────────────────────────────

class _MacroLabel extends StatelessWidget {
  const _MacroLabel(this.prefix, this.value, this.color);
  final String prefix;
  final String value;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Text('$prefix ${value}g',
        style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600));
  }
}