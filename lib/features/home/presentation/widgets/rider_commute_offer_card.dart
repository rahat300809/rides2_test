import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/core/services/location_search_service.dart';

class RiderCommuteOfferCard extends StatefulWidget {
  final String initialPickup;
  final String initialDropoff;
  final Function({
    required String pickup,
    required String dropoff,
    required DateTime departureTime,
    required bool isNow,
  }) onProceed;

  const RiderCommuteOfferCard({
    super.key,
    this.initialPickup = 'DIU Smart City, Ashulia',
    this.initialDropoff = '',
    required this.onProceed,
  });

  @override
  State<RiderCommuteOfferCard> createState() => _RiderCommuteOfferCardState();
}

class _RiderCommuteOfferCardState extends State<RiderCommuteOfferCard> {
  late TextEditingController _pickupController;
  late TextEditingController _dropoffController;
  DateTime _selectedTime = DateTime.now();
  bool _isNow = true;
  bool _isLocatingGps = false;

  List<LocationSearchResult> _suggestions = [];
  bool _showSuggestions = false;
  String _activeFocusField = 'dropoff';

  void _onTextChanged(String text, String field) {
    setState(() {
      _activeFocusField = field;
    });
    final clean = text.trim();
    if (clean.isEmpty) {
      setState(() {
        _suggestions = LocationSearchService.campusLandmarks.take(6).toList();
        _showSuggestions = true;
      });
      return;
    }

    // 0ms instant local suggestion matching
    final instantMatches = LocationSearchService.getLocalMatches(clean);
    setState(() {
      _suggestions = instantMatches.take(7).toList();
      _showSuggestions = instantMatches.isNotEmpty;
    });

    LocationSearchService.search(clean).then((results) {
      if (mounted && results.isNotEmpty) {
        setState(() {
          final seen = <String>{};
          _suggestions = [...instantMatches, ...results].where((e) => seen.add(e.title)).take(7).toList();
          _showSuggestions = _suggestions.isNotEmpty;
        });
      }
    });
  }

