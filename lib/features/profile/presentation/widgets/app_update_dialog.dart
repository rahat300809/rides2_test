import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/utils/url_launcher_helper.dart';

const String kApkGithubReleaseUrl = 'https://github.com/rahat300809/Diu_Rides/releases/latest/download/diu_ride.apk';
const String kApkDownloadUrl = 'https://servertest.eu.cc/ride/download-apk';
const String kApkLocalDownloadUrl = 'http://192.168.0.114:8001/ride/download-apk';

/// Shows the Official In-App APK Update & Installation Dialog
void showAppUpdateDialog(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _AppUpdateSheet(),
  );
}

class _AppUpdateSheet extends StatefulWidget {
  const _AppUpdateSheet();

  @override
  State<_AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<_AppUpdateSheet> {
  bool _isDownloading = false;

  Future<void> _launchApkDownload() async {
    setState(() => _isDownloading = true);
    try {
      // 1. Direct Server APK download (fast, no login, directly downloads latest APK)
      bool launched = await launchDownloadFile(kApkDownloadUrl, fileName: 'diu_ride.apk');
      if (!launched) {
        launched = await launchDownloadFile(kApkLocalDownloadUrl, fileName: 'diu_ride.apk');
        if (!launched) {
          await launchDownloadFile(kApkGithubReleaseUrl, fileName: 'diu_ride.apk');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open download link: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header with Badge
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B5E20).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.system_update,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'DIU Ride APK Update',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2E7D32), width: 0.8),
                          ),
                          child: const Text(
                            'v1.0.1',
                            style: TextStyle(
                              color: Color(0xFF2E7D32),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Varsity Production Release • Daffodil Smart City',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF757575),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Changelog Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What\'s New in this Build:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 8),
                _buildChangelogItem(
                  icon: Icons.chat_outlined,
                  text: 'Chatbox Order Portal: Confirm, start, cancel & end ride from chat',
                ),
                _buildChangelogItem(
                  icon: Icons.location_on_outlined,
                  text: 'Live GPS Location Sharing with Google Maps links in conversation',
                ),
                _buildChangelogItem(
                  icon: Icons.schedule_outlined,
                  text: 'Manual Schedule Customizer with custom date, time & location spot',
                ),
                _buildChangelogItem(
                  icon: Icons.expand_more,
                  text: 'Expandable destination ride search cards with driver route & actions',
                ),
                _buildChangelogItem(
                  icon: Icons.notifications_active_outlined,
                  text: 'Real-time varsity announcement popups, chimes & notification bar alerts',
                ),
                _buildChangelogItem(
                  icon: Icons.two_wheeler,
                  text: 'Motorbike customization: Model name, license plate, and color',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Install / Download Action Button
          ElevatedButton.icon(
            onPressed: _isDownloading ? null : _launchApkDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
            ),
            icon: _isDownloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.download, size: 22),
            label: Text(
              _isDownloading ? 'Opening Downloader...' : 'Download & Install APK Now',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Direct Download Link Display
          Center(
            child: TextButton.icon(
              onPressed: _launchApkDownload,
              icon: const Icon(Icons.link, size: 14, color: Color(0xFF757575)),
              label: const Text(
                'Direct link: servertest.eu.cc/ride/download-apk',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF757575),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangelogItem({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF424242),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
