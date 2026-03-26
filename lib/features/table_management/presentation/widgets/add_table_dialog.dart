import 'package:flutter/material.dart';
import '../../../../shared/models/table_model.dart';
import '../../../../core/theme/app_theme.dart';

class AddTableDialog extends StatefulWidget {
  const AddTableDialog({super.key});
  @override
  State<AddTableDialog> createState() => _AddTableDialogState();
}

class _AddTableDialogState extends State<AddTableDialog> {
  final _numberCtrl = TextEditingController();
  int _capacity = 4;
  TableShape _shape = TableShape.square;

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah Meja Baru',
        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _numberCtrl,
          decoration: const InputDecoration(
            labelText: 'Nomor Meja', hintText: 'contoh: A1, VIP-1'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Text('Kapasitas:', style: TextStyle(fontFamily: 'Poppins')),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () {
              if (_capacity > 1) setState(() => _capacity--);
            },
          ),
          Text('$_capacity',
            style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 18)),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => setState(() => _capacity++),
          ),
        ]),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Bentuk:', style: TextStyle(fontFamily: 'Poppins')),
        ),
        const SizedBox(height: 8),
        Row(
          children: TableShape.values.map((s) {
            final selected = _shape == s;
            return GestureDetector(
              onTap: () => setState(() => _shape = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border),
                ),
                child: Text(s.name,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  )),
              ),
            );
          }).toList(),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_numberCtrl.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'number': _numberCtrl.text.trim(),
              'capacity': _capacity,
              'shape': _shape.name,
            });
          },
          child: const Text('Tambah'),
        ),
      ],
    );
  }
}