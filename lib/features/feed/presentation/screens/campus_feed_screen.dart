import 'package:diu_ride/shared/widgets/visitor_mode_dialog.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/feed/data/models/feed_post_model.dart';
import 'package:diu_ride/features/feed/presentation/providers/feed_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/profile/presentation/screens/profile_screen.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';

class CampusFeedScreen extends ConsumerStatefulWidget {
  final String? initialCategory;

  const CampusFeedScreen({super.key, this.initialCategory});

  @override
  ConsumerState<CampusFeedScreen> createState() => _CampusFeedScreenState();
}

class _CampusFeedScreenState extends ConsumerState<CampusFeedScreen> {
  final List<Map<String, dynamic>> _categories = const [
    {'name': 'All', 'icon': Icons.public, 'color': Color(0xFF006699)},
    {'name': 'Carpool', 'icon': Icons.two_wheeler, 'color': Color(0xFF16A34A)},
    {'name': 'Campus Life', 'icon': Icons.school, 'color': Color(0xFFFFA000)},
    {'name': 'Notice', 'icon': Icons.campaign, 'color': Color(0xFFE65100)},
    {'name': 'Lost & Found', 'icon': Icons.search, 'color': Color(0xFFD97706)},
    {'name': 'Question', 'icon': Icons.help_outline, 'color': Color(0xFF0284C7)},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(feedProvider.notifier).selectCategory(widget.initialCategory!);
      });
    }
  }

  void _openCreatePostModal({String initialCategory = 'Campus Life', String? initialImageUrl}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreatePostModalSheet(
        initialCategory: initialCategory,
        initialImageUrl: initialImageUrl,
      ),
    );
  }

  void _showCommentsBottomSheet(FeedPostModel post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CommentsSheet(post: post),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Widget imageWidget;
    if (imageUrl.startsWith('data:image')) {
      try {
        final comma = imageUrl.indexOf(',');
        final b64 = comma != -1 ? imageUrl.substring(comma + 1) : imageUrl;
        imageWidget = Image.memory(
          base64Decode(b64),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
          ),
        );
      } catch (_) {
        imageWidget = const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        );
      }
    } else {
      imageWidget = Image.network(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        ),
      );
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
            title: const Text('Campus Photo', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: imageWidget,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedImageWidget(String url, {double? height, BoxFit fit = BoxFit.cover}) {
    if (url.startsWith('data:image')) {
      try {
        final comma = url.indexOf(',');
        final b64 = comma != -1 ? url.substring(comma + 1) : url;
        return Image.memory(
          base64Decode(b64),
          width: double.infinity,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
        );
      } catch (_) {}
    }
    return Image.network(
      url,
      width: double.infinity,
      height: height,
      fit: fit,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return Container(
          height: height ?? 220,
          color: const Color(0xFFF1F5F9),
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006699)),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 6),
          Text('DIU Campus Photo', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedProvider);
    final user = ref.watch(authNotifierProvider).user;
    final posts = feedState.filteredPosts;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF0F172A), size: 20),
                onPressed: () => Navigator.of(context).pop(),
              )
            : Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: const Color(0xFF006699),
                      child: Text(
                        user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'S',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Campus News Feed',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    fontSize: 17.5,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF006699).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'DIU',
                    style: TextStyle(
                      color: Color(0xFF006699),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'Student stories, carpool shouts & campus photos',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                _openCreatePostModal();
              },
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Post', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006699),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF006699)),
            tooltip: 'Refresh Feed',
            onPressed: () => ref.read(feedProvider.notifier).fetchPosts(refresh: true),
          ),
        ],
      ),

      // Prominent Floating Action Button for Posting
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          _openCreatePostModal();
        },
        icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white, size: 20),
        label: const Text(
          'Post to Feed',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2),
        ),
        backgroundColor: const Color(0xFF006699),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),

      body: RefreshIndicator(
        onRefresh: () => ref.read(feedProvider.notifier).fetchPosts(refresh: true),
        color: const Color(0xFF006699),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // 1. Facebook-Style Composer Box
            SliverToBoxAdapter(
              child: _buildFacebookComposerCard(user),
            ),

            // 2. Category Filter Pills
            SliverToBoxAdapter(
              child: _buildCategoryFilters(feedState.selectedCategory),
            ),

            // 3. Loading Indicator
            if (feedState.isLoading && feedState.posts.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF006699)),
                      SizedBox(height: 12),
                      Text('Loading campus feed...', style: TextStyle(color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              )
            // Empty State
            else if (posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE2E8F0),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.forum_outlined, size: 48, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No posts in "${feedState.selectedCategory}" yet',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Be the first student to post a commute ride, photo, or campus update!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => _openCreatePostModal(),
                          icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                          label: const Text('Create First Post with Photo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006699),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            // 4. Facebook-Style Feed Posts List
            else
              SliverPadding(
                padding: const EdgeInsets.only(left: 10, right: 10, bottom: 84),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final post = posts[index];
                      return _buildFacebookPostCard(post, user?.id);
                    },
                    childCount: posts.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Facebook-Style Top Composer Box
  Widget _buildFacebookComposerCard(dynamic user) {
    final userName = user?.name ?? 'DIU Student';
    final userInitial = userName.isNotEmpty ? userName[0].toUpperCase() : 'D';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF006699).withOpacity(0.12),
                  child: Text(
                    userInitial,
                    style: const TextStyle(
                      color: Color(0xFF006699),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _openCreatePostModal(),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        "What's on your mind, ${userName.split(' ')[0]}?",
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _openCreatePostModal(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Post', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006699),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          // Quick Post Actions
          Row(
            children: [
              Expanded(
                child: _buildComposerActionBtn(
                  icon: Icons.photo_library_rounded,
                  color: const Color(0xFF16A34A),
                  label: 'Photo',
                  onTap: () => _openCreatePostModal(initialImageUrl: 'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?w=800&q=80'),
                ),
              ),
              Container(width: 1, height: 22, color: const Color(0xFFF1F5F9)),
              Expanded(
                child: _buildComposerActionBtn(
                  icon: Icons.two_wheeler_rounded,
                  color: const Color(0xFFE65100),
                  label: 'Carpool',
                  onTap: () => _openCreatePostModal(initialCategory: 'Carpool'),
                ),
              ),
              Container(width: 1, height: 22, color: const Color(0xFFF1F5F9)),
              Expanded(
                child: _buildComposerActionBtn(
                  icon: Icons.campaign_rounded,
                  color: const Color(0xFF006699),
                  label: 'Notice',
                  onTap: () => _openCreatePostModal(initialCategory: 'Notice'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposerActionBtn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilters(String currentSelection) {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final name = cat['name'] as String;
          final icon = cat['icon'] as IconData;
          final color = cat['color'] as Color;
          final isSelected = currentSelection.toLowerCase() == name.toLowerCase();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(feedProvider.notifier).selectCategory(name);
              },
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF006699) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF006699) : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF006699).withOpacity(0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: isSelected ? Colors.white : color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Facebook-Style Feed Post Card
  Widget _buildFacebookPostCard(FeedPostModel post, String? currentUserId) {
    final user = ref.read(authNotifierProvider).user;
    final isMe = (currentUserId != null && currentUserId.isNotEmpty && post.userId == currentUserId) ||
        (user?.studentId != null && user!.studentId.isNotEmpty && post.authorStudentId == user.studentId) ||
        (user?.name != null && user!.name.isNotEmpty && post.authorName == user.name);
    final isCarpool = post.category.toLowerCase().contains('carpool');

    Color categoryColor = const Color(0xFFFFA000);
    if (post.category.toLowerCase().contains('carpool')) {
      categoryColor = const Color(0xFF16A34A);
    } else if (post.category.toLowerCase().contains('notice')) {
      categoryColor = const Color(0xFFE65100);
    } else if (post.category.toLowerCase().contains('lost')) {
      categoryColor = const Color(0xFFD97706);
    } else if (post.category.toLowerCase().contains('question')) {
      categoryColor = const Color(0xFF0284C7);
    }

    final hasImage = post.imageUrl != null && post.imageUrl!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0).withOpacity(0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Post Header: Author Avatar, Name, Dept, Time
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => _showAuthorProfileDialog(context, post),
                  borderRadius: BorderRadius.circular(20),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: categoryColor.withOpacity(0.12),
                    child: Text(
                      post.authorName.isNotEmpty ? post.authorName[0].toUpperCase() : 'S',
                      style: TextStyle(
                        color: categoryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _showAuthorProfileDialog(context, post),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.authorName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Color(0xFF0F172A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: categoryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                post.category,
                                style: TextStyle(
                                  color: categoryColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '${post.authorStudentId} • ${post.authorDepartment}',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(width: 5),
                            const Text('•', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                            const SizedBox(width: 5),
                            Text(
                              post.timeAgo,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (isMe)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: Color(0xFF94A3B8)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (val) {
                      if (val == 'delete') {
                        _confirmDeletePost(post.id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Delete Post', style: TextStyle(color: Colors.red, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // 2. Post Text Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text(
              post.content,
              style: const TextStyle(
                fontSize: 14.5,
                color: Color(0xFF1E293B),
                height: 1.45,
              ),
            ),
          ),

          if (post.tag.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Text(
                post.tag,
                style: TextStyle(
                  color: categoryColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),

          // 3. Post Image (Facebook-Style Photo Card)
          if (hasImage) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: GestureDetector(
                  onTap: () => _showFullScreenImage(context, post.imageUrl!),
                  child: Hero(
                    tag: 'feed_img_${post.id}',
                    child: _buildFeedImageWidget(post.imageUrl!),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // 4. Reaction Counters Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                if (post.likesCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE11D48),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite, size: 10, color: Colors.white),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${post.likesCount}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ],
                const Spacer(),
                if (post.commentsCount > 0)
                  Text(
                    '${post.commentsCount} comments',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // 5. Action Buttons: Like, Comment, Carpool Connect, Share
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              children: [
                // Like Button
                InkWell(
                  onTap: () {
                    if (checkAndEnforceVisitorMode(context, ref, actionName: 'like posts')) return;
                    HapticFeedback.lightImpact();
                    ref.read(feedProvider.notifier).toggleLike(post.id);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      children: [
                        Icon(
                          post.isLiked ? Icons.favorite : Icons.favorite_border,
                          size: 19,
                          color: post.isLiked ? const Color(0xFFE11D48) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Like',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: post.isLiked ? FontWeight.bold : FontWeight.w500,
                            color: post.isLiked ? const Color(0xFFE11D48) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Comment Button
                InkWell(
                  onTap: () => _showCommentsBottomSheet(post),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Color(0xFF64748B)),
                        SizedBox(width: 6),
                        Text(
                          'Comment',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Message / Carpool Connect button if it's not the user's own post
                if (!isMe) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      final currentUserId = user?.id ?? '';
                      final peerId = post.userId;
                      final sorted = [currentUserId, peerId]..sort();
                      final convId = 'peer_dm_${sorted[0]}__${sorted[1]}';
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            rideId: convId,
                            driverName: post.authorName,
                            peerName: post.authorName,
                            peerId: post.userId,
                            vehicleModel: isCarpool ? 'DIU Carpool Post' : 'DIU Campus Feed',
                            peerRole: isCarpool ? 'Biker' : 'Student',
                          ),
                        ),
                      );
                    },
                    icon: Icon(isCarpool ? Icons.two_wheeler : Icons.chat_bubble_outline_rounded, size: 14),
                    label: Text(isCarpool ? 'Book / Chat' : 'Message', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCarpool ? const Color(0xFF16A34A) : const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Share Button
                IconButton(
                  icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF64748B)),
                  tooltip: 'Share Post',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: '${post.authorName} on DIU Ride Feed:\n${post.content}\n${post.tag}',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Post copied to clipboard!'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePost(String postId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Post?'),
        content: const Text('This will remove your post from the DIU Campus Feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(feedProvider.notifier).deletePost(postId);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAuthorProfileDialog(BuildContext context, FeedPostModel post) {
    final user = ref.read(authNotifierProvider).user;
    final isMe = (user?.id != null && post.userId == user!.id) ||
        (user?.studentId != null && post.authorStudentId == user!.studentId);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: const Color(0xFF006699).withOpacity(0.12),
                  child: Text(
                    post.authorName.isNotEmpty ? post.authorName[0].toUpperCase() : 'S',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF006699),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified, color: Colors.white, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              post.authorName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'DIU Verified Student • ${post.authorDepartment}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Student ID:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      Text(post.authorStudentId, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Department:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      Text(post.authorDepartment, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Campus Category:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      Text(post.category, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF006699))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!isMe) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    final currentUserId = user?.id ?? '';
                    final peerId = post.userId;
                    final sorted = [currentUserId, peerId]..sort();
                    final convId = 'peer_dm_${sorted[0]}__${sorted[1]}';
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: convId,
                          driverName: post.authorName,
                          peerName: post.authorName,
                          peerId: post.userId,
                          vehicleModel: 'DIU Campus Feed',
                          peerRole: 'Student',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                  label: const Text('Send Message in Inbox', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    DirectCallService.showCallOptions(
                      context,
                      peerName: post.authorName,
                      phoneNumber: '01700000000',
                      peerRole: 'Student',
                      peerDept: post.authorDepartment,
                    );
                  },
                  icon: const Icon(Icons.phone_in_talk_rounded, size: 16),
                  label: const Text('Call Student', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF16A34A),
                    side: const BorderSide(color: Color(0xFF16A34A)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
            ),
          ],
        ),
      ),
    );
  }
}

// Modal Sheet for Creating a Post with Images & Presets
class _CreatePostModalSheet extends ConsumerStatefulWidget {
  final String initialCategory;
  final String? initialImageUrl;

  const _CreatePostModalSheet({
    required this.initialCategory,
    this.initialImageUrl,
  });

  @override
  ConsumerState<_CreatePostModalSheet> createState() => _CreatePostModalSheetState();
}

class _CreatePostModalSheetState extends ConsumerState<_CreatePostModalSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _imageUrlCtrl = TextEditingController();
  late String _selectedCategory;
  String? _selectedImage;
  bool _isUploadingImage = false;

  Future<void> _pickImageFromDevice() async {
    setState(() => _isUploadingImage = true);
    HapticFeedback.lightImpact();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 82,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        if (mounted) {
          setState(() {
            _selectedImage = base64String;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select image from gallery: $e'),
            backgroundColor: const Color(0xFFE65100),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  final List<Map<String, String>> _sampleCampusPhotos = const [
    {
      'label': 'Campus Gate 1',
      'url': 'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?w=800&q=80',
    },
    {
      'label': 'Central Library',
      'url': 'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800&q=80',
    },
    {
      'label': 'Carpool Bike',
      'url': 'https://images.unsplash.com/photo-1558981403-c5f9899a28bc?w=800&q=80',
    },
    {
      'label': 'Campus Cafeteria',
      'url': 'https://images.unsplash.com/photo-1606567595334-d39972c85dbe?w=800&q=80',
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _selectedImage = widget.initialImageUrl;
    if (_selectedImage != null) {
      _imageUrlCtrl.text = _selectedImage!;
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (checkAndEnforceVisitorMode(context, ref, actionName: 'publish a post to campus feed')) return;
    final text = _textCtrl.text.trim();
    final img = _selectedImage?.trim();

    if (text.isEmpty && (img == null || img.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write something or attach a photo.')),
      );
      return;
    }

    final success = await ref.read(feedProvider.notifier).createPost(
          content: text.isNotEmpty ? text : 'Shared a campus photo 📸',
          category: _selectedCategory,
          imageUrl: (img != null && img.isNotEmpty) ? img : null,
        );

    if (success && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Your post is live on DIU Campus Feed!'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final userName = user?.name ?? 'DIU Student';
    final userDept = user?.department ?? 'CSE';
    final isSubmitting = ref.watch(feedProvider).isSubmitting;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header: Title & Close Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Text(
                  'Create Campus Post',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006699),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Post', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Author row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF006699).withOpacity(0.12),
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'D',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF006699), fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F172A)),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$userDept • DIU Community',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Post Content Input
                TextField(
                  controller: _textCtrl,
                  maxLines: 5,
                  minLines: 3,
                  autofocus: true,
                  style: const TextStyle(fontSize: 15.5, color: Color(0xFF0F172A), height: 1.45),
                  decoration: const InputDecoration(
                    hintText: "What's happening on campus? Share a commute, exam question, or campus photo...",
                    hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 12),

                // Category chips selector
                const Text(
                  'Post Category',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    'Campus Life',
                    'Carpool',
                    'Notice',
                    'Lost & Found',
                    'Question',
                  ].map((cat) {
                    final isSel = _selectedCategory == cat;
                    return ChoiceChip(
                      label: Text(cat),
                      selected: isSel,
                      selectedColor: const Color(0xFF006699),
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : const Color(0xFF334155),
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      backgroundColor: const Color(0xFFF1F5F9),
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = cat);
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 18),

                // Upload Campus Photo from Device Gallery
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Attach Campus Photo',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                    ),
                    if (_selectedImage != null)
                      TextButton.icon(
                        onPressed: () => setState(() => _selectedImage = null),
                        icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                        label: const Text(
                          'Remove Photo',
                          style: TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_selectedImage != null) ...[
                  // Selected Image Preview Card
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _selectedImage!.startsWith('data:image')
                              ? Image.memory(
                                  base64Decode(
                                    _selectedImage!.contains(',')
                                        ? _selectedImage!.substring(_selectedImage!.indexOf(',') + 1)
                                        : _selectedImage!,
                                  ),
                                  width: double.infinity,
                                  height: 180,
                                  fit: BoxFit.cover,
                                )
                              : Image.network(
                                  _selectedImage!,
                                  width: double.infinity,
                                  height: 180,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black.withOpacity(0.75),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.photo_library, size: 14),
                            label: const Text('Change Photo', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            onPressed: _pickImageFromDevice,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Empty Upload Button Card (Gallery Image Picker)
                  InkWell(
                    onTap: _pickImageFromDevice,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _isUploadingImage
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF16A34A)),
                                )
                              : const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF16A34A), size: 36),
                          const SizedBox(height: 8),
                          const Text(
                            'Upload Photo from Device / Gallery',
                            style: TextStyle(
                              color: Color(0xFF15803D),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Direct campus photo upload • No URL link needed',
                            style: TextStyle(color: Color(0xFF65A30D), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _sampleCampusPhotos.map((item) {
                        final isSel = _selectedImage == item['url'];
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedImage = item['url']);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF006699).withOpacity(0.12) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? const Color(0xFF006699) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.image, size: 14, color: Color(0xFF006699)),
                                const SizedBox(width: 5),
                                Text(
                                  item['label']!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                    color: isSel ? const Color(0xFF006699) : const Color(0xFF334155),
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

                // In-form prominent Publish Post button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006699),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(
                      isSubmitting ? 'Publishing...' : 'Publish Post to Campus Feed',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, letterSpacing: 0.2),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // Sticky Bottom Bar with Prominent Publish Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006699),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(
                    isSubmitting ? 'Publishing Post...' : 'Publish Post to Campus Feed',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  final FeedPostModel post;

  const _CommentsSheet({required this.post});

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  List<FeedCommentModel> _comments = [];
  bool _isLoading = true;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final list = await ref.read(feedProvider.notifier).fetchComments(widget.post.id);
    if (mounted) {
      setState(() {
        _comments = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _sendComment() async {
    if (checkAndEnforceVisitorMode(context, ref, actionName: 'comment on posts')) return;
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPosting = true);
    final newCmt = await ref.read(feedProvider.notifier).addComment(widget.post.id, text);
    if (mounted) {
      if (newCmt != null) {
        setState(() {
          _comments = [newCmt, ..._comments];
          _isPosting = false;
        });
        _commentCtrl.clear();
      } else {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Comments (${_comments.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF006699)))
                : _comments.isEmpty
                    ? Center(
                        child: Text(
                          'No comments yet. Start the conversation!',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final c = _comments[i];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      c.authorName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      c.timeAgo,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  c.commentText,
                                  style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        hintText: 'Write a comment as a DIU student...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isPosting ? null : _sendComment,
                    icon: _isPosting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, color: Color(0xFF006699)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
