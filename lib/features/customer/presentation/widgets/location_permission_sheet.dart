// lib/features/customer/presentation/widgets/location_permission_sheet.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Bottom sheet minta izin lokasi — gaya Shopee/Tokopedia
/// Panggil dengan: LocationPermissionSheet.show(context, onGranted: ...)
class LocationPermissionSheet extends StatelessWidget {
  final VoidCallback onGranted;
  final VoidCallback? onDenied;

  const LocationPermissionSheet({
    super.key,
    required this.onGranted,
    this.onDenied,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onGranted,
    VoidCallback? onDenied,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (_) => LocationPermissionSheet(
        onGranted: onGranted,
        onDenied: onDenied,
      ),
    );
  }

  Future<void> _handleAllow(BuildContext context) async {
    Navigator.of(context).pop();

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      // Arahkan ke settings
      await Geolocator.openAppSettings();
      return;
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      onGranted();
    } else {
      onDenied?.call();
    }
  }

  void _handleDeny(BuildContext context) {
    Navigator.of(context).pop();
    onDenied?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Ilustrasi lokasi
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              size: 40,
              color: Color(0xFFFF6B00),
            ),
          ),
          const SizedBox(height: 20),

          // Judul
          const Text(
            'Izinkan Akses Lokasi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 10),

          // Deskripsi
          Text(
            'Kami akan menggunakan lokasi Anda untuk menampilkan cabang restoran terdekat dan memudahkan pemesanan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),

          // Keuntungan fitur
          _BenefitRow(
            icon: Icons.store_rounded,
            text: 'Temukan cabang terdekat dari Anda',
          ),
          _BenefitRow(
            icon: Icons.delivery_dining_rounded,
            text: 'Estimasi waktu pengiriman lebih akurat',
          ),
          _BenefitRow(
            icon: Icons.navigation_rounded,
            text: 'Navigasi langsung ke restoran',
          ),

          const SizedBox(height: 24),

          // Tombol Izinkan
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _handleAllow(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Izinkan Akses Lokasi',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Tombol Lewati
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => _handleDeny(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Lewati',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Privacy note
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(
                  'Lokasi Anda hanya digunakan saat aplikasi dibuka',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFFFF6B00)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF424242)),
            ),
          ),
        ],
      ),
    );
  }
}