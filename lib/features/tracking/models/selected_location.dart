import 'package:latlong2/latlong.dart';

/// الموقع اللي المستخدم اختاره من الخريطة (بيتسلّم للشاشة الأم عن طريق
/// `onLocationSelected`).
class SelectedLocation {
  const SelectedLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  final double latitude;
  final double longitude;

  /// عنوان مفهوم، أو "موقع محدد على الخريطة" لو الـ Reverse Geocoding فشل.
  final String address;

  LatLng get latLng => LatLng(latitude, longitude);

  @override
  bool operator ==(Object other) =>
      other is SelectedLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.address == address;

  @override
  int get hashCode => Object.hash(latitude, longitude, address);

  @override
  String toString() => 'SelectedLocation($latitude, $longitude, $address)';
}
