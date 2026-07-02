// lib/features/costing/providers/costing_providers.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/costing_model.dart';
import '../services/costing_services.dart';
import '../../../core/models/staff_role.dart';
import '../../auth/providers/auth_provider.dart';
import '../../menu/providers/menu_provider.dart';
import '../../inventory/providers/inventory_provider.dart';

// ─── Service Provider ──────────────────────────────────────────────────────
final costingServiceProvider = Provider<CostingService>((ref) {
  return CostingService();
});

// ─── State Notifier ────────────────────────────────────────────────────────
final costingProvider =
    ChangeNotifierProvider<CostingNotifier>((ref) {
  final service = ref.watch(costingServiceProvider);
  return CostingNotifier(service: service, ref: ref);
});

// ─── Notifier (wrapper tipis di atas CostingProvider lama) ────────────────
class CostingNotifier extends ChangeNotifier {
  final ICostingService _service;
  final Ref _ref;

  CostingNotifier({required ICostingService service, required Ref ref})
      : _service = service,
        _ref = ref;

  // ── State ──────────────────────────────────────────────────────────────
  CostingViewState _state = CostingViewState.initial;
  String _errorMessage = '';
  List<CostingModel> _costings = [];
  OperatingExpenseModel _operatingExpense = OperatingExpenseModel.empty();
  CostingModel _activeCosting = CostingModel.empty();
  CostingSummaryModel _summary = CostingSummaryModel.fromCostings([], 100);
  bool _isSaving = false;

  // ── Branch filter state (sama seperti reports) ─────────────────────────
  bool _isSuperAdmin = false;
  String? _branchId;          // branch user yang login (non-superadmin)
  String? _selectedBranchId; // branch yang dipilih superadmin di dropdown
  List<Map<String, dynamic>> _branches = [];
  bool _initialized = false;

  double _liveIngredientCost = 0;
  double _livePackagingCost = 0;
  double _liveAllocatedOpCost = 0;
  double _liveTargetMargin = 30;
  double _liveCurrentPrice = 0;

  // ── Getters ────────────────────────────────────────────────────────────
  CostingViewState get state => _state;
  String get errorMessage => _errorMessage;
  List<CostingModel> get costings => _costings;
  OperatingExpenseModel get operatingExpense => _operatingExpense;
  CostingModel get activeCosting => _activeCosting;
  CostingSummaryModel get summary => _summary;
  bool get isSaving => _isSaving;
  bool get isLoading => _state == CostingViewState.loading;

  // Branch getters
  bool get isSuperAdmin => _isSuperAdmin;
  String? get selectedBranchId => _selectedBranchId;
  List<Map<String, dynamic>> get branches => _branches;

  CostingModel get liveCalcResult => CostingModel(
        id: _activeCosting.id,
        menuItemId: _activeCosting.menuItemId,
        menuItemName: _activeCosting.menuItemName,
        ingredientCost: _liveIngredientCost,
        packagingCost: _livePackagingCost,
        allocatedOperatingCost: _liveAllocatedOpCost,
        targetProfitMarginPercent: _liveTargetMargin,
        currentSellingPrice: _liveCurrentPrice,
        createdAt: _activeCosting.createdAt,
        updatedAt: DateTime.now(),
      );

  // ── Init (sama seperti reports) ────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final staff = _ref.read(currentStaffProvider);
    if (staff == null) {
      await Future.delayed(const Duration(milliseconds: 300));
      final retryStaff = _ref.read(currentStaffProvider);
      if (retryStaff == null) return;
      _isSuperAdmin = retryStaff.role == StaffRole.superadmin;
      _branchId = retryStaff.role == StaffRole.superadmin ? null : retryStaff.branchId;
    } else {
      _isSuperAdmin = staff.role == StaffRole.superadmin;
      _branchId = staff.role == StaffRole.superadmin ? null : staff.branchId;
    }

    await _loadBranches();
    await loadAll();
  }

  // ── Branch filter ──────────────────────────────────────────────────────
  Future<void> selectBranch(String? branchId) async {
    _selectedBranchId = branchId;
    notifyListeners();
    await loadAll();
  }

  Future<void> _loadBranches() async {
    if (!_isSuperAdmin) return;
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .order('name');
      _branches = List<Map<String, dynamic>>.from(res);
      notifyListeners();
    } catch (e) {
      debugPrint('_loadBranches error: $e');
    }
  }

  // ── Effective branch untuk query ───────────────────────────────────────
  String? get _effectiveBranchId =>
      _isSuperAdmin ? _selectedBranchId : _branchId;

  /// Branch aktif saat ini (dipakai UI untuk filter picker menu).
  String? get effectiveBranchId => _effectiveBranchId;

  /// Hitung total biaya bahan baku (ingredient cost) per porsi untuk satu
  /// menu item, berdasarkan resep (menu_ingredients) × harga bahan TERKINI
  /// dari inventory (bukan harga yang tersimpan lama di resep), supaya HPP
  /// selalu mengikuti harga bahan baku terbaru.
  ///
  /// Ini adalah titik koneksi utama Menu ↔ Inventory ↔ Costing.
  Future<double> computeIngredientCostForMenu(String menuItemId) async {
    final branchId = _effectiveBranchId;
    if (branchId == null || menuItemId.isEmpty) return 0;

    final menuService = _ref.read(menuServiceProvider);
    final inventoryService = _ref.read(inventoryServiceProvider);

    final ingredients = await menuService.fetchIngredients(menuItemId);
    if (ingredients.isEmpty) return 0;

    final currentStock = await inventoryService.fetchInventoryItems(
      branchId: branchId,
    );
    final costByName = {
      for (final item in currentStock) item.name.trim().toLowerCase(): item.costPerUnit,
    };

    double total = 0;
    for (final ing in ingredients) {
      final liveCost = costByName[ing.inventoryItemName.trim().toLowerCase()];
      // Prioritaskan harga inventory TERKINI; fallback ke harga tersimpan di
      // resep kalau bahan itu belum/tidak ada di data inventory hari ini.
      final unitCost = liveCost ?? ing.costPerUnit;
      total += ing.quantity * unitCost;
    }
    return total;
  }

  // ── Load ───────────────────────────────────────────────────────────────
  Future<void> loadAll() async {
    _setState(CostingViewState.loading);
    try {
      final results = await Future.wait([
        _service.getAllCostings(branchId: _effectiveBranchId),
        _service.getLatestOperatingExpense(branchId: _effectiveBranchId),
      ]);
      _costings = results[0] as List<CostingModel>;
      _operatingExpense =
          (results[1] as OperatingExpenseModel?) ?? OperatingExpenseModel.empty();
      _recalculateSummary();
      _setState(CostingViewState.success);
    } catch (e) {
      _setError('Gagal memuat data: $e');
    }
  }

  Future<void> loadCostingForMenu(String menuItemId) async {
    try {
      final costing = await _service.getCostingByMenuItemId(menuItemId);
      setActiveCosting(costing ?? CostingModel.empty());
    } catch (e) {
      _setError('Gagal memuat costing: $e');
    }
  }

  // ── CRUD ───────────────────────────────────────────────────────────────
  Future<bool> saveCosting({
    required String menuItemId,
    required String menuItemName,
    required double ingredientCost,
    required double packagingCost,
    required double targetMarginPercent,
    required double currentSellingPrice,
  }) async {
    _isSaving = true;
    notifyListeners();
    try {
      final allocatedCost = _operatingExpense.operatingCostPerPortion;
      final effectiveBranchId = _isSuperAdmin ? _selectedBranchId : _branchId;
      final existing =
          _costings.where((c) => c.menuItemId == menuItemId).firstOrNull;
      CostingModel saved;
      if (existing != null) {
        saved = await _service.updateCosting(existing.copyWith(
          menuItemName: menuItemName,
          ingredientCost: ingredientCost,
          packagingCost: packagingCost,
          allocatedOperatingCost: allocatedCost,
          targetProfitMarginPercent: targetMarginPercent,
          currentSellingPrice: currentSellingPrice,
          branchId: effectiveBranchId,
        ));
        final idx = _costings.indexWhere((c) => c.id == saved.id);
        if (idx != -1) _costings[idx] = saved;
      } else {
        final now = DateTime.now();
        saved = await _service.createCosting(CostingModel(
          id: '',
          menuItemId: menuItemId,
          menuItemName: menuItemName,
          ingredientCost: ingredientCost,
          packagingCost: packagingCost,
          allocatedOperatingCost: allocatedCost,
          targetProfitMarginPercent: targetMarginPercent,
          currentSellingPrice: currentSellingPrice,
          branchId: effectiveBranchId,
          createdAt: now,
          updatedAt: now,
        ));
        _costings.insert(0, saved);
      }
      _activeCosting = saved;
      _recalculateSummary();
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isSaving = false;
      _setError('Gagal menyimpan: $e');
      return false;
    }
  }

  Future<bool> deleteCosting(String id) async {
    try {
      await _service.deleteCosting(id);
      _costings.removeWhere((c) => c.id == id);
      _recalculateSummary();
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Gagal menghapus: $e');
      return false;
    }
  }

  Future<bool> saveOperatingExpense({
    required int year,
    required int month,
    required double laborCost,
    required double electricityCost,
    required double waterCost,
    required double gasCost,
    required double internetCost,
    required double rentCost,
    required double otherCost,
    required int estimatedPortions,
  }) async {
    _isSaving = true;
    notifyListeners();
    try {
      final expense = OperatingExpenseModel(
        id: _operatingExpense.id,
        periodLabel: '$month/$year',
        periodYear: year,
        periodMonth: month,
        totalLaborCost: laborCost,
        electricityCost: electricityCost,
        waterCost: waterCost,
        gasCost: gasCost,
        internetCost: internetCost,
        rentCost: rentCost,
        otherOverheadCost: otherCost,
        estimatedPortionsSoldMonthly: estimatedPortions,
        createdAt: _operatingExpense.createdAt.isAfter(DateTime(2000))
            ? _operatingExpense.createdAt
            : DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _operatingExpense = await _service.upsertOperatingExpense(expense);
      await _service.recalculateAllocatedCosts(_operatingExpense);
      _costings = await _service.getAllCostings();
      _recalculateSummary();
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isSaving = false;
      _setError('Gagal menyimpan biaya operasional: $e');
      return false;
    }
  }

  // ── Live Calculator ────────────────────────────────────────────────────
  void updateLiveIngredientCost(double v) { _liveIngredientCost = v; notifyListeners(); }
  void updateLivePackagingCost(double v) { _livePackagingCost = v; notifyListeners(); }
  void updateLiveAllocatedOpCost(double v) { _liveAllocatedOpCost = v; notifyListeners(); }
  void updateLiveTargetMargin(double v) { _liveTargetMargin = v.clamp(1, 99); notifyListeners(); }
  void updateLiveCurrentPrice(double v) { _liveCurrentPrice = v; notifyListeners(); }
  void autoFillAllocatedCost() { _liveAllocatedOpCost = _operatingExpense.operatingCostPerPortion; notifyListeners(); }

  void setActiveCosting(CostingModel costing) {
    _activeCosting = costing;
    _liveIngredientCost = costing.ingredientCost;
    _livePackagingCost = costing.packagingCost;
    _liveAllocatedOpCost = costing.allocatedOperatingCost;
    _liveTargetMargin = costing.targetProfitMarginPercent;
    _liveCurrentPrice = costing.currentSellingPrice;
    notifyListeners();
  }

  void clearActiveCosting() {
    _activeCosting = CostingModel.empty();
    _liveIngredientCost = 0;
    _livePackagingCost = 0;
    _liveAllocatedOpCost = _operatingExpense.operatingCostPerPortion;
    _liveTargetMargin = 30;
    _liveCurrentPrice = 0;
    notifyListeners();
  }

  // ── Filter ─────────────────────────────────────────────────────────────
  List<CostingModel> getFilteredCostings({
    CostingStatus? filterByStatus,
    String? searchQuery,
    bool sortByMarginAsc = false,
  }) {
    var list = List<CostingModel>.from(_costings);
    if (filterByStatus != null) {
      list = list.where((c) => c.pricingStatus == filterByStatus).toList();
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      list = list
          .where((c) =>
              c.menuItemName.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }
    if (sortByMarginAsc) {
      list.sort((a, b) =>
          a.actualProfitMarginPercent.compareTo(b.actualProfitMarginPercent));
    }
    return list;
  }

  Map<String, double> getProfitabilityMap() => {
        for (final c in _costings) c.menuItemId: c.actualProfitMarginPercent
      };

  Map<String, dynamic> exportForReports() => {
        'summary': {
          'total_items': _summary.totalMenuItems,
          'avg_food_cost_pct': _summary.averageFoodCostPercent,
          'avg_margin_pct': _summary.averageProfitMarginPercent,
          'healthy_items': _summary.healthyItems,
          'underpriced_items': _summary.underpricedItems,
          'estimated_monthly_revenue': _summary.totalEstimatedMonthlyRevenue,
          'estimated_monthly_profit': _summary.totalEstimatedMonthlyProfit,
        },
        'operating_expense': _operatingExpense.toJson(),
        'items': _costings
            .map((c) => {
                  'menu_item_id': c.menuItemId,
                  'menu_item_name': c.menuItemName,
                  'hpp': c.hpp,
                  'recommended_price': c.recommendedSellingPrice,
                  'current_price': c.currentSellingPrice,
                  'margin_pct': c.actualProfitMarginPercent,
                  'food_cost_pct': c.foodCostPercentage,
                  'status': c.pricingStatus.name,
                })
            .toList(),
      };

  // ── Helpers ────────────────────────────────────────────────────────────
  void _recalculateSummary() =>
      _summary = CostingSummaryModel.fromCostings(_costings, 100);

  void _setState(CostingViewState s) { _state = s; notifyListeners(); }

  void _setError(String msg) {
    _errorMessage = msg;
    _state = CostingViewState.error;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = '';
    if (_state == CostingViewState.error) _state = CostingViewState.success;
    notifyListeners();
  }
}