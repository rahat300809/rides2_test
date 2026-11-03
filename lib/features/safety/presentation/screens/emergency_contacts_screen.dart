import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/constants/app_constants.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/safety/presentation/providers/safety_provider.dart';

class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safetyState = ref.watch(safetyNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Emergency & Safety'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Proctor Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryContainer],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield, color: AppColors.primaryFixed, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'DIU Proctor Security Control',
                      style: AppTypography.headlineSm.copyWith(color: AppColors.onPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '24/7 Campus Security Control Room at Daffodil Smart City, Ashulia. Immediate patrol dispatch for distress calls.',
                  style: AppTypography.bodyMd.copyWith(color: AppColors.onPrimary.withOpacity(0.9)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AppConstants.proctorExtension,
                        style: AppTypography.labelMd.copyWith(color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Calling DSC Control Desk...')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryFixed,
                        foregroundColor: AppColors.onPrimaryFixed,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.call, size: 16),
                      label: const Text('Call Control'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Guardian Emergency Contacts',
            style: AppTypography.headlineSm,
          ),
          const SizedBox(height: 4),
          Text(
            'These numbers will receive instant SMS & WhatsApp alerts with your live tracking link when Campus SOS is triggered.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          ...safetyState.contacts.map((contact) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: AppColors.surfaceContainerLowest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryFixed.withOpacity(0.5),
                  child: const Icon(Icons.person, color: AppColors.primary),
                ),
                title: Text(contact.name, style: AppTypography.bodyLgMedium),
                subtitle: Text('${contact.relation} • ${contact.phone}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.outline),
                  onPressed: () {
                    ref.read(safetyNotifierProvider.notifier).removeContact(contact.id);
                  },
                ),
              ),
            );
          }),

          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add Contact dialog')),
              );
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary),
              foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add Guardian Contact'),
          ),
        ],
      ),
    );
  }
}
