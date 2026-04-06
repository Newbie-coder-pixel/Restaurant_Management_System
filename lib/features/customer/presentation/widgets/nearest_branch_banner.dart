// lib/features/customer/presentation/widgets/nearest_branch_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/location_service.dart';
import 'location_permission_sheet.dart';

// ─── Supabase branches provider ──────────────────────────────────────────────

/// Fetch semua cabang aktif dari Supabase yang memiliki koordinat.
final _branchesProvider =
    FutureProvider.autoDispose<List<RestaurantBranch>>((ref) async {
  final res = await Supabase.instance.client
      .from('branches')
      .select(
          'id, name, address, phone, opening_time, closing_time, latitude, longitude')
      .eq('is_active', true)
      .not('latitude', 'is', null)
      .not('longitude', 'is', null)
      .order('name');

  final rows = (res as List).cast<Map<String, dynamic>>();

  return rows.map((b) {
    final isOpen = _isCurrentlyOpen(
      b['opening_time'] as String?,
      b['closing_time'] as String?,
    );

    return RestaurantBranch(
      id: b['id'] as String,
      name: b['name'] as String,
      address: b['address'] as String? ?? '',
      latitude: (b['latitude'] as num).toDouble(),
      longitude: (b['longitude'] as num).toDouble(),
      phone: b['phone'] as String? ?? '',
      openHours:
          '${b['opening_time'] ?? '?'} - ${b['closing_time'] ?? '?'}',
      isOpen: isOpen,
    );
  }).toList();
});

/// Cek apakah sekarang dalam jam operasional (format "HH:MM").
bool _isCurrentlyOpen(String? openTime, String? closeTime) {
  if (openTime == null || closeTime == null) return true;
  try {
    final now = TimeOfDay.now();
    final open = _parseTime(openTime);
    final close = _parseTime(closeTime);
    final nowMinutes = now.hour * 60 + now.minute;
    final openMinutes = open.hour * 60 + open.minute;
    final closeMinutes = close.hour * 60 + close.minute;
    // Handle overnight (misal 22:00 - 02:00)
    if (closeMinutes < openMinutes) {
      return nowMinutes >= openMinutes || nowMinutes < closeMinutes;
    }
    return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
  } catch (_) {
    return true;
  }
}

TimeOfDay _parseTime(String t) {
  final parts = t.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

// ─── State ───────────────────────────────────────────────────────────────────

abstract class NearestBranchState {}

class NearestBranchInitial extends NearestBranchState {}

class NearestBranchLoading extends NearestBranchState {}

class NearestBranchLoaded extends NearestBranchState {
  final NearestBranchResult result;
  NearestBranchLoaded(this.result);
}

class NearestBranchPermissionDenied extends NearestBranchState {}

class NearestBranchError extends NearestBranchState {
  final String message;
  NearestBranchError(this.message);
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class NearestBranchNotifier extends StateNotifier<NearestBranchState> {
  NearestBranchNotifier() : super(NearestBranchInitial());

  final _service = LocationService();

  /// Deteksi cabang terdekat dari list yang sudah di-fetch dari Supabase.
  Future<void> detectNearestBranch(List<RestaurantBranch> branches) async {
    state = NearestBranchLoading();

    final ready = await _service.isLocationReady();
    if (!ready) {
      state = NearestBranchInitial();
      return;
    }

    final position = await _service.getCurrentPosition();
    if (position == null) {
      state = NearestBranchError('Gagal mendapatkan lokasi');
      return;
    }

    final result = _service.findNearestBranch(position, branches);
    if (result == null) {
      state = NearestBranchError('Tidak ada cabang dengan koordinat tersedia');
      return;
    }

    state = NearestBranchLoaded(result);
  }

  void permissionDenied() => state = NearestBranchPermissionDenied();

  void reset() => state = NearestBranchInitial();
}

/// Provider untuk nearest branch result
final nearestBranchProvider =
    StateNotifierProvider<NearestBranchNotifier, NearestBranchState>(
  (ref) => NearestBranchNotifier(),
);

// ─── Banner Widget ────────────────────────────────────────────────────────────

/// Widget banner untuk ditampilkan di customer_landing_screen.dart
/// Self-contained: fetch cabang dari Supabase sendiri, tidak perlu data luar.
///
/// Taruh di bagian atas body, sebelum konten menu/lainnya:
/// ```dart
/// NearestBranchBanner(
///   onBranchSelected: (branch) => context.push('/customer/menu/${branch.id}'),
/// )
/// ```
class NearestBranchBanner extends ConsumerWidget {
  final void Function(RestaurantBranch branch)? onBranchSelected;

  const NearestBranchBanner({super.key, this.onBranchSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(_branchesProvider);
    final state = ref.watch(nearestBranchProvider);

    // Tunggu data Supabase dulu; jika error atau kosong, sembunyikan banner
    return branchesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (branches) {
        if (branches.isEmpty) return const SizedBox.shrink();
        if (state is NearestBranchPermissionDenied) {
          return const SizedBox.shrink();
        }

        if (state is NearestBranchInitial) {
          return _PromptBanner(
            onTap: () => _showPermissionSheet(context, ref, branches),
          );
        }

        if (state is NearestBranchLoading) {
          return const _LoadingBanner();
        }

        if (state is NearestBranchLoaded) {
          return _ResultBanner(
            result: state.result,
            onTap: () => onBranchSelected?.call(state.result.branch),
            onRefresh: () => ref
                .read(nearestBranchProvider.notifier)
                .detectNearestBranch(branches),
          );
        }

        if (state is NearestBranchError) {
          return _ErrorBanner(
            message: state.message,
            onRetry: () => ref
                .read(nearestBranchProvider.notifier)
                .detectNearestBranch(branches),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  void _showPermissionSheet(
    BuildContext context,
    WidgetRef ref,
    List<RestaurantBranch> branches,
  ) {
    LocationPermissionSheet.show(
      context,
      onGranted: () => ref
          .read(nearestBranchProvider.notifier)
          .detectNearestBranch(branches),
      onDenied: () =>
          ref.read(nearestBranchProvider.notifier).permissionDenied(),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _PromptBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _PromptBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F0),
          border: Border.all(color: const Color(0xFFFFD199)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.location_on_rounded,
                color: Color(0xFFFF6B00), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Temukan cabang terdekat',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF212121),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Ketuk untuk izinkan akses lokasi',
                    style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Color(0xFFFF6B00), size: 20),
          ],
        ),
      ),
    );
  }
}

class _LoadingBanner extends StatelessWidget {
  const _LoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Color(0xFFFF6B00)),
            ),
          ),
          SizedBox(width: 12),
          Text(
            'Mencari cabang terdekat...',
            style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final NearestBranchResult result;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const _ResultBanner({
    required this.result,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final service = LocationService();
    final isOpen = result.branch.isOpen;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F0),
          border: Border.all(color: const Color(0xFFFFD199)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.store_rounded,
                  color: Color(0xFFFF6B00), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        result.branch.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF212121),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOpen
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFCE4EC),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isOpen ? 'Buka' : 'Tutup',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isOpen
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 3),
                      Text(
                        service.formatDistance(result.distanceKm),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFF6B00),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          result.branch.address,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFFF6B00), size: 20),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFCE4EC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: const Text(
              'Coba lagi',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFFF6B00),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}