import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/map/presentation/widgets/map_location_picker_sheet.dart';

/// Reusable Autocomplete & Map Search Input Widget
/// Provides real-time typing suggestions via Google Places API & Campus Landmarks
/// Supports typo-correction (e.g. "motijil" -> "Motijheel", "asulia" -> "Ashulia")
class LocationAutocompleteInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final IconData prefixIcon;
  final Color prefixColor;
  final ValueChanged<LocationSearchResult> onLocationSelected;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onGpsTap;
  final LatLng? mapInitialPosition;
  final bool showMapPicker;

  const LocationAutocompleteInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.labelText,
    this.prefixIcon = Icons.location_on,
    this.prefixColor = const Color(0xFFE65100),
    required this.onLocationSelected,
    this.onChanged,
    this.onSubmitted,
    this.onGpsTap,
    this.mapInitialPosition,
    this.showMapPicker = true,
  });

  @override
  State<LocationAutocompleteInput> createState() => _LocationAutocompleteInputState();
}

class _LocationAutocompleteInputState extends State<LocationAutocompleteInput> {
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;

  List<LocationSearchResult> _suggestions = [];
  bool _isLoading = false;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (widget.controller.text.trim().isNotEmpty) {
        _searchPlaces(widget.controller.text);
      } else {
        setState(() {
          _suggestions = LocationSearchService.campusLandmarks.take(6).toList();
          _showSuggestions = true;
        });
      }
    } else {
      // 250ms delay allows InkWell.onTap on suggestions to register before closing
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted && !_focusNode.hasFocus) {
          setState(() => _showSuggestions = false);
        }
      });
    }
  }

  void _onTextChanged(String query) {
    widget.onChanged?.call(query);
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = LocationSearchService.campusLandmarks.take(6).toList();
        _showSuggestions = true;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    setState(() => _isLoading = true);
    final results = await LocationSearchService.search(query);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _isLoading = false;
      _showSuggestions = results.isNotEmpty;
    });
  }

  void _selectSuggestion(LocationSearchResult item) async {
    widget.controller.text = item.title;
    widget.onChanged?.call(item.title);
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
    _focusNode.unfocus();

    // Fetch exact coordinates via Place Details if placeId is present
    if (item.placeId != null) {
      final point = await LocationSearchService.getPlaceCoordinates(item.placeId!);
      if (point != null) {
        final updated = LocationSearchResult(
          title: item.title,
          subtitle: item.subtitle,
          lat: point.latitude,
          lng: point.longitude,
          category: item.category,
          placeId: item.placeId,
        );
        widget.onLocationSelected(updated);
        return;
      }
    }

    widget.onLocationSelected(item);
  }

  void _openMapPicker() {
    setState(() => _showSuggestions = false);
    _focusNode.unfocus();
    MapLocationPickerSheet.show(
      context: context,
      title: widget.labelText ?? 'Select Location on Map',
      initialPosition: widget.mapInitialPosition,
      onLocationPicked: (result) {
        widget.controller.text = result.title;
        widget.onChanged?.call(result.title);
        widget.onLocationSelected(result);
      },
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main Input Field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focusNode.hasFocus ? widget.prefixColor : const Color(0xFFE5E7EB),
              width: _focusNode.hasFocus ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(widget.prefixIcon, color: widget.prefixColor, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.labelText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.labelText!,
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      onChanged: _onTextChanged,
                      onSubmitted: widget.onSubmitted,
                      onTap: () {
                        if (widget.controller.text.trim().isEmpty) {
                          setState(() {
                            _suggestions = LocationSearchService.campusLandmarks.take(6).toList();
                            _showSuggestions = true;
                          });
                        } else {
                          _searchPlaces(widget.controller.text);
                        }
                      },
                      style: AppTypography.bodyMdMedium.copyWith(fontSize: 13.5),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: widget.hintText,
                        hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline, fontSize: 13),
                        contentPadding: EdgeInsets.symmetric(
                          vertical: widget.labelText != null ? 6 : 12,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (widget.controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: AppColors.outline),
                  tooltip: 'Clear',
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged?.call('');
                    setState(() {
                      _suggestions = LocationSearchService.campusLandmarks.take(6).toList();
                      _showSuggestions = true;
                    });
                  },
                ),
              if (widget.onGpsTap != null)
                IconButton(
                  icon: const Icon(Icons.my_location, size: 18, color: AppColors.primary),
                  tooltip: 'Current Campus Location',
                  onPressed: widget.onGpsTap,
                ),
              if (widget.showMapPicker)
                IconButton(
                  icon: const Icon(Icons.map_outlined, size: 19, color: Color(0xFFE65100)),
                  tooltip: 'Pick on Google Map',
                  onPressed: _openMapPicker,
                ),
            ],
          ),
        ),

        // Inline Autocomplete Dropdown List
        if (_showSuggestions && _suggestions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF3F4F6)),
              itemBuilder: (context, index) {
                final item = _suggestions[index];
                IconData icon;
                Color iconColor;
                switch (item.category) {
                  case 'campus':
                    icon = Icons.school;
                    iconColor = AppColors.primary;
                    break;
                  case 'metro':
                    icon = Icons.train;
                    iconColor = const Color(0xFF2E7D32);
                    break;
                  case 'hub':
                    icon = Icons.hub;
                    iconColor = const Color(0xFF1565C0);
                    break;
                  default:
                    icon = Icons.place;
                    iconColor = const Color(0xFFE65100);
                }

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _selectSuggestion(item),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: iconColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 16, color: iconColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: AppTypography.bodyMdMedium.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.subtitle,
                                  style: AppTypography.labelSm.copyWith(
                                    color: AppColors.outline,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.north_west, size: 14, color: Color(0xFFBDBDBD)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
