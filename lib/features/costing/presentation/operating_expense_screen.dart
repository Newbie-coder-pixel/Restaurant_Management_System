// lib/features/costing/presentation/screens/operating_expense_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/costing_model.dart';
import '../providers/costing_providers.dart';
import 'costing_widgets.dart';

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

  // Estimasi
  final _portionsCtrl = TextEditingController();

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ RIVERPOD: context.read<X>() → ref.read(xProvider)
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
        _portionsCtrl.text = '3000';
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
              '✅ Biaya operasional berhasil disimpan dan dialokasikan ulang'),
          backgroundColor: const Color(0xFF2E7D32),
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
    final theme = Theme.of(context);
    // ✅ RIVERPOD: Consumer<X> wrapper di tombol save → ref.watch di build
    final isSaving = ref.watch(costingProvider).isSaving;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Biaya Operasional Bulanan',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Periode
              _PeriodSelector(
                year: _selectedYear,
                month: _selectedMonth,
                onChanged: (y, m) => setState(() {
                  _selectedYear = y;
                  _selectedMonth = m;
                }),
              ),
              const SizedBox(height: 20),

              // Labor
              const CostingSectionHeader(
                title: 'Biaya Tenaga Kerja (Labor)',
                icon: Icons.people_rounded,
                color: Color(0xFF1565C0),
              ),
              const SizedBox(height: 12),
              CurrencyInputField(
                label: 'Total Gaji Semua Staf / bulan',
                hint: '15000000',
                controller: _laborCtrl,
                helperText: 'Termasuk gaji pokok + tunjangan',
                accentColor: const Color(0xFF1565C0),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              // Utilities
              const CostingSectionHeader(
                title: 'Biaya Utilitas',
                icon: Icons.bolt_rounded,
                color: Color(0xFFF57F17),
              ),
              const SizedBox(height: 12),
              CurrencyInputField(
                label: 'Listrik',
                hint: '2500000',
                controller: _electricityCtrl,
                accentColor: const Color(0xFFF57F17),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              CurrencyInputField(
                label: 'Air (PDAM)',
                hint: '500000',
                controller: _waterCtrl,
                accentColor: const Color(0xFFF57F17),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              CurrencyInputField(
                label: 'Gas / LPG',
                hint: '750000',
                controller: _gasCtrl,
                accentColor: const Color(0xFFF57F17),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              CurrencyInputField(
                label: 'Internet / Telepon',
                hint: '350000',
                controller: _internetCtrl,
                accentColor: const Color(0xFFF57F17),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              // Overhead
              const CostingSectionHeader(
                title: 'Sewa & Overhead',
                icon: Icons.location_city_rounded,
                color: Color(0xFF6A1B9A),
              ),
              const SizedBox(height: 12),
              CurrencyInputField(
                label: 'Biaya Sewa Tempat / bulan',
                hint: '8000000',
                controller: _rentCtrl,
                accentColor: const Color(0xFF6A1B9A),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              CurrencyInputField(
                label: 'Overhead Lainnya (asuransi, perizinan, dll)',
                hint: '1000000',
                controller: _otherCtrl,
                accentColor: const Color(0xFF6A1B9A),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              // Estimasi porsi
              const CostingSectionHeader(
                title: 'Estimasi Penjualan',
                icon: Icons.bar_chart_rounded,
                color: Color(0xFF2E7D32),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimasi Total Porsi Terjual / bulan',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _portionsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '3000',
                      helperText:
                          'Digunakan untuk menghitung alokasi biaya per porsi',
                      suffixText: 'porsi',
                      filled: true,
                      fillColor:
                          theme.colorScheme.surfaceVariant.withOpacity(0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFF2E7D32), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n <= 0) {
                        return 'Estimasi porsi harus > 0';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Live total preview
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _TotalLine(
                        'Total Biaya Operasional / bulan',
                        formatIdr(_totalLive),
                        theme.colorScheme.onInverseSurface,
                        true),
                    const SizedBox(height: 4),
                    _TotalLine(
                        '⚡ Alokasi per porsi',
                        formatIdr(_costPerPortionLive),
                        const Color(0xFF81C784),
                        true),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ✅ RIVERPOD: Consumer wrapper dihapus — isSaving sudah di-watch di atas
              FilledButton.icon(
                onPressed: isSaving ? null : _save,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(isSaving
                    ? 'Menyimpan & Mengalokasikan...'
                    : 'Simpan & Alokasikan ke Semua Menu'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                fontSize: 13)),
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: bold ? 15 : 13)),
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
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bulan',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: month,
                items: List.generate(
                  12,
                  (i) => DropdownMenuItem(
                      value: i + 1, child: Text(_months[i])),
                ),
                onChanged: (v) => onChanged(year, v!),
                decoration: InputDecoration(
                  filled: true,
                  fillColor:
                      theme.colorScheme.surfaceVariant.withOpacity(0.4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
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
              Text('Tahun',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: year,
                items: List.generate(5, (i) {
                  final y = DateTime.now().year - 2 + i;
                  return DropdownMenuItem(value: y, child: Text('$y'));
                }),
                onChanged: (v) => onChanged(v!, month),
                decoration: InputDecoration(
                  filled: true,
                  fillColor:
                      theme.colorScheme.surfaceVariant.withOpacity(0.4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
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