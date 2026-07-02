import 'dart:math' as math;

import '../main.dart';
import 'ph_locations.dart';

export 'ph_locations.dart' show PhCity, phCities;

/// The signed-in user's saved location (city name + coordinates).
class UserLocation {
  final String name;
  final double lat;
  final double lng;

  const UserLocation({required this.name, required this.lat, required this.lng});
}

class LocationService {
  /// Great-circle (Haversine) distance between two points, in kilometres.
  static double distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  /// Loads the signed-in user's saved location, or `null` if none is set yet.
  static Future<UserLocation?> fetchUserLocation() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final row = await supabase
          .from('users')
          .select('location_name, latitude, longitude')
          .eq('id', userId)
          .maybeSingle();
      final name = (row?['location_name'] as String?)?.trim() ?? '';
      final lat = row?['latitude'] as num?;
      final lng = row?['longitude'] as num?;
      if (name.isEmpty || lat == null || lng == null) return null;
      return UserLocation(name: name, lat: lat.toDouble(), lng: lng.toDouble());
    } catch (_) {
      return null; // Columns may not exist yet — treat as "no location".
    }
  }

  /// Saves [city] as the signed-in user's location. Returns true on success.
  static Future<bool> saveUserLocation(PhCity city) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      await supabase.from('users').update({
        'location_name': city.label,
        'latitude': city.lat,
        'longitude': city.lng,
      }).eq('id', userId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
