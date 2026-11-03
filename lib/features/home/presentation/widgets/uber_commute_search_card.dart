import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/core/services/location_search_service.dart';

class UberCommuteSearchCard extends StatefulWidget {
  final String initialPickup;
  final String initialDropoff;
  final Function({
    required String pickup,
    required String dropoff,
    required DateTime departureTime,
    required bool isNow,
  }) onSearch;

  const UberCommuteSearchCard({
    super.key,
    this.initialPickup = 'DIU Smart City, Ashulia',
    this.initialDropoff = '',
    required this.onSearch,
  });

  @override
  State<UberCommuteSearchCard> createState() => _UberCommuteSearchCardState();
}

class _UberCommuteSearchCardState extends State<UberCommuteSearchCard> {
  late TextEditingController _pickupController;
  late TextEditingController _dropoffController;
  DateTime _selectedTime = DateTime.now();
  bool _isNow = true;
  bool _isLocatingGps = false;

  List<LocationSearchResult> _suggestions = [];
  bool _showSuggestions = false;
  String _activeFocusField = 'dropoff'; // 'dropoff' or 'pickup'

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
    LocationSearchService.search(clean).then((results) {
      if (mounted) {
        setState(() {
          _suggestions = results.take(7).toList();
          _showSuggestions = results.isNotEmpty;
        });
      }
    });
  }

  final List<String> _quickAiDestinations = [
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

  void _triggerSearch() {
    final dropoff = _dropoffController.text.trim();
    if (dropoff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or select a destination'),
          backgroundColor: Color(0xFFE65100),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    widget.onSearch(
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
        // 3D Liquid glass layered backdrop with subtle gloss
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.95),
            Colors.white.withOpacity(0.88),
          ],
        ),
        border: Border.all(
          color: Colors.white,
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE65100).withOpacity(0.10),
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
                // Top header title + AI Tag
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Campus Commute',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF141416),
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Instant road corridor & peer matching',
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
                          Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'AI MATCH',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // From & To Box Container (Uber style interconnected line)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEAEAEA)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Dots & Connector Line
                      Column(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF16A34A).withOpacity(0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  const Color(0xFF16A34A),
                                  const Color(0xFFE65100).withOpacity(0.8),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE65100),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE65100).withOpacity(0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),

                      // Text Fields for From and To
                      Expanded(
                        child: Column(
                          children: [
                            // Pickup row
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _pickupController,
                                    onChanged: (val) => _onTextChanged(val, 'pickup'),
                                    onTap: () => _onTextChanged(_pickupController.text, 'pickup'),
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: 'Pickup (e.g. DIU Main Gate)',
                                      hintStyle: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: _fetchCurrentLocation,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8F5E9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: _isLocatingGps
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF16A34A)),
                                          )
                                        : const Icon(Icons.my_location, color: Color(0xFF16A34A), size: 16),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 14, color: Color(0xFFEAEAEA)),
                            // Destination row
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _dropoffController,
                                    onChanged: (val) => _onTextChanged(val, 'dropoff'),
                                    onTap: () => _onTextChanged(_dropoffController.text, 'dropoff'),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF141416)),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: 'Where to? (e.g. Mirpur 10, DU, Uttara)',
                                      hintStyle: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                                    ),
                                    onSubmitted: (_) {
                                      setState(() => _showSuggestions = false);
                                      _triggerSearch();
                                    },
                                  ),
                                ),
                                if (_dropoffController.text.isNotEmpty)
                                  InkWell(
                                    onTap: () {
                                      _dropoffController.clear();
                                      setState(() {
                                        _showSuggestions = false;
                                      });
                                    },
                                    child: const Icon(Icons.close, size: 16, color: Color(0xFF8E8E93)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showSuggestions && _suggestions.isNotEmpty)
                  _buildSuggestionsDropdown(),
                const SizedBox(height: 12),

                // Departure Time Selector Row
                Row(
                  children: [
                    // Now Pill
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isNow = true);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isNow ? const Color(0xFF141416) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.bolt,
                              size: 15,
                              color: _isNow ? Colors.white : const Color(0xFF141416),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Leave Now',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _isNow ? Colors.white : const Color(0xFF141416),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Custom Schedule Time Pill
                    InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: !_isNow ? const Color(0xFFE65100) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: !_isNow ? Colors.white : const Color(0xFF8E8E93),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              !_isNow
                                  ? '${_selectedTime.hour > 12 ? _selectedTime.hour - 12 : (_selectedTime.hour == 0 ? 12 : _selectedTime.hour)}:${_selectedTime.minute.toString().padLeft(2, '0')} ${_selectedTime.hour >= 12 ? 'PM' : 'AM'}'
                                  : 'Pick Time',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: !_isNow ? Colors.white : const Color(0xFF141416),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // AI Smart Suggested Destination Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _quickAiDestinations.map((dest) {
                      final isSelected = _dropoffController.text.toLowerCase() == dest.toLowerCase();
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          avatar: Icon(
                            dest == 'Mirpur 10' || dest == 'Uttara North' ? Icons.directions_subway : Icons.near_me,
                            size: 13,
                            color: isSelected ? Colors.white : const Color(0xFFE65100),
                          ),
                          label: Text(dest),
                          labelStyle: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? Colors.white : const Color(0xFF141416),
                          ),
                          backgroundColor: isSelected ? const Color(0xFFE65100) : const Color(0xFFF2F2F7),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFFE65100) : Colors.transparent,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => _dropoffController.text = dest);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // 3D Liquid Glass Search Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _triggerSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0xFFE65100).withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Find Matching Bikers & Routes',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, size: 13),
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
