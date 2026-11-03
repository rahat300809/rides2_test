import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/utils/url_launcher_helper.dart';

/// Official SVGs for Developer Social Profiles
const String _linkedInSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="22" height="22">
  <path fill="#0A66C2" d="M19 3a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14m-.5 15.5v-5.3a3.26 3.26 0 0 0-3.26-3.26c-.85 0-1.84.52-2.28 1.3v-1.11h-2.79v8.37h2.79v-4.93c0-.77.62-1.4 1.39-1.4a1.4 1.4 0 0 1 1.4 1.4v4.93h2.75M6.46 8.76a1.64 1.64 0 1 0 0-3.28 1.64 1.64 0 0 0 0 3.28m1.39 9.74v-8.37H5.07v8.37h2.78z"/>
</svg>
''';

const String _gitHubSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="22" height="22">
  <path fill="#24292E" fill-rule="evenodd" clip-rule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.53 1.032 1.53 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"/>
</svg>
''';

const String _whatsAppSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="22" height="22">
  <path fill="#25D366" d="M12.04 2c-5.46 0-9.91 4.45-9.91 9.91 0 1.75.46 3.45 1.32 4.95L2.05 22l5.25-1.38c1.45.79 3.08 1.21 4.74 1.21 5.46 0 9.91-4.45 9.91-9.91 0-2.65-1.03-5.14-2.9-7.01A9.816 9.816 0 0 0 12.04 2m.01 1.67c2.2 0 4.26.86 5.82 2.42a8.225 8.225 0 0 1 2.41 5.83c0 4.54-3.7 8.24-8.24 8.24-1.48 0-2.93-.4-4.2-1.15l-.3-.18-3.12.82.83-3.04-.2-.31a8.196 8.196 0 0 1-1.26-4.38c0-4.54 3.7-8.24 8.24-8.24m4.52 11.64c-.25-.13-1.47-.72-1.7-.81-.23-.08-.39-.13-.56.13-.17.25-.64.81-.79.97-.14.17-.29.19-.54.06-.25-.13-1.06-.39-2.02-1.25-.75-.67-1.26-1.5-1.41-1.75-.15-.25-.02-.39.11-.51.11-.11.25-.29.37-.44.12-.14.17-.25.25-.42.08-.17.04-.31-.02-.44-.06-.13-.56-1.35-.77-1.85-.2-.49-.41-.42-.56-.43h-.48c-.17 0-.44.06-.67.31-.23.25-.87.85-.87 2.08 0 1.23.89 2.42 1.02 2.59.13.17 1.76 2.69 4.26 3.77.6.26 1.06.41 1.43.53.6.19 1.15.16 1.58.1.48-.07 1.47-.6 1.68-1.18.21-.58.21-1.08.15-1.18-.06-.1-.23-.17-.48-.29z"/>
</svg>
''';

/// Helper to launch external URLs safely across Web & Mobile
Future<void> launchSocialUrl(BuildContext context, String urlString) async {
  final success = await launchSafeUrl(urlString);
  if (!success && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open: $urlString'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Compact & Decorated Developer Footer Card for Profile & Settings
class DeveloperFooterCard extends StatelessWidget {
  final VoidCallback? onOpenDetails;

  const DeveloperFooterCard({super.key, this.onOpenDetails});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onOpenDetails,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                // Developer Photo with Emerald Status Ring
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF16A34A), width: 2),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/developer_rahat.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF15803D),
                            child: const Center(
                              child: Text('RM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                // Developer Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'MD. Rahat Mahamud',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'BATCH 252',
                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Creator & Lead Engineer • CSE, DIU',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          // Decorated Social Pill Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _socialCompactBtn(context, 'LinkedIn', 'https://www.linkedin.com/in/rahat300809/', _linkedInSvg, const Color(0xFF0A66C2)),
              _socialCompactBtn(context, 'GitHub', 'https://github.com/rahat300809', _gitHubSvg, const Color(0xFF24292E)),
              _socialCompactBtn(context, 'WhatsApp', 'https://wa.me/8801909566539', _whatsAppSvg, const Color(0xFF25D366)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _socialCompactBtn(BuildContext context, String title, String url, String svg, Color color) {
    return InkWell(
      onTap: () => launchSocialUrl(context, url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.string(svg, width: 14, height: 14),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the Decorated, Minimal-Space Developer Profile Dialog
void showDeveloperInfoDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => const DeveloperInfoDialog(),
  );
}

/// Decorated, Minimal Space Developer Modal Dialog
class DeveloperInfoDialog extends StatelessWidget {
  const DeveloperInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 390),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar with Badge & Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, size: 13, color: Color(0xFF059669)),
                      SizedBox(width: 4),
                      Text(
                        'DIU STUDENT CREATOR',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF059669), letterSpacing: 0.3),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 19, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Profile Header Row (Compact & Decorated)
            Row(
              children: [
                // Developer Photo
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF16A34A), width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF16A34A).withOpacity(0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/developer_rahat.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF15803D),
                            child: const Center(
                              child: Text('RM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                // Identity
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MD. Rahat Mahamud',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'B.Sc in CSE • Batch 252 (5th Sem)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF16A34A)),
                      ),
                      Text(
                        'Daffodil International University (DIU)',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Decorated Highlights Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatBadge(icon: Icons.code_rounded, label: 'Full Stack', value: 'Flutter & Python'),
                  _StatBadge(icon: Icons.shield_outlined, label: 'Security', value: 'IoT & Web'),
                  _StatBadge(icon: Icons.location_on_outlined, label: 'Campus', value: 'Ashulia'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Decorated Social Links with Working Universal Web Launchers
            const Text(
              'Connect with Developer',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF334155), letterSpacing: 0.2),
            ),
            const SizedBox(height: 8),

            const _SocialTile(
              title: 'LinkedIn Profile',
              subtitle: 'linkedin.com/in/rahat300809',
              url: 'https://www.linkedin.com/in/rahat300809/',
              svgIcon: _linkedInSvg,
              brandColor: Color(0xFF0A66C2),
            ),
            const SizedBox(height: 6),
            const _SocialTile(
              title: 'GitHub Repository',
              subtitle: 'github.com/rahat300809/Diu_Rides',
              url: 'https://github.com/rahat300809/Diu_Rides',
              svgIcon: _gitHubSvg,
              brandColor: Color(0xFF24292E),
            ),
            const SizedBox(height: 6),
            const _SocialTile(
              title: 'WhatsApp Contact',
              subtitle: '+880 1909-566539',
              url: 'https://wa.me/8801909566539',
              svgIcon: _whatsAppSvg,
              brandColor: Color(0xFF25D366),
            ),
            const SizedBox(height: 12),

            // Footer
            const Text(
              'DIU Ride Platform • Crafted with ❤️ for DIU Community',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatBadge({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF16A34A)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        Text(label, style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
      ],
    );
  }
}

class _SocialTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String url;
  final String svgIcon;
  final Color brandColor;

  const _SocialTile({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.svgIcon,
    required this.brandColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchSocialUrl(context, url),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: brandColor.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: brandColor.withOpacity(0.18), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: SvgPicture.string(svgIcon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: brandColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 14, color: brandColor.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}
