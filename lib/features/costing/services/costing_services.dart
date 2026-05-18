// lib/features/costing/services/costing_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/costing_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ABSTRACT: Interface
// ─────────────────────────────────────────────────────────────────────────────
abstract class ICostingService {
  Future<List<CostingModel>> getAllCostings();
  Future<CostingModel?> getCostingById(String id);
  Future<CostingModel?> getCostingByMenuItemId(String menuItemId);
  Future<CostingModel> createCosting(CostingModel costing);
  Future<CostingModel> updateCosting(CostingModel costing);
  Future<void> deleteCosting(String id);
  Future<OperatingExpenseModel?> getLatestOperatingExpense();
  Future<OperatingExpenseModel> upsertOperatingExpense(OperatingExpenseModel expense);
  Future<List<CostingModel>> getCostingsWithLowMargin(double thresholdPercent);
  Future<void> recalculateAllocatedCosts(OperatingExpenseModel expense);
}

// ─────────────────────────────────────────────────────────────────────────────
// IMPLEMENTASI SUPABASE
// ─────────────────────────────────────────────────────────────────────────────
class CostingService implements ICostingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _costingsTable = 'costings';
  static const String _operatingExpensesTable = 'operating_expenses';

  // ─────────────────────────────────────────────────
  // CRUD: Costings
  // ─────────────────────────────────────────────────

  @override
  Future<List<CostingModel>> getAllCostings() async {
    final res = await _supabase
        .from(_costingsTable)
        .select()
        .order('updated_at', ascending: false);
    return (res as List).map((e) => CostingModel.fromJson(e)).toList();
  }

  @override
  Future<CostingModel?> getCostingById(String id) async {
    final res = await _supabase
        .from(_costingsTable)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return CostingModel.fromJson(res);
  }

  @override
  Future<CostingModel?> getCostingByMenuItemId(String menuItemId) async {
    final res = await _supabase
        .from(_costingsTable)
        .select()
        .eq('menu_item_id', menuItemId)
        .maybeSingle();
    if (res == null) return null;
    return CostingModel.fromJson(res);
  }

  @override
  Future<CostingModel> createCosting(CostingModel costing) async {
    // Hapus 'id' agar Supabase generate UUID sendiri
    final data = costing.toJson()..remove('id');
    final res = await _supabase
        .from(_costingsTable)
        .insert(data)
        .select()
        .single();
    return CostingModel.fromJson(res);
  }

  @override
  Future<CostingModel> updateCosting(CostingModel costing) async {
    final res = await _supabase
        .from(_costingsTable)
        .update(costing.toJson())
        .eq('id', costing.id)
        .select()
        .single();
    return CostingModel.fromJson(res);
  }

  @override
  Future<void> deleteCosting(String id) async {
    await _supabase
        .from(_costingsTable)
        .delete()
        .eq('id', id);
  }

  // ─────────────────────────────────────────────────
  // CRUD: Operating Expenses
  // ─────────────────────────────────────────────────

  @override
  Future<OperatingExpenseModel?> getLatestOperatingExpense() async {
    final res = await _supabase
        .from(_operatingExpensesTable)
        .select()
        .order('period_year', ascending: false)
        .order('period_month', ascending: false)
        .limit(1)
        .maybeSingle();
    if (res == null) return null;
    return OperatingExpenseModel.fromJson(res);
  }

  @override
  Future<OperatingExpenseModel> upsertOperatingExpense(
      OperatingExpenseModel expense) async {
    final data = expense.toJson()..remove('id');
    final res = await _supabase
        .from(_operatingExpensesTable)
        .upsert(
          data,
          onConflict: 'period_year,period_month',
        )
        .select()
        .single();
    return OperatingExpenseModel.fromJson(res);
  }

  // ─────────────────────────────────────────────────
  // QUERY KHUSUS
  // ─────────────────────────────────────────────────

  @override
  Future<List<CostingModel>> getCostingsWithLowMargin(
      double thresholdPercent) async {
    final all = await getAllCostings();
    return all
        .where((c) =>
            c.currentSellingPrice > 0 &&
            c.actualProfitMarginPercent < thresholdPercent)
        .toList();
  }

  Future<void> recalculateAllocatedCosts(OperatingExpenseModel expense) async {
    final all = await getAllCostings();
    final costPerPortion = expense.operatingCostPerPortion;
    for (final costing in all) {
      await updateCosting(
        costing.copyWith(allocatedOperatingCost: costPerPortion),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOCK SERVICE: Untuk testing / development tanpa Supabase
// ─────────────────────────────────────────────────────────────────────────────
class MockCostingService implements ICostingService {
  final Map<String, Map<String, dynamic>> _costingsDb = {};
  final Map<String, Map<String, dynamic>> _expensesDb = {};
  int _idCounter = 1;

  MockCostingService() {
    _seedDummyData();
  }

  void _seedDummyData() {
    final now = DateTime.now();
    final dummies = [
      CostingModel(
        id: 'cost-001', menuItemId: 'menu-001', menuItemName: 'Nasi Goreng Spesial',
        ingredientCost: 12500, packagingCost: 1500, allocatedOperatingCost: 3000,
        targetProfitMarginPercent: 35, currentSellingPrice: 35000,
        createdAt: now, updatedAt: now,
      ),
      CostingModel(
        id: 'cost-002', menuItemId: 'menu-002', menuItemName: 'Ayam Bakar',
        ingredientCost: 18000, packagingCost: 1500, allocatedOperatingCost: 3000,
        targetProfitMarginPercent: 35, currentSellingPrice: 42000,
        createdAt: now, updatedAt: now,
      ),
    ];
    for (final c in dummies) {
      _costingsDb[c.id] = c.toJson();
    }
    final exp = OperatingExpenseModel(
      id: 'exp-001', periodLabel: 'Mei 2025', periodYear: 2025, periodMonth: 5,
      totalLaborCost: 15000000, electricityCost: 2500000, waterCost: 500000,
      gasCost: 750000, internetCost: 350000, rentCost: 8000000,
      otherOverheadCost: 1000000, estimatedPortionsSoldMonthly: 3000,
      createdAt: now, updatedAt: now,
    );
    _expensesDb[exp.id] = exp.toJson();
  }

  @override
  Future<List<CostingModel>> getAllCostings() async {
    return _costingsDb.values.map((e) => CostingModel.fromJson(e)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<CostingModel?> getCostingById(String id) async {
    final d = _costingsDb[id];
    return d == null ? null : CostingModel.fromJson(d);
  }

  @override
  Future<CostingModel?> getCostingByMenuItemId(String menuItemId) async {
    final found = _costingsDb.values
        .where((e) => e['menu_item_id'] == menuItemId)
        .firstOrNull;
    return found == null ? null : CostingModel.fromJson(found);
  }

  @override
  Future<CostingModel> createCosting(CostingModel costing) async {
    final newId = 'mock-${_idCounter++}';
    final c = costing.copyWith(id: newId, createdAt: DateTime.now(), updatedAt: DateTime.now());
    _costingsDb[newId] = c.toJson();
    return c;
  }

  @override
  Future<CostingModel> updateCosting(CostingModel costing) async {
    final c = costing.copyWith(updatedAt: DateTime.now());
    _costingsDb[c.id] = c.toJson();
    return c;
  }

  @override
  Future<void> deleteCosting(String id) async {
    _costingsDb.remove(id);
  }

  @override
Future<OperatingExpenseModel?> getLatestOperatingExpense() async {
  if (_expensesDb.isEmpty) return null;
  final sorted = _expensesDb.values
      .map((e) => OperatingExpenseModel.fromJson(e))
      .toList()
    ..sort((a, b) => DateTime(b.periodYear, b.periodMonth)
        .compareTo(DateTime(a.periodYear, a.periodMonth)));
  return sorted.first;
}

  @override
  Future<OperatingExpenseModel> upsertOperatingExpense(
      OperatingExpenseModel expense) async {
    final existing = _expensesDb.values.where((e) =>
        e['period_year'] == expense.periodYear &&
        e['period_month'] == expense.periodMonth).firstOrNull;
    final id = existing != null
        ? OperatingExpenseModel.fromJson(existing).id
        : 'exp-${_idCounter++}';
    final result = expense.copyWith(id: id, updatedAt: DateTime.now());
    _expensesDb[id] = result.toJson();
    return result;
  }

  @override
  Future<List<CostingModel>> getCostingsWithLowMargin(double thresholdPercent) async {
    final all = await getAllCostings();
    return all.where((c) =>
        c.currentSellingPrice > 0 &&
        c.actualProfitMarginPercent < thresholdPercent).toList();
  }

  Future<void> recalculateAllocatedCosts(OperatingExpenseModel expense) async {
    final all = await getAllCostings();
    for (final c in all) {
      await updateCosting(c.copyWith(allocatedOperatingCost: expense.operatingCostPerPortion));
    }
  }
}