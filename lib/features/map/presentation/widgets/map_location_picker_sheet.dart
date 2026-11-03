import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/core/theme/app_typography.dart';

/// Interactive Map Location Picker Bottom Sheet
/// Allows rider or passenger to point anywhere on Google Map to select pickup/dropoff
class MapLocationPickerSheet extends StatefulWidget {
  final String title;
  final LatLng initialPosition;
  final ValueChanged<LocationSearchResult> onLocationPicked;

  const MapLocationPickerSheet({
    super.key,
    required this.title,
    required this.initialPosition,
    required this.onLocationPicked,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    LatLng? initialPosition,
    required ValueChanged<LocationSearchResult> onLocationPicked,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapLocationPickerSheet(
        title: title,
        initialPosition: initialPosition ??
            const LatLng(CampusLocations.diuCenterLat, CampusLocations.diuCenterLng),
        onLocationPicked: onLocationPicked,
      ),
    );
  }

  @override
  State<MapLocationPickerSheet> createState() => _MapLocationPickerSheetState();
}

class _MapLocationPickerSheetState extends State<MapLocationPickerSheet> {
  late LatLng _selectedLatLng;
  GoogleMapController? _mapController;
  String _locationName = 'Locating...';
  bool _isGeocoding = false;

  @override
  void initState() {
    super.initState();
    _selectedLatLng = widget.initialPosition;
    _reverseGeocode(_selectedLatLng);
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _isGeocoding = true);
    final name = await LocationSearchService.reverseGeocode(point);
    if (mounted) {
      setState(() {
        _locationName = name;
        _isGeocoding = false;
      });
    }
  }

  void _onMapTapped(LatLng point) {
    setState(() {
      _selectedLatLng = point;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(point));
    _reverseGeocode(point);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: AppTypography.headlineSm.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap anywhere on Google Map to select location pin',
                      style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Map View
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: widget.initialPosition,
                    zoom: 14.5,
                  ),
                  onMapCreated: (ctrl) => _mapController = ctrl,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                  onTap: _onMapTapped,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
                  markers: {
                    Marker(
                      markerId: const MarkerId('picked_point'),
                      position: _selectedLatLng,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                      infoWindow: InfoWindow(title: _locationName),
                    ),
                  },
                ),

                // Floating Target Center Pin
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.place, color: Color(0xFFE65100), size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isGeocoding ? 'Detecting address...' : _locationName,
                                style: AppTypography.bodyMdMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_selectedLatLng.latitude.toStringAsFixed(4)}, ${_selectedLatLng.longitude.toStringAsFixed(4)}',
                                style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                              ),
                            ],
                          ),
                        ),
                        if (_isGeocoding)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Confirmation Bar
          Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      widget.onLocationPicked(
                        LocationSearchResult(
                          title: _locationName,
                          subtitle: 'Selected on Google Map',
                          lat: _selectedLatLng.latitude,
                          lng: _selectedLatLng.longitude,
                          category: 'city',
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: Text(
                      'Confirm This Location',
                      style: AppTypography.labelLg.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
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