  final List<String> _quickDestinations = [
    'Mirpur 10',
    'Uttara North',
    'Dhaka University',
    'Motijheel',
    'Dhanmondi',
    'Farmgate',
    'ECB Chattar',
    'Savar',
  ];

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController(text: widget.initialPickup);
    _dropoffController = TextEditingController(text: widget.initialDropoff);
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLocatingGps = true);
    HapticFeedback.lightImpact();
    try {
      final name = await GpsLocationService.getReadableCurrentLocationName();
      if (mounted) {
        setState(() {
          _pickupController.text = name;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Pickup set to $name')),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _pickupController.text = GpsLocationService.defaultCampusName);
    } finally {
      if (mounted) setState(() => _isLocatingGps = false);
    }
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: now,
      helpText: 'SELECT DEPARTURE TIME',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65100),
              onPrimary: Colors.white,
              onSurface: Color(0xFF141416),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final nowDt = DateTime.now();
      final dt = DateTime(nowDt.year, nowDt.month, nowDt.day, picked.hour, picked.minute);
      setState(() {
        _selectedTime = dt;
        _isNow = false;
      });
    }
  }

  void _triggerProceed() {
    final dropoff = _dropoffController.text.trim();
    if (dropoff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or select your destination'),
          backgroundColor: Color(0xFFE65100),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    widget.onProceed(
      pickup: _pickupController.text.trim().isEmpty ? 'DIU Smart City, Ashulia' : _pickupController.text.trim(),
      dropoff: dropoff,
      departureTime: _selectedTime,
      isNow: _isNow,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.96),
            Colors.white.withOpacity(0.90),
          ],
        ),
        border: Border.all(
          color: Colors.white,
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE65100).withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top header title + Rider Mode Tag
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offer a Ride',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF141416),
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Set your commute corridor & auto-match peers',
                          style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE65100).withOpacity(0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.two_wheeler, color: Colors.white, size: 13),
                          SizedBox(width: 4),
                          Text(
                            'RIDER',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Pickup & Destination Inputs
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      // Pickup Row (From)
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _pickupController,
                              onChanged: (val) => _onTextChanged(val, 'pickup'),
                              onTap: () => _onTextChanged(_pickupController.text, 'pickup'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Where from? (Pickup location)',
                                hintStyle: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.normal,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: _isLocatingGps
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                                  )
                                : const Icon(Icons.my_location, size: 18, color: Color(0xFF10B981)),
                            onPressed: _fetchCurrentLocation,
                            tooltip: 'Use current GPS location',
                          ),
                        ],
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Divider(color: Color(0xFFE5E7EB), height: 1),
                      ),

                      // Dropoff Row (To)
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE65100),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _dropoffController,
                              onChanged: (val) => _onTextChanged(val, 'dropoff'),
                              onTap: () => _onTextChanged(_dropoffController.text, 'dropoff'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Where to? (e.g. Mirpur 10, Uttara, Motijheel)',
                                hintStyle: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.normal,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                              ),
                              onSubmitted: (_) {
                                setState(() => _showSuggestions = false);
                                _triggerProceed();
                              },
                            ),
                          ),
                          if (_dropoffController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: Color(0xFF9CA3AF)),
                              onPressed: () {
                                _dropoffController.clear();
                                setState(() {
                                  _showSuggestions = false;
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_showSuggestions && _suggestions.isNotEmpty)
                  _buildSuggestionsDropdown(),

                const SizedBox(height: 14),

                // Departure Time Selector
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isNow = true;
                            _selectedTime = DateTime.now();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _isNow ? const Color(0xFFE65100) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.bolt_rounded, size: 16, color: _isNow ? Colors.white : const Color(0xFF4B5563)),
                              const SizedBox(width: 6),
                              Text(
                                'Leaving Now',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: _isNow ? Colors.white : const Color(0xFF4B5563),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_isNow ? const Color(0xFFE65100) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.schedule, size: 16, color: !_isNow ? Colors.white : const Color(0xFF4B5563)),
                              const SizedBox(width: 6),
                              Text(
                                !_isNow
                                    ? '${_selectedTime.hour % 12 == 0 ? 12 : _selectedTime.hour % 12}:${_selectedTime.minute.toString().padLeft(2, '0')} ${_selectedTime.hour >= 12 ? 'PM' : 'AM'}'
                                    : 'Schedule Later',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: !_isNow ? Colors.white : const Color(0xFF4B5563),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Quick Destination Route Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _quickDestinations.map((dest) {
                      final isSelected = _dropoffController.text.trim().toLowerCase() == dest.toLowerCase();
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _dropoffController.text = dest;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFE65100).withOpacity(0.12) : const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFE65100) : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.near_me_outlined,
                                size: 12,
                                color: isSelected ? const Color(0xFFE65100) : const Color(0xFF6B7280),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                dest,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? const Color(0xFFE65100) : const Color(0xFF374151),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 18),

                // Primary CTA: Calculate Route & Set Fare ->
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _triggerProceed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Review Route Map & Set Fare →',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFE65100)),
                    const SizedBox(width: 5),
                    Text(
                      _activeFocusField == 'dropoff' ? 'SUGGESTED DESTINATIONS' : 'SUGGESTED PICKUPS',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => setState(() => _showSuggestions = false),
                  child: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ..._suggestions.map((s) => InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                if (_activeFocusField == 'dropoff') {
                  _dropoffController.text = s.title;
                } else {
                  _pickupController.text = s.title;
                }
                _showSuggestions = false;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: s.category == 'metro'
                          ? const Color(0xFFEFF6FF)
                          : (s.category == 'campus' ? const Color(0xFFECFDF5) : const Color(0xFFFFF8E1)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      s.category == 'metro'
                          ? Icons.subway_rounded
                          : (s.category == 'campus' ? Icons.school_rounded : Icons.location_on_rounded),
                      size: 15,
                      color: s.category == 'metro'
                          ? const Color(0xFF2563EB)
                          : (s.category == 'campus' ? const Color(0xFF059669) : const Color(0xFFE65100)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          s.subtitle,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }
}
