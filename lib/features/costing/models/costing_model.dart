// lib/features/costing/models/costing_model.dart
// ignore_for_file: non_constant_identifier_names

import 'dart:math';

/// Model untuk Direct Costs (Biaya Langsung per menu item)
class DirectCostModel {
  final String id;
  final String menuItemId;
  final String menuItemName;
  final double ingredientCost;    // Biaya bahan baku (dari inventory)
  final double packagingCost;     // Biaya kemasan (takeaway, dll.)
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

  /// Total biaya langsung per porsi
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

/// Model untuk Operating Expenses (Biaya Operasional Bulanan)
class OperatingExpenseModel {
  final String id;
  final String periodLabel;      // e.g., "Mei 2025"
  final int periodYear;
  final int periodMonth;

  // Labor
  final double totalLaborCost;   // Total gaji semua staf

  // Utilities
  final double electricityCost;
  final double waterCost;
  final double gasCost;
  final double internetCost;

  // Overhead
  final double rentCost;
  final double otherOverheadCost;

  // Estimasi output bulanan
  final int estimatedPortionsSoldMonthly; // Estimasi total porsi terjual/bulan

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

  /// Total biaya utilitas
  double get totalUtilityCost =>
      electricityCost + waterCost + gasCost + internetCost;

  /// Total biaya overhead (sewa + lain-lain)
  double get totalOverheadCost => rentCost + otherOverheadCost;

  /// Total semua biaya operasional bulanan
  double get totalOperatingExpense =>
      totalLaborCost + totalUtilityCost + totalOverheadCost;

  /// Biaya operasional per porsi (dialokasikan)
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
/// CORE MODEL: CostingModel — Agregat utama yang menggabungkan semua kalkulasi
/// ─────────────────────────────────────────────────────────────────────────────
class CostingModel {
  final String id;
  final String menuItemId;
  final String menuItemName;

  // === INPUT BIAYA ===
  final double ingredientCost;          // Biaya bahan baku per porsi
  final double packagingCost;           // Biaya kemasan per porsi
  final double allocatedOperatingCost;  // Biaya operasional dialokasikan per porsi

  // === INPUT TARGET ===
  final double targetProfitMarginPercent; // e.g., 30.0 → berarti 30%
  final double currentSellingPrice;       // Harga jual yang sedang dipakai (opsional)

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
  //  GETTER KALKULASI KEUANGAN
  // ═══════════════════════════════════════

  /// Biaya Langsung total (bahan baku + kemasan)
  double get totalDirectCost => ingredientCost + packagingCost;

  /// HPP (Harga Pokok Penjualan) = Biaya Langsung + Biaya Operasional Dialokasikan
  /// Ini adalah COGS (Cost of Goods Sold) yang sesungguhnya
  double get hpp => totalDirectCost + allocatedOperatingCost;

  /// Food Cost Percentage = (Biaya Bahan Baku / Harga Jual) × 100
  /// Standar industri restoran: idealnya 28–35%
  double get foodCostPercentage {
    if (currentSellingPrice <= 0) return 0;
    return (ingredientCost / currentSellingPrice) * 100;
  }

  /// Rekomendasi Harga Jual menggunakan rumus markup dari HPP
  /// Formula: Harga Jual = HPP / (1 - Target Margin)
  double get recommendedSellingPrice {
    final marginDecimal = targetProfitMarginPercent / 100;
    if (marginDecimal >= 1.0) return hpp * 2; // safeguard jika margin ≥ 100%
    return hpp / (1 - marginDecimal);
  }

  /// Rekomendasi harga jual yang sudah dibulatkan ke kelipatan 500 (IDR-friendly)
  double get recommendedSellingPriceRounded {
    final raw = recommendedSellingPrice;
    return (raw / 500).ceil() * 500.0;
  }

  /// Keuntungan bersih per porsi berdasarkan harga jual saat ini
  double get profitPerPortion => currentSellingPrice - hpp;

  /// Margin profit aktual berdasarkan harga jual saat ini (%)
  double get actualProfitMarginPercent {
    if (currentSellingPrice <= 0) return 0;
    return (profitPerPortion / currentSellingPrice) * 100;
  }

  /// Selisih: apakah harga saat ini sudah cukup? (positif = sudah baik)
  double get priceGap => currentSellingPrice - recommendedSellingPrice;

  /// Status penilaian harga
  CostingStatus get pricingStatus {
    if (currentSellingPrice <= 0) return CostingStatus.notSet;
    if (priceGap >= 0) return CostingStatus.healthy;
    if (priceGap >= -500) return CostingStatus.warning;
    return CostingStatus.underpriced;
  }

  /// Break-even point: berapa porsi yang harus terjual untuk balik modal operasional
  /// Gunakan ini untuk item yang berkontribusi pada fixed cost
  double breakEvenPortions(double totalFixedCostMonthly) {
    if (profitPerPortion <= 0) return double.infinity;
    return totalFixedCostMonthly / profitPerPortion;
  }

  /// Markup percentage dari HPP ke harga jual
  double get markupPercent {
    if (hpp <= 0) return 0;
    return ((currentSellingPrice - hpp) / hpp) * 100;
  }

  /// Skor kesehatan finansial (0–100), formula composite
  int get financialHealthScore {
    double score = 0;

    // 1. Food cost ideal: 28–35% → skor 40
    if (foodCostPercentage >= 20 && foodCostPercentage <= 35) {
      score += 40;
    } else if (foodCostPercentage < 20) {
      score += 30; // terlalu rendah, mungkin kualitas?
    } else if (foodCostPercentage <= 40) {
      score += 20;
    }

    // 2. Margin ≥ target → skor 40
    if (actualProfitMarginPercent >= targetProfitMarginPercent) {
      score += 40;
    } else {
      score += max(
          0, 40 * (actualProfitMarginPercent / targetProfitMarginPercent));
    }

    // 3. Harga sudah diset → skor 20
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

/// Status kesehatan harga menu
enum CostingStatus {
  notSet,      // Harga belum diisi
  healthy,     // Harga sudah di atas rekomendasi
  warning,     // Harga sedikit di bawah rekomendasi (<500 IDR)
  underpriced, // Harga jauh di bawah rekomendasi (rugi)
}

extension CostingStatusExtension on CostingStatus {
  String get label {
    switch (this) {
      case CostingStatus.notSet:
        return 'Belum Diset';
      case CostingStatus.healthy:
        return 'Harga Sehat';
      case CostingStatus.warning:
        return 'Perlu Review';
      case CostingStatus.underpriced:
        return 'Harga Terlalu Rendah';
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

/// Model ringkasan untuk ditampilkan di dashboard / laporan
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