// lib/features/costing/models/costing_model.dart
// ignore_for_file: non_constant_identifier_names

import 'dart:math';

/// Model for Direct Costs (direct cost per menu item)
class DirectCostModel {
  final String id;
  final String menuItemId;
  final String menuItemName;
  final double ingredientCost;    // Raw ingredient cost (from inventory)
  final double packagingCost;     // Packaging cost (takeaway, etc.)
  final DateTime createdAt;
  final DateTime updatedAt;

  const DirectCostModel({
    required this.id,
    required this.menuItemId,
    required this.menuItemName,
    required this.ingredientCost,
    required this.packagingCost,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Total direct cost per portion
  double get totalDirectCost => ingredientCost + packagingCost;

  DirectCostModel copyWith({
    String? id,
    String? menuItemId,
    String? menuItemName,
    double? ingredientCost,
    double? packagingCost,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DirectCostModel(
      id: id ?? this.id,
      menuItemId: menuItemId ?? this.menuItemId,
      menuItemName: menuItemName ?? this.menuItemName,
      ingredientCost: ingredientCost ?? this.ingredientCost,
      packagingCost: packagingCost ?? this.packagingCost,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'menu_item_id': menuItemId,
        'menu_item_name': menuItemName,
        'ingredient_cost': ingredientCost,
        'packaging_cost': packagingCost,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory DirectCostModel.fromJson(Map<String, dynamic> json) {
    return DirectCostModel(
      id: json['id'] as String,
      menuItemId: json['menu_item_id'] as String,
      menuItemName: json['menu_item_name'] as String,
      ingredientCost: (json['ingredient_cost'] as num).toDouble(),
      packagingCost: (json['packaging_cost'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Model for Operating Expenses (monthly operating costs)
class OperatingExpenseModel {
  final String id;
  final String periodLabel;      // e.g., "May 2025"
  final int periodYear;
  final int periodMonth;

  // Labor
  final double totalLaborCost;   // Total wages for all staff

  // Utilities
  final double electricityCost;
  final double waterCost;
  final double gasCost;
  final double internetCost;

  // Overhead
  final double rentCost;
  final double otherOverheadCost;

  // Monthly output estimate
  final int estimatedPortionsSoldMonthly; // Estimated total portions sold/month

  final DateTime createdAt;
  final DateTime updatedAt;

  const OperatingExpenseModel({
    required this.id,
    required this.periodLabel,
    required this.periodYear,
    required this.periodMonth,
    required this.totalLaborCost,
    required this.electricityCost,
    required this.waterCost,
    required this.gasCost,
    required this.internetCost,
    required this.rentCost,
    required this.otherOverheadCost,
    required this.estimatedPortionsSoldMonthly,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Total utility cost
  double get totalUtilityCost =>
      electricityCost + waterCost + gasCost + internetCost;

  /// Total overhead cost (rent + other)
  double get totalOverheadCost => rentCost + otherOverheadCost;

  /// Total of all monthly operating costs
  double get totalOperatingExpense =>
      totalLaborCost + totalUtilityCost + totalOverheadCost;

  /// Operating cost per portion (allocated)
  double get operatingCostPerPortion {
    if (estimatedPortionsSoldMonthly <= 0) return 0;
    return totalOperatingExpense / estimatedPortionsSoldMonthly;
  }

  OperatingExpenseModel copyWith({
    String? id,
    String? periodLabel,
    int? periodYear,
    int? periodMonth,
    double? totalLaborCost,
    double? electricityCost,
    double? waterCost,
    double? gasCost,
    double? internetCost,
    double? rentCost,
    double? otherOverheadCost,
    int? estimatedPortionsSoldMonthly,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OperatingExpenseModel(
      id: id ?? this.id,
      periodLabel: periodLabel ?? this.periodLabel,
      periodYear: periodYear ?? this.periodYear,
      periodMonth: periodMonth ?? this.periodMonth,
      totalLaborCost: totalLaborCost ?? this.totalLaborCost,
      electricityCost: electricityCost ?? this.electricityCost,
      waterCost: waterCost ?? this.waterCost,
      gasCost: gasCost ?? this.gasCost,
      internetCost: internetCost ?? this.internetCost,
      rentCost: rentCost ?? this.rentCost,
      otherOverheadCost: otherOverheadCost ?? this.otherOverheadCost,
      estimatedPortionsSoldMonthly:
          estimatedPortionsSoldMonthly ?? this.estimatedPortionsSoldMonthly,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'period_label': periodLabel,
        'period_year': periodYear,
        'period_month': periodMonth,
        'total_labor_cost': totalLaborCost,
        'electricity_cost': electricityCost,
        'water_cost': waterCost,
        'gas_cost': gasCost,
        'internet_cost': internetCost,
        'rent_cost': rentCost,
        'other_overhead_cost': otherOverheadCost,
        'estimated_portions_sold_monthly': estimatedPortionsSoldMonthly,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory OperatingExpenseModel.fromJson(Map<String, dynamic> json) {
    return OperatingExpenseModel(
      id: json['id'] as String,
      periodLabel: json['period_label'] as String,
      periodYear: json['period_year'] as int,
      periodMonth: json['period_month'] as int,
      totalLaborCost: (json['total_labor_cost'] as num).toDouble(),
      electricityCost: (json['electricity_cost'] as num).toDouble(),
      waterCost: (json['water_cost'] as num).toDouble(),
      gasCost: (json['gas_cost'] as num).toDouble(),
      internetCost: (json['internet_cost'] as num).toDouble(),
      rentCost: (json['rent_cost'] as num).toDouble(),
      otherOverheadCost: (json['other_overhead_cost'] as num).toDouble(),
      estimatedPortionsSoldMonthly:
          json['estimated_portions_sold_monthly'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  factory OperatingExpenseModel.empty() {
    final now = DateTime.now();
    return OperatingExpenseModel(
      id: '',
      periodLabel: '${now.month}/${now.year}',
      periodYear: now.year,
      periodMonth: now.month,
      totalLaborCost: 0,
      electricityCost: 0,
      waterCost: 0,
      gasCost: 0,
      internetCost: 0,
      rentCost: 0,
      otherOverheadCost: 0,
      estimatedPortionsSoldMonthly: 1,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// CORE MODEL: CostingModel — Main aggregate that combines all calculations
/// ─────────────────────────────────────────────────────────────────────────────
class CostingModel {
  final String id;
  final String menuItemId;
  final String menuItemName;

  // === COST INPUTS ===
  final double ingredientCost;          // Raw ingredient cost per portion
  final double packagingCost;           // Packaging cost per portion
  final double allocatedOperatingCost;  // Allocated operating cost per portion

  // === TARGET INPUTS ===
  final double targetProfitMarginPercent; // e.g., 30.0 → means 30%
  final double currentSellingPrice;       // Currently used selling price (optional)

  // === BRANCH ===
  final String? branchId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CostingModel({
    required this.id,
    required this.menuItemId,
    required this.menuItemName,
    required this.ingredientCost,
    required this.packagingCost,
    required this.allocatedOperatingCost,
    required this.targetProfitMarginPercent,
    required this.currentSellingPrice,
    this.branchId,
    required this.createdAt,
    required this.updatedAt,
  });

  // ═══════════════════════════════════════
  //  FINANCIAL CALCULATION GETTERS
  // ═══════════════════════════════════════

  /// Total direct cost (ingredients + packaging)
  double get totalDirectCost => ingredientCost + packagingCost;

  /// COGS (Cost of Goods Sold) = Direct Cost + Allocated Operating Cost
  /// This is the actual COGS (Cost of Goods Sold)
  double get hpp => totalDirectCost + allocatedOperatingCost;

  /// Food Cost Percentage = (Ingredient Cost / Selling Price) × 100
  /// Restaurant industry standard: ideally 28–35%
  double get foodCostPercentage {
    if (currentSellingPrice <= 0) return 0;
    return (ingredientCost / currentSellingPrice) * 100;
  }

  /// Recommended Selling Price using the markup formula from COGS
  /// Formula: Selling Price = COGS / (1 - Target Margin)
  double get recommendedSellingPrice {
    final marginDecimal = targetProfitMarginPercent / 100;
    if (marginDecimal >= 1.0) return hpp * 2; // safeguard if margin ≥ 100%
    return hpp / (1 - marginDecimal);
  }

  /// Recommended selling price rounded to the nearest 500 (IDR-friendly)
  double get recommendedSellingPriceRounded {
    final raw = recommendedSellingPrice;
    return (raw / 500).ceil() * 500.0;
  }

  /// Net profit per portion based on the current selling price
  double get profitPerPortion => currentSellingPrice - hpp;

  /// Actual profit margin based on the current selling price (%)
  double get actualProfitMarginPercent {
    if (currentSellingPrice <= 0) return 0;
    return (profitPerPortion / currentSellingPrice) * 100;
  }

  /// Gap: is the current price already sufficient? (positive = already good)
  double get priceGap => currentSellingPrice - recommendedSellingPrice;

  /// Price assessment status
  CostingStatus get pricingStatus {
    if (currentSellingPrice <= 0) return CostingStatus.notSet;
    if (priceGap >= 0) return CostingStatus.healthy;
    if (priceGap >= -500) return CostingStatus.warning;
    return CostingStatus.underpriced;
  }

  /// Break-even point: how many portions must be sold to cover operating costs
  /// Use this for items that contribute to fixed cost
  double breakEvenPortions(double totalFixedCostMonthly) {
    if (profitPerPortion <= 0) return double.infinity;
    return totalFixedCostMonthly / profitPerPortion;
  }

  /// Markup percentage from COGS to selling price
  double get markupPercent {
    if (hpp <= 0) return 0;
    return ((currentSellingPrice - hpp) / hpp) * 100;
  }

  /// Financial health score (0–100), composite formula
  int get financialHealthScore {
    double score = 0;

    // 1. Ideal food cost: 28–35% → score 40
    if (foodCostPercentage >= 20 && foodCostPercentage <= 35) {
      score += 40;
    } else if (foodCostPercentage < 20) {
      score += 30; // too low, possibly a quality concern?
    } else if (foodCostPercentage <= 40) {
      score += 20;
    }

    // 2. Margin ≥ target → score 40
    if (actualProfitMarginPercent >= targetProfitMarginPercent) {
      score += 40;
    } else {
      score += max(
          0, 40 * (actualProfitMarginPercent / targetProfitMarginPercent));
    }

    // 3. Price already set → score 20
    if (currentSellingPrice > 0) score += 20;

    return score.round().clamp(0, 100);
  }

  CostingModel copyWith({
    String? id,
    String? menuItemId,
    String? menuItemName,
    double? ingredientCost,
    double? packagingCost,
    double? allocatedOperatingCost,
    double? targetProfitMarginPercent,
    double? currentSellingPrice,
    String? branchId,
    bool clearBranchId = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CostingModel(
      id: id ?? this.id,
      menuItemId: menuItemId ?? this.menuItemId,
      menuItemName: menuItemName ?? this.menuItemName,
      ingredientCost: ingredientCost ?? this.ingredientCost,
      packagingCost: packagingCost ?? this.packagingCost,
      allocatedOperatingCost:
          allocatedOperatingCost ?? this.allocatedOperatingCost,
      targetProfitMarginPercent:
          targetProfitMarginPercent ?? this.targetProfitMarginPercent,
      currentSellingPrice: currentSellingPrice ?? this.currentSellingPrice,
      branchId: clearBranchId ? null : branchId ?? this.branchId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'menu_item_id': menuItemId,
        'menu_item_name': menuItemName,
        'ingredient_cost': ingredientCost,
        'packaging_cost': packagingCost,
        'allocated_operating_cost': allocatedOperatingCost,
        'target_profit_margin_percent': targetProfitMarginPercent,
        'current_selling_price': currentSellingPrice,
        if (branchId != null) 'branch_id': branchId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory CostingModel.fromJson(Map<String, dynamic> json) {
    return CostingModel(
      id: json['id'] as String,
      menuItemId: json['menu_item_id'] as String,
      menuItemName: json['menu_item_name'] as String,
      ingredientCost: (json['ingredient_cost'] as num).toDouble(),
      packagingCost: (json['packaging_cost'] as num).toDouble(),
      allocatedOperatingCost:
          (json['allocated_operating_cost'] as num).toDouble(),
      targetProfitMarginPercent:
          (json['target_profit_margin_percent'] as num).toDouble(),
      currentSellingPrice: (json['current_selling_price'] as num).toDouble(),
      branchId: json['branch_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  factory CostingModel.empty() {
    final now = DateTime.now();
    return CostingModel(
      id: '',
      menuItemId: '',
      menuItemName: '',
      ingredientCost: 0,
      packagingCost: 0,
      allocatedOperatingCost: 0,
      targetProfitMarginPercent: 30,
      currentSellingPrice: 0,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Menu pricing health status
enum CostingStatus {
  notSet,      // Price not yet set
  healthy,     // Price is already above the recommendation
  warning,     // Price is slightly below the recommendation (<500 IDR)
  underpriced, // Price is far below the recommendation (a loss)
}

extension CostingStatusExtension on CostingStatus {
  String get label {
    switch (this) {
      case CostingStatus.notSet:
        return 'Not Set';
      case CostingStatus.healthy:
        return 'Healthy Price';
      case CostingStatus.warning:
        return 'Needs Review';
      case CostingStatus.underpriced:
        return 'Price Too Low';
    }
  }

  String get emoji {
    switch (this) {
      case CostingStatus.notSet:
        return '⚪';
      case CostingStatus.healthy:
        return '🟢';
      case CostingStatus.warning:
        return '🟡';
      case CostingStatus.underpriced:
        return '🔴';
    }
  }
}

/// Summary model for display on the dashboard / reports
class CostingSummaryModel {
  final int totalMenuItems;
  final double averageFoodCostPercent;
  final double averageProfitMarginPercent;
  final int healthyItems;
  final int warningItems;
  final int underpricedItems;
  final double totalEstimatedMonthlyProfit;
  final double totalEstimatedMonthlyRevenue;

  const CostingSummaryModel({
    required this.totalMenuItems,
    required this.averageFoodCostPercent,
    required this.averageProfitMarginPercent,
    required this.healthyItems,
    required this.warningItems,
    required this.underpricedItems,
    required this.totalEstimatedMonthlyProfit,
    required this.totalEstimatedMonthlyRevenue,
  });

  double get profitabilityScore {
    if (totalMenuItems == 0) return 0;
    return (healthyItems / totalMenuItems) * 100;
  }

  factory CostingSummaryModel.fromCostings(
      List<CostingModel> costings, int estimatedPortionsPerItemMonthly) {
    if (costings.isEmpty) {
      return const CostingSummaryModel(
        totalMenuItems: 0,
        averageFoodCostPercent: 0,
        averageProfitMarginPercent: 0,
        healthyItems: 0,
        warningItems: 0,
        underpricedItems: 0,
        totalEstimatedMonthlyProfit: 0,
        totalEstimatedMonthlyRevenue: 0,
      );
    }

    double totalFoodCost = 0;
    double totalMargin = 0;
    int healthy = 0, warning = 0, underpriced = 0;
    double totalRevenue = 0;
    double totalProfit = 0;

    for (final c in costings) {
      totalFoodCost += c.foodCostPercentage;
      totalMargin += c.actualProfitMarginPercent;

      switch (c.pricingStatus) {
        case CostingStatus.healthy:
          healthy++;
          break;
        case CostingStatus.warning:
          warning++;
          break;
        case CostingStatus.underpriced:
          underpriced++;
          break;
        default:
          break;
      }

      totalRevenue += c.currentSellingPrice * estimatedPortionsPerItemMonthly;
      totalProfit += c.profitPerPortion * estimatedPortionsPerItemMonthly;
    }

    return CostingSummaryModel(
      totalMenuItems: costings.length,
      averageFoodCostPercent: totalFoodCost / costings.length,
      averageProfitMarginPercent: totalMargin / costings.length,
      healthyItems: healthy,
      warningItems: warning,
      underpricedItems: underpriced,
      totalEstimatedMonthlyRevenue: totalRevenue,
      totalEstimatedMonthlyProfit: totalProfit,
    );
  }
}

enum CostingViewState {
  initial,
  loading,
  success,
  error,
}