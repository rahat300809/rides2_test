import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/auth/presentation/screens/login_screen.dart';
import 'package:diu_ride/features/dashboard/presentation/screens/my_rides_dashboard_screen.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:diu_ride/features/safety/presentation/screens/emergency_contacts_screen.dart';
import 'package:diu_ride/features/chat/presentation/screens/campus_messages_screen.dart';
import 'package:diu_ride/features/profile/presentation/widgets/developer_info_dialog.dart';
import 'package:diu_ride/features/profile/presentation/widgets/app_update_dialog.dart';
import 'package:diu_ride/features/profile/presentation/widgets/motorcycle_config_dialog.dart';
import 'package:diu_ride/features/feed/presentation/screens/campus_feed_screen.dart';
import 'package:diu_ride/features/feed/presentation/providers/feed_provider.dart';
import 'package:diu_ride/features/feed/data/models/feed_post_model.dart';

final _profilePhotoPathProvider = StateProvider<String?>((ref) => null);

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _deptController;
  Uint8List? _photoBytes;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authNotifierProvider).user;
    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _deptController = TextEditingController(text: user?.department ?? 'CSE');
    _loadSavedPhoto();
  }

  Future<void> _loadSavedPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString('profile_photo_b64');
    if (b64 != null && b64.isNotEmpty) {
      try {
        final decoded = base64Decode(b64);
        setState(() => _photoBytes = decoded);
        return;
      } catch (_) {}
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFE65100)),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFE65100)),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 512);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    final b64 = base64Encode(bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_b64', b64);
    await prefs.setString('profile_photo_path', image.path);
    setState(() {
      _photoBytes = bytes;
    });
    ref.read(_profilePhotoPathProvider.notifier).state = image.path;
  }

  Future<void> _saveChanges() async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;
    final updated = user.copyWith(
      name: _nameController.text.trim().isEmpty ? user.name : _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? user.phone : _phoneController.text.trim(),
      department: _deptController.text.trim().isEmpty ? user.department : _deptController.text.trim(),
    );
    await ref.read(authRepositoryProvider).updateProfile(updated);
    setState(() => _isEditing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1C1C1E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: const Text('Profile updated ✓', style: TextStyle(color: Colors.white)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _deptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final allFeedPosts = ref.watch(feedProvider).posts;
    final myFeedPosts = allFeedPosts.where((p) {
      if (user == null) return false;
      return (p.userId.isNotEmpty && p.userId == user.id) ||
             (p.authorStudentId.isNotEmpty && p.authorStudentId == user.studentId) ||
             (p.authorName.isNotEmpty && p.authorName == user.name);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Hero Header
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFFE65100),
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(_isEditing ? Icons.check : Icons.edit_outlined, color: Colors.white),
                onPressed: _isEditing ? _saveChanges : () => setState(() => _isEditing = true),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFBF360C), Color(0xFFE65100), Color(0xFFF57C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        // Profile Photo
                        GestureDetector(
                          onTap: _pickPhoto,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 46,
                                backgroundColor: Colors.white24,
                                backgroundImage: _photoBytes != null
                                    ? MemoryImage(_photoBytes!)
                                    : null,
                                child: _photoBytes == null
                                    ? Text(
                                        (user?.name.isNotEmpty == true
                                            ? user!.name[0].toUpperCase()
                                            : 'S'),
                                        style: const TextStyle(
                                          fontSize: 36,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 14, color: Color(0xFFE65100)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user?.name ?? 'DIU Student',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user?.email ?? '',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Stats Row
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat('As Driver', '${user?.totalRidesAsDriver ?? 0}', Icons.two_wheeler),
                        Container(width: 1, height: 40, color: Colors.black12),
                        _buildStat('As Passenger', '${user?.totalRidesAsPassenger ?? 0}', Icons.person),
                        Container(width: 1, height: 40, color: Colors.black12),
                        _buildStat('Rating', '${user?.rating ?? 4.9}★', Icons.star),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Editable Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Personal Info', style: AppTypography.headlineSm.copyWith(fontSize: 15)),
                            if (_isEditing)
                              TextButton(
                                onPressed: () => setState(() => _isEditing = false),
                                child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildInfoField(
                          label: 'Full Name',
                          controller: _nameController,
                          icon: Icons.person_outline,
                          enabled: _isEditing,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoField(
                          label: 'Phone Number',
                          controller: _phoneController,
                          icon: Icons.phone_outlined,
                          enabled: _isEditing,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoField(
                          label: 'Department',
                          controller: _deptController,
                          icon: Icons.school_outlined,
                          enabled: _isEditing,
                        ),
                        const SizedBox(height: 10),
                        // Read-only fields
                        _buildReadonlyRow('Student ID', user?.studentId ?? 'N/A', Icons.badge_outlined),
                        const SizedBox(height: 8),
                        _buildReadonlyRow('Email', user?.email ?? 'N/A', Icons.email_outlined),
                        if (_isEditing) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _saveChanges,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE65100),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Motorcycle Card (Interactive Configuration)
                  InkWell(
                    onTap: () {
                      MotorcycleConfigDialog.show(
                        context: context,
                        onSaved: (m, p, c, h) => setState(() {}),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFFE0B2), width: 1.5),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 26),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Text(
                                          'Motorcycle Configuration',
                                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                        ),
                                        SizedBox(width: 4),
                                        Icon(Icons.verified, size: 14, color: Color(0xFFE65100)),
                                      ],
                                    ),
                                    Text(
                                      user?.vehicleInfo ?? 'Tap to setup motorcycle details',
                                      style: TextStyle(
                                        color: user?.vehicleInfo != null ? const Color(0xFF141416) : const Color(0xFF8E8E93),
                                        fontSize: 12.5,
                                        fontWeight: user?.vehicleInfo != null ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: user?.isDriverRegistered == true
                                      ? const Color(0xFFFFF3E0)
                                      : const Color(0xFFF2F2F7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  user?.isDriverRegistered == true ? '🟢 Biker Active' : 'Configure',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: user?.isDriverRegistered == true
                                        ? const Color(0xFFE65100)
                                        : const Color(0xFF8E8E93),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Campus Peer Commuter Setup',
                                style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                              ),
                              Row(
                                children: [
                                  Text(
                                    'Edit Moto Setup',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFFE65100)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),



                  // My Published Campus Posts (With Delete & Auto-expiry indicator)
                  _buildMyFeedPostsSection(myFeedPosts),
                  const SizedBox(height: 16),

                  // Menu Items
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildMenuTile(
                          icon: Icons.newspaper_rounded,
                          title: 'Campus News Feed',
                          subtitle: 'Student community posts & updates',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CampusFeedScreen()),
                          ),
                        ),
                        _divider(),
                        _buildMenuTile(
                          icon: Icons.history,
                          title: 'My Ride History',
                          subtitle: 'All your campus commutes',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const MyRidesDashboardScreen()),
                          ),
                        ),
                        _divider(),
                        _buildMenuTile(
                          icon: Icons.chat_bubble_outline,
                          title: 'Campus Messages',
                          subtitle: 'Chats with ride partners',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CampusMessagesScreen(
                                onExploreRides: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                        ),
                        _divider(),
                        _buildMenuTile(
                          icon: Icons.shield_outlined,
                          title: 'Safety & Emergency',
                          subtitle: 'DIU Proctor hotline & contacts',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
                          ),
                        ),
                        _divider(),
                        _buildMenuTile(
                          icon: Icons.notifications_none,
                          title: 'Notifications',
                          subtitle: 'Alerts for bookings & arrivals',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                          ),
                        ),
                        _divider(),
                        _buildMenuTile(
                          icon: Icons.system_update_alt,
                          title: 'Check for Updates',
                          subtitle: 'Version 1.0.1 (Latest) • Tap to download APK update',
                          onTap: () => showAppUpdateDialog(context),
                        ),
                        _divider(),
                        _buildMenuTile(
                          icon: Icons.code,
                          title: 'Developer Info',
                          subtitle: 'MD. Rahat Mahamud • CSE Batch 252',
                          onTap: () => showDeveloperInfoDialog(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Logout
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(authNotifierProvider.notifier).logout();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'DIU Ride v1.0.0 • Daffodil Smart City, Ashulia',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 10),
                  ),
                  const SizedBox(height: 16),

                  // Dedicated Developer Info Footer Section (Batch 252)
                  DeveloperFooterCard(
                    onOpenDetails: () => showDeveloperInfoDialog(context),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFE65100)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1C1C1E),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
      ],
    );
  }

  Widget _buildInfoField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool enabled = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFFE65100)),
        filled: true,
        fillColor: enabled ? const Color(0xFFFFF8F5) : const Color(0xFFF8F9FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: enabled ? const Color(0xFFE65100) : Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE65100), width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _buildReadonlyRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF8E8E93)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 56, endIndent: 16);

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFFE65100), size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFBDBDBD)),
      onTap: onTap,
    );
  }

  Widget _buildMyFeedPostsSection(List<FeedPostModel> myPosts) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF006699).withOpacity(0.18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF006699).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.dynamic_feed_rounded, color: Color(0xFF006699), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Campus Posts',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Auto-expires after 1 week (7 days)',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF006699).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${myPosts.length} Active',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF006699)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (myPosts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[400], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You have no active posts. Share updates, carpools, or campus photos in News Feed!',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else
            ...myPosts.map((post) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          post.imageUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image, size: 24, color: Colors.grey),
                          ),
                        ),
                      ),
                    if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                      const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF006699).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  post.category,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF006699),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                post.timeAgo,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            post.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      tooltip: 'Delete post',
                      onPressed: () => _confirmDeletePost(post.id),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _confirmDeletePost(String postId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Post?'),
        content: const Text(
          'Are you sure you want to delete this campus post? It will be permanently removed from the DIU campus feed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref.read(feedProvider.notifier).deletePost(postId);
              if (mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Post deleted from Campus Feed ✓'),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete Post'),
          ),
        ],
      ),
    );
  }
}
