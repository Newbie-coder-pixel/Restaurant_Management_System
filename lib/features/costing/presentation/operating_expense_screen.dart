// lib/features/costing/presentation/screens/operating_expense_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/costing_providers.dart';
import 'costing_widgets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/staff_shell.dart';

// ✅ RIVERPOD: StatefulWidget → ConsumerStatefulWidget
class OperatingExpenseScreen extends ConsumerStatefulWidget {
  const OperatingExpenseScreen({super.key});

  @override
  ConsumerState<OperatingExpenseScreen> createState() =>
      _OperatingExpenseScreenState();
}

// ✅ RIVERPOD: State<T> → ConsumerState<T>
class _OperatingExpenseScreenState
    extends ConsumerState<OperatingExpenseScreen> {
  final _formKey = GlobalKey<FormState>();

  // Labor
  final _laborCtrl = TextEditingController();

  // Utilities
  final _electricityCtrl = TextEditingController();
  final _waterCtrl = TextEditingController();
  final _gasCtrl = TextEditingController();
  final _internetCtrl = TextEditingController();

  // Overhead
  final _rentCtrl = TextEditingController();
  final _otherCtrl = TextEditingController();

  // Estimate
  final _portionsCtrl = TextEditingController();

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(costingProvider.notifier);
      notifier.init();

      final expense = ref.read(costingProvider).operatingExpense;
      if (expense.id.isNotEmpty) {
        _laborCtrl.text = expense.totalLaborCost.toStringAsFixed(0);
        _electricityCtrl.text = expense.electricityCost.toStringAsFixed(0);
        _waterCtrl.text = expense.waterCost.toStringAsFixed(0);
        _gasCtrl.text = expense.gasCost.toStringAsFixed(0);
        _internetCtrl.text = expense.internetCost.toStringAsFixed(0);
        _rentCtrl.text = expense.rentCost.toStringAsFixed(0);
        _otherCtrl.text = expense.otherOverheadCost.toStringAsFixed(0);
        _portionsCtrl.text = expense.estimatedPortionsSoldMonthly.toString();
        _selectedYear = expense.periodYear;
        _selectedMonth = expense.periodMonth;
        setState(() {});
      } else {
        // No data for this period yet — start from 0, not empty, so the
        // "required" warning is immediately visible and the user knows which
        // fields still need to be filled in.
        _laborCtrl.text = '0';
        _electricityCtrl.text = '0';
        _waterCtrl.text = '0';
        _gasCtrl.text = '0';
        _internetCtrl.text = '0';
        _rentCtrl.text = '0';
        _otherCtrl.text = '0';
        _portionsCtrl.text = '3000';
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _laborCtrl.dispose();
    _electricityCtrl.dispose();
    _waterCtrl.dispose();
    _gasCtrl.dispose();
    _internetCtrl.dispose();
    _rentCtrl.dispose();
    _otherCtrl.dispose();
    _portionsCtrl.dispose();
    super.dispose();
  }

  double _getDouble(TextEditingController ctrl) =>
      double.tryParse(ctrl.text) ?? 0;

  // Shared validator: the field must be filled with a number (0 is allowed,
  // but not empty/negative/invalid) — so the user can't just skip a cost field.
  String? _requiredNonNegative(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = double.tryParse(v);
    if (n == null) return 'Invalid';
    if (n < 0) return 'Cannot be negative';
    return null;
  }

  double get _totalLive =>
      _getDouble(_laborCtrl) +
      _getDouble(_electricityCtrl) +
      _getDouble(_waterCtrl) +
      _getDouble(_gasCtrl) +
      _getDouble(_internetCtrl) +
      _getDouble(_rentCtrl) +
      _getDouble(_otherCtrl);

  double get _costPerPortionLive {
    final portions = int.tryParse(_portionsCtrl.text) ?? 0;
    if (portions <= 0) return 0;
    return _totalLive / portions;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ RIVERPOD: context.read<X>() → ref.read(xProvider.notifier)
    final success = await ref.read(costingProvider.notifier).saveOperatingExpense(
      year: _selectedYear,
      month: _selectedMonth,
      laborCost: _getDouble(_laborCtrl),
      electricityCost: _getDouble(_electricityCtrl),
      waterCost: _getDouble(_waterCtrl),
      gasCost: _getDouble(_gasCtrl),
      internetCost: _getDouble(_internetCtrl),
      rentCost: _getDouble(_rentCtrl),
      otherCost: _getDouble(_otherCtrl),
      estimatedPortions: int.tryParse(_portionsCtrl.text) ?? 1,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              '✅ Operating expense saved and reallocated successfully'),
          backgroundColor: AppColors.available,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(costingProvider).isSaving;
    final notifier = ref.watch(costingProvider.notifier);

    return StaffShell(
      pageTitle: 'Operating Expenses',
      activeRoute: AppRoutes.operatingExpense,
      topBarActions: [
        if (notifier.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: notifier.selectedBranchId,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down,
                      size: 16, color: AppColors.textSecondary),
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Branches',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
                    ...notifier.branches.map((b) => DropdownMenuItem<String?>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
                  ],
                  onChanged: (val) => notifier.selectBranch(val),
                ),
              ),
            ),
          ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Operating Expenses',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 30,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('Monthly labor, utility, and overhead cost allocation.',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),

              LayoutBuilder(builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 980;
                final left = _buildFormColumn();
                final right = _buildSummaryColumn(isSaving);

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: left),
                      const SizedBox(width: 20),
                      SizedBox(width: 340, child: right),
                    ],
                  );
                }
                return Column(children: [left, const SizedBox(height: 20), right]);
              }),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Period
        _SectionCard(
          title: 'Reporting Period',
          icon: Icons.calendar_month_rounded,
          color: AppColors.primary,
          child: _PeriodSelector(
            year: _selectedYear,
            month: _selectedMonth,
            onChanged: (y, m) => setState(() {
              _selectedYear = y;
              _selectedMonth = m;
            }),
          ),
        ),
        const SizedBox(height: 20),

        // Labor
        _SectionCard(
          title: 'Labor Cost',
          icon: Icons.people_rounded,
          color: AppColors.primary,
          child: CurrencyInputField(
            label: 'Total Wages for All Staff / month',
            hint: '15000000',
            controller: _laborCtrl,
            helperText: 'Includes base salary + allowances',
            accentColor: AppColors.primary,
            isRequired: true,
            onChanged: (_) => setState(() {}),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final n = double.tryParse(v);
              if (n == null) return 'Invalid';
              if (n <= 0) return 'Must be greater than 0';
              return null;
            },
          ),
        ),
        const SizedBox(height: 20),

        // Utilities
        _SectionCard(
          title: 'Utility Cost',
          icon: Icons.bolt_rounded,
          color: AppColors.accentOrange,
          child: Column(
            children: [
              CurrencyInputField(
                label: 'Electricity',
                hint: '2500000',
                controller: _electricityCtrl,
                accentColor: AppColors.accentOrange,
                isRequired: true,
                onChanged: (_) => setState(() {}),
                validator: _requiredNonNegative,
              ),
              const SizedBox(height: 10),
              CurrencyInputField(
                label: 'Water (Utility Company)',
                hint: '500000',
                controller: _waterCtrl,
                accentColor: AppColors.accentOrange,
                isRequired: true,
                onChanged: (_) => setState(() {}),
                validator: _requiredNonNegative,
              ),
              const SizedBox(height: 10),
              CurrencyInputField(
                label: 'Gas / LPG',
                hint: '750000',
                controller: _gasCtrl,
                accentColor: AppColors.accentOrange,
                isRequired: true,
                onChanged: (_) => setState(() {}),
                validator: _requiredNonNegative,
              ),
              const SizedBox(height: 10),
              CurrencyInputField(
                label: 'Internet / Phone',
                hint: '350000',
                controller: _internetCtrl,
                accentColor: AppColors.accentOrange,
                isRequired: true,
                onChanged: (_) => setState(() {}),
                validator: _requiredNonNegative,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Overhead
        _SectionCard(
          title: 'Rent & Overhead',
          icon: Icons.location_city_rounded,
          color: AppColors.accent,
          child: Column(
            children: [
              CurrencyInputField(
                label: 'Rent Cost / month',
                hint: '8000000',
                controller: _rentCtrl,
                accentColor: AppColors.accent,
                isRequired: true,
                onChanged: (_) => setState(() {}),
                validator: _requiredNonNegative,
              ),
              const SizedBox(height: 10),
              CurrencyInputField(
                label: 'Other Overhead (insurance, licensing, etc.)',
                hint: '1000000',
                controller: _otherCtrl,
                accentColor: AppColors.accent,
                isRequired: true,
                onChanged: (_) => setState(() {}),
                validator: _requiredNonNegative,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Estimated portions
        _SectionCard(
          title: 'Sales Estimate',
          icon: Icons.bar_chart_rounded,
          color: AppColors.available,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estimated Total Portions Sold / month',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _portionsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autovalidateMode: AutovalidateMode.always,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: '3000',
                  helperText: 'Used to calculate the cost allocation per portion',
                  helperStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
                  suffixText: 'portions',
                  suffixStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: const BorderSide(color: AppColors.available, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) {
                    return 'Estimated portions must be > 0';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryColumn(bool isSaving) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Expense Summary',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                _TotalLine('TOTAL OPERATING EXPENSE / MONTH', formatIdr(_totalLive),
                    AppColors.textPrimary, true),
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 10),
                _TotalLine('ALLOCATED PER PORTION', formatIdr(_costPerPortionLive),
                    AppColors.primary, true),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: isSaving ? null : _save,
            icon: isSaving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(
              isSaving ? 'Saving & Allocating...' : 'SAVE & ALLOCATE',
              style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.4)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Saving reallocates this cost across every menu item\'s costing.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CostingSectionHeader(title: title, icon: icon, color: color),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _TotalLine(this.label, this.value, this.color, this.bold);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'Poppins',
                color: AppColors.textSecondary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                fontSize: 10, letterSpacing: 0.4)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontFamily: 'Poppins',
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: bold ? 20 : 13)),
      ],
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final int year;
  final int month;
  final void Function(int year, int month) onChanged;

  const _PeriodSelector({
    required this.year,
    required this.month,
    required this.onChanged,
  });

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Month',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: month,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary),
                items: List.generate(
                  12,
                  (i) => DropdownMenuItem(
                      value: i + 1, child: Text(_months[i])),
                ),
                onChanged: (v) => onChanged(year, v!),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide.none),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Year',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: year,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary),
                items: List.generate(5, (i) {
                  final y = DateTime.now().year - 2 + i;
                  return DropdownMenuItem(value: y, child: Text('$y'));
                }),
                onChanged: (v) => onChanged(v!, month),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide.none),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
