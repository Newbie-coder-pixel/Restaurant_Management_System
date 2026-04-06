// lib/core/services/location_service.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Model untuk data cabang restaurant
class RestaurantBranch {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String phone;
  final String openHours;
  final bool isOpen;

  const RestaurantBranch({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.phone,
    required this.openHours,
    required this.isOpen,
  });
}

/// Result wrapper untuk lokasi + cabang terdekat
class NearestBranchResult {
  final RestaurantBranch branch;
  final double distanceKm;
  final Position userPosition;

  const NearestBranchResult({
    required this.branch,
    required this.distanceKm,
    required this.userPosition,
  });
}

class LocationService {
  /// Cek apakah location service aktif & permission sudah granted
  Future<bool> isLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Request permission — kembalikan true jika granted
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Dapatkan posisi user saat ini
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  /// Hitung jarak antara dua koordinat (km) — Haversine formula
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRad(double deg) => deg * (pi / 180);

  /// Temukan cabang terdekat dari posisi user
  NearestBranchResult? findNearestBranch(
    Position userPosition,
    List<RestaurantBranch> branches,
  ) {
    if (branches.isEmpty) return null;

    RestaurantBranch nearest = branches.first;
    double minDistance = double.infinity;

    for (final branch in branches) {
      final distance = calculateDistance(
        userPosition.latitude,
        userPosition.longitude,
        branch.latitude,
        branch.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearest = branch;
      }
    }

    return NearestBranchResult(
      branch: nearest,
      distanceKm: minDistance,
      userPosition: userPosition,
    );
  }

  /// One-shot: request permission + get nearest branch
  Future<NearestBranchResult?> getNearestBranch(
    List<RestaurantBranch> branches,
  ) async {
    final granted = await requestPermission();
    if (!granted) return null;

    final position = await getCurrentPosition();
    if (position == null) return null;

    return findNearestBranch(position, branches);
  }

  /// Format jarak jadi string yang readable
  String formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} m';
    }
    return '${km.toStringAsFixed(1)} km';
  }
}