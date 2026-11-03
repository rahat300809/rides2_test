import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_voice_call_dialog.dart';

class DirectCallService {
  DirectCallService._();

  static String cleanPhoneNumber(String rawPhone) {
    return rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  static bool isValidPhone(String phone) {
    final clean = cleanPhoneNumber(phone);
    return clean.replaceAll('+', '').length >= 6;
  }

  static Future<bool> makeDirectPhoneCall(
    BuildContext context, {
    required String phoneNumber,
    String? peerName,
  }) async {
    final clean = cleanPhoneNumber(phoneNumber);
    if (!isValidPhone(clean)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.phone_missed, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    peerName != null
                        ? 'No direct phone number provided by $peerName.'
                        : 'No valid phone number available.',
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
      return false;
    }

    final uri = Uri(scheme: 'tel', path: clean);
    bool launched = false;
    try {
      if (kIsWeb) {
        try {
          launched = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
        } catch (_) {
          try {
            launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
          } catch (_) {
            launched = await launchUrl(uri);
          }
        }
      } else {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) {
          launched = await launchUrl(uri);
        }
      }
    } catch (e) {
      debugPrint('[DirectCallService] Dial error: $e');
    }

    // Always copy number to clipboard as safe backup so user never loses it
    await Clipboard.setData(ClipboardData(text: clean));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.phone_in_talk, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Dialing $clean (${peerName ?? "Peer"})...'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
    return launched;
  }

  static Future<void> showCallOptions(
    BuildContext context, {
    required String phoneNumber,
    required String peerName,
    String peerRole = 'Ride Companion',
    String? peerDept = 'DIU Student',
  }) {
    final clean = cleanPhoneNumber(phoneNumber);
    final hasValidPhone = isValidPhone(clean);

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag indicator
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),

              // Peer header
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFFE8F5E9),
                    child: Text(
                      peerName.isNotEmpty ? peerName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peerName,
                          style: AppTypography.headlineSm.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$peerRole • ${peerDept ?? "DIU Student"}',
                          style: AppTypography.labelSm.copyWith(color: Colors.grey[600]),
                        ),
                        if (hasValidPhone)
                          Text(
                            phoneNumber,
                            style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Option 1: Direct Phone Call (Immediate Cellular Dial)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.phone, color: Color(0xFF2E7D32), size: 22),
                ),
                title: const Text(
                  'Direct Phone Call',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Text(
                  hasValidPhone
                      ? 'Launch mobile phone dialer to call $clean'
                      : 'No cellular number registered',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                enabled: hasValidPhone,
                onTap: () {
                  Navigator.pop(ctx);
                  makeDirectPhoneCall(context, phoneNumber: phoneNumber, peerName: peerName);
                },
              ),

              // Option 2: Campus Voice Intercom Call
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.record_voice_over, color: Color(0xFF1976D2), size: 22),
                ),
                title: const Text(
                  'Campus Voice Intercom',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Text(
                  'In-app student peer voice channel & intercom',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  CampusVoiceCallDialog.show(
                    context,
                    peerName: peerName,
                    peerPhone: hasValidPhone ? phoneNumber : '01712345678',
                    peerRole: peerRole,
                    peerDept: peerDept,
                  );
                },
              ),

              // Option 3: Copy Phone Number
              if (hasValidPhone)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.copy, color: Colors.black87, size: 22),
                  ),
                  title: const Text(
                    'Copy Phone Number',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(
                    clean,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Clipboard.setData(ClipboardData(text: clean));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Phone number $clean copied to clipboard!'),
                          backgroundColor: const Color(0xFF2E7D32),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
