import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';

class MotorcycleConfigDialog extends ConsumerStatefulWidget {
  final Function(String model, String plate, String color, bool hasHelmet)? onSaved;

  const MotorcycleConfigDialog({super.key, this.onSaved});

  static Future<void> show({
    required BuildContext context,
    Function(String model, String plate, String color, bool hasHelmet)? onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MotorcycleConfigDialog(onSaved: onSaved),
    );
  }

  static Future<bool> isConfigured(WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('rider_moto_configured') == true) {
      return true;
    }
    final model = prefs.getString('rider_moto_model');
    final plate = prefs.getString('rider_moto_plate');
    if (model != null && model.trim().isNotEmpty && plate != null && plate.trim().isNotEmpty) {
      return true;
    }
    final user = ref.read(authNotifierProvider).user;
    if (user?.vehicleInfo != null && user!.vehicleInfo!.trim().isNotEmpty) {
      final vInfo = user.vehicleInfo!;
      final match = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(vInfo);
      if (match != null) {
        final m = match.group(1)?.trim();
        final p = match.group(2)?.trim();
        if (m != null && m.isNotEmpty && p != null && p.isNotEmpty) {
          await prefs.setString('rider_moto_model', m);
          await prefs.setString('rider_moto_plate', p);
        }
      } else {
        await prefs.setString('rider_moto_model', vInfo);
        await prefs.setString('rider_moto_plate', 'DHAKA-METRO');
      }
      await prefs.setBool('rider_moto_configured', true);
      return true;
    }
    return false;
  }

  static Future<bool> ensureConfigured(BuildContext context, WidgetRef ref) async {
    final configured = await isConfigured(ref);
    if (!context.mounted) return false;
    if (configured) return true;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 28),
            SizedBox(width: 10),
            Text('Motorcycle Setup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: const Text(
          'To offer campus rides, please configure your bike model and license plate number once. After setup, you will not be asked again!',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF334155)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setup Motorcycle Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (proceed != true || !context.mounted) return false;

    await show(context: context);
    return await isConfigured(ref);
  }

  @override
  ConsumerState<MotorcycleConfigDialog> createState() => _MotorcycleConfigDialogState();
}

class _MotorcycleConfigDialogState extends ConsumerState<MotorcycleConfigDialog> {
  final _modelController = TextEditingController(text: 'Yamaha FZ-X');
  final _plateController = TextEditingController(text: 'Dhaka Metro-HA 24-8891');
  final _colorController = TextEditingController(text: 'Black Metallic');
  bool _hasHelmet = true;
  bool _isLoading = false;

  final List<String> _popularModels = [
    'Yamaha FZ-X',
    'Yamaha FZ-S V3',
    'Honda CB Shine',
    'Honda X-Blade',
    'Suzuki Gixxer',
    'Bajaj Pulsar NS160',
    'TVS Apache RTR',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedModel = prefs.getString('rider_moto_model');
    final savedPlate = prefs.getString('rider_moto_plate');
    final savedColor = prefs.getString('rider_moto_color');
    final savedHelmet = prefs.getBool('rider_moto_helmet');

    final user = ref.read(authNotifierProvider).user;
    if (savedModel != null && savedModel.isNotEmpty) {
      _modelController.text = savedModel;
    } else if (user?.vehicleInfo != null && user!.vehicleInfo!.isNotEmpty) {
      // parse "Model (Plate)"
      final vInfo = user.vehicleInfo!;
      final match = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(vInfo);
      if (match != null) {
        _modelController.text = match.group(1) ?? 'Yamaha FZ-X';
        _plateController.text = match.group(2) ?? 'Dhaka Metro-HA 24-8891';
      } else {
        _modelController.text = vInfo;
      }
    }

    if (savedPlate != null && savedPlate.isNotEmpty) {
      _plateController.text = savedPlate;
    }
    if (savedColor != null && savedColor.isNotEmpty) {
      _colorController.text = savedColor;
    }
    if (savedHelmet != null) {
      setState(() => _hasHelmet = savedHelmet);
    }
  }

  @override
  void dispose() {
    _modelController.dispose();
    _plateController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final model = _modelController.text.trim().isEmpty ? 'Yamaha FZ-X' : _modelController.text.trim();
    final plate = _plateController.text.trim().isEmpty ? 'Dhaka Metro-HA 24-8891' : _plateController.text.trim();
    final color = _colorController.text.trim().isEmpty ? 'Black' : _colorController.text.trim();

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rider_moto_model', model);
      await prefs.setString('rider_moto_plate', plate);
      await prefs.setString('rider_moto_color', color);
      await prefs.setBool('rider_moto_helmet', _hasHelmet);
      await prefs.setBool('rider_moto_configured', true);

      final user = ref.read(authNotifierProvider).user;
      if (user != null) {
        final updated = user.copyWith(
          isDriverRegistered: true,
          vehicleInfo: '$model ($plate)',
        );
        final saved = await ref.read(authRepositoryProvider).updateProfile(updated);
        ref.read(authNotifierProvider.notifier).setUser(saved);
      }

      widget.onSaved?.call(model, plate, color, _hasHelmet);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF2E7D32),
            content: Text('Motorcycle configuration saved successfully! 🏍️'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to save configuration: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Motorcycle Rider Setup',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF141416),
                          ),
                        ),
                        Text(
                          'Configure your bike details for campus peer sharing',
                          style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Quick Bike Model Suggestions
              const Text(
                'Quick Select Bike Model',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _popularModels.map((m) {
                  final isSelected = _modelController.text.trim().toLowerCase() == m.toLowerCase();
                  return ChoiceChip(
                    label: Text(m),
                    selected: isSelected,
                    selectedColor: const Color(0xFFFFF3E0),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFFE65100) : const Color(0xFF374151),
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _modelController.text = m);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Motorcycle Model Custom Input
              TextField(
                controller: _modelController,
                decoration: InputDecoration(
                  labelText: 'Motorcycle Model & Make',
                  hintText: 'e.g. Yamaha FZ-X / Suzuki Gixxer',
                  prefixIcon: const Icon(Icons.motorcycle, color: Color(0xFFE65100)),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // License Plate
              TextField(
                controller: _plateController,
                decoration: InputDecoration(
                  labelText: 'Number Plate / Registration',
                  hintText: 'e.g. Dhaka Metro-HA 24-8891',
                  prefixIcon: const Icon(Icons.pin, color: Color(0xFFE65100)),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Bike Color
              TextField(
                controller: _colorController,
                decoration: InputDecoration(
                  labelText: 'Motorcycle Color',
                  hintText: 'e.g. Matte Black / Metallic Blue',
                  prefixIcon: const Icon(Icons.palette_outlined, color: Color(0xFFE65100)),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Clean Helmet Switch
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.sports_motorsports_outlined, color: Color(0xFFE65100), size: 22),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Clean Helmet for Passenger',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'You provide an extra sanitized helmet',
                              style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: _hasHelmet,
                      activeColor: const Color(0xFFE65100),
                      onChanged: (val) => setState(() => _hasHelmet = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Save Button
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveConfig,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(
                  _isLoading ? 'Saving...' : 'Save Motorcycle Configuration',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
