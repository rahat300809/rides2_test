import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/feed/data/models/feed_post_model.dart';

class FeedState {
  final List<FeedPostModel> posts;
  final bool isLoading;
  final bool isSubmitting;
  final String selectedCategory;
  final String? errorMessage;

  const FeedState({
    this.posts = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.selectedCategory = 'All',
    this.errorMessage,
  });

  List<FeedPostModel> get filteredPosts {
    if (selectedCategory == 'All') return posts;
    return posts.where((p) => p.category.toLowerCase() == selectedCategory.toLowerCase()).toList();
  }

  FeedState copyWith({
    List<FeedPostModel>? posts,
    bool? isLoading,
    bool? isSubmitting,
    String? selectedCategory,
    String? errorMessage,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      errorMessage: errorMessage,
    );
  }
}

class FeedNotifier extends StateNotifier<FeedState> {
  final Ref ref;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  FeedNotifier(this.ref) : super(const FeedState()) {
    fetchPosts();
  }

  String get _apiBaseUrl => AppConfig.current.apiBaseUrl;

  String? get _currentUserId => ref.read(authNotifierProvider).user?.id;

  void selectCategory(String category) {
    state = state.copyWith(selectedCategory: category);
  }

  Future<void> fetchPosts({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    if (!refresh && state.posts.isEmpty) {
      state = state.copyWith(isLoading: true, errorMessage: null);
    }

    try {
      final userId = _currentUserId;
      final uri = '$_apiBaseUrl/feed${userId != null ? '?user_id=$userId' : ''}';
      final response = await _dio.get(uri);

      if (response.statusCode == 200) {
        List rawList = [];
        if (response.data is List) {
          rawList = response.data as List;
        } else if (response.data is Map && response.data['posts'] is List) {
          rawList = response.data['posts'] as List;
        }
        final now = DateTime.now();
        final loadedPosts = rawList
            .map((item) => FeedPostModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((p) => now.difference(p.createdAt).inDays < 7)
            .toList();

        state = state.copyWith(
          posts: loadedPosts,
          isLoading: false,
          errorMessage: null,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint('[FeedNotifier] fetchPosts error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to load campus posts. Please check network connection.',
      );
    }
  }

  Future<bool> createPost({
    required String content,
    required String category,
    String? tag,
    String? imageUrl,
  }) async {
    if (content.trim().isEmpty) return false;

    state = state.copyWith(isSubmitting: true);
    final user = ref.read(authNotifierProvider).user;

    final body = {
      'user_id': user?.id ?? 'diu_${DateTime.now().millisecondsSinceEpoch}',
      'author_name': user?.name ?? 'DIU Student',
      'author_student_id': user?.studentId ?? '211-15-XXXXX',
      'author_department': user?.department ?? 'CSE',
      'author_avatar': user?.profilePhotoUrl ?? '',
      'content': content.trim(),
      'category': category,
      'tag': tag ?? '#${category.replaceAll(' ', '')}',
      'image_url': imageUrl ?? '',
    };

    try {
      final response = await _dio.post('$_apiBaseUrl/feed', data: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final postJson = response.data['post'];
        if (postJson != null) {
          final newPost = FeedPostModel.fromJson(Map<String, dynamic>.from(postJson as Map));
          // Prepend new post
          state = state.copyWith(
            posts: [newPost, ...state.posts],
            isSubmitting: false,
          );
          return true;
        }
      }
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      debugPrint('[FeedNotifier] createPost error: $e');
      state = state.copyWith(isSubmitting: false, errorMessage: 'Failed to create post. Try again.');
      return false;
    }
  }

  Future<void> toggleLike(String postId) async {
    final userId = _currentUserId ?? 'anonymous';
    final index = state.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final targetPost = state.posts[index];
    final wasLiked = targetPost.isLiked;
    final updatedPost = targetPost.copyWith(
      isLiked: !wasLiked,
      likesCount: wasLiked ? (targetPost.likesCount - 1).clamp(0, 999999) : targetPost.likesCount + 1,
    );

    // Optimistic local update
    final updatedList = List<FeedPostModel>.from(state.posts);
    updatedList[index] = updatedPost;
    state = state.copyWith(posts: updatedList);

    try {
      final response = await _dio.post(
        '$_apiBaseUrl/feed/$postId/like',
        data: {'user_id': userId},
      );

      if (response.statusCode == 200 && response.data != null) {
        final serverLiked = response.data['is_liked'] as bool? ?? !wasLiked;
        final serverLikesCount = (response.data['likes_count'] as num?)?.toInt() ?? updatedPost.likesCount;
        
        final refreshedPost = updatedPost.copyWith(
          isLiked: serverLiked,
          likesCount: serverLikesCount,
        );
        final syncList = List<FeedPostModel>.from(state.posts);
        final curIdx = syncList.indexWhere((p) => p.id == postId);
        if (curIdx != -1) {
          syncList[curIdx] = refreshedPost;
          state = state.copyWith(posts: syncList);
        }
      }
    } catch (e) {
      debugPrint('[FeedNotifier] toggleLike error: $e');
      // Revert if error
      final revertList = List<FeedPostModel>.from(state.posts);
      final curIdx = revertList.indexWhere((p) => p.id == postId);
      if (curIdx != -1) {
        revertList[curIdx] = targetPost;
        state = state.copyWith(posts: revertList);
      }
    }
  }

  Future<List<FeedCommentModel>> fetchComments(String postId) async {
    try {
      final res = await _dio.get('$_apiBaseUrl/feed/$postId/comments');
      if (res.statusCode == 200) {
        List rawList = [];
        if (res.data is List) {
          rawList = res.data as List;
        } else if (res.data is Map && res.data['comments'] is List) {
          rawList = res.data['comments'] as List;
        }
        final list = rawList
            .map((item) => FeedCommentModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        return list;
      }
    } catch (e) {
      debugPrint('[FeedNotifier] fetchComments error: $e');
    }
    return [];
  }

  Future<FeedCommentModel?> addComment(String postId, String commentText) async {
    final text = commentText.trim();
    if (text.isEmpty) return null;

    final user = ref.read(authNotifierProvider).user;
    final body = {
      'user_id': user?.id ?? 'diu_${DateTime.now().millisecondsSinceEpoch}',
      'author_id': user?.id ?? 'diu_${DateTime.now().millisecondsSinceEpoch}',
      'author_name': user?.name ?? 'DIU Student',
      'author_student_id': user?.studentId ?? 'DIU-STU',
      'author_dept': user?.department ?? 'CSE',
      'comment_text': text,
      'content': text,
      'text': text,
    };

    try {
      final res = await _dio.post('$_apiBaseUrl/feed/$postId/comments', data: body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final cmtJson = res.data['comment'];
        if (cmtJson != null) {
          final cmt = FeedCommentModel.fromJson(Map<String, dynamic>.from(cmtJson as Map));
          // Update local post comment count
          final index = state.posts.indexWhere((p) => p.id == postId);
          if (index != -1) {
            final p = state.posts[index];
            final updatedPost = p.copyWith(
              commentsCount: p.commentsCount + 1,
              latestComments: [cmt, ...p.latestComments],
            );
            final updatedList = List<FeedPostModel>.from(state.posts);
            updatedList[index] = updatedPost;
            state = state.copyWith(posts: updatedList);
          }
          return cmt;
        }
      }
    } catch (e) {
      debugPrint('[FeedNotifier] addComment error: $e');
    }
    return null;
  }

  Future<bool> deletePost(String postId) async {
    final user = ref.read(authNotifierProvider).user;
    try {
      final res = await _dio.delete('$_apiBaseUrl/feed/$postId?user_id=${user?.id ?? ''}');
      if (res.statusCode == 200) {
        state = state.copyWith(
          posts: state.posts.where((p) => p.id != postId).toList(),
        );
        return true;
      }
    } catch (e) {
      debugPrint('[FeedNotifier] deletePost error: $e');
    }
    return false;
  }

  void handleWebSocketEvent(String event, Map<String, dynamic> data) {
    if (event == 'campus_feed_new_post') {
      final postData = data['post'];
      if (postData is Map<String, dynamic>) {
        final newPost = FeedPostModel.fromJson(postData);
        if (!state.posts.any((p) => p.id == newPost.id)) {
          state = state.copyWith(posts: [newPost, ...state.posts]);
        }
      }
    } else if (event == 'campus_feed_like_updated') {
      final postId = data['post_id']?.toString();
      final likesCount = (data['likes_count'] as num?)?.toInt();
      if (postId != null && likesCount != null) {
        final index = state.posts.indexWhere((p) => p.id == postId);
        if (index != -1) {
          final p = state.posts[index];
          final updated = p.copyWith(likesCount: likesCount);
          final updatedList = List<FeedPostModel>.from(state.posts);
          updatedList[index] = updated;
          state = state.copyWith(posts: updatedList);
        }
      }
    } else if (event == 'campus_feed_comment_added') {
      final postId = data['post_id']?.toString();
      final commentsCount = (data['comments_count'] as num?)?.toInt();
      if (postId != null) {
        final index = state.posts.indexWhere((p) => p.id == postId);
        if (index != -1) {
          final p = state.posts[index];
          final updated = p.copyWith(commentsCount: commentsCount ?? (p.commentsCount + 1));
          final updatedList = List<FeedPostModel>.from(state.posts);
          updatedList[index] = updated;
          state = state.copyWith(posts: updatedList);
        }
      }
    } else if (event == 'campus_feed_post_deleted') {
      final postId = data['post_id']?.toString();
      if (postId != null) {
        state = state.copyWith(
          posts: state.posts.where((p) => p.id != postId).toList(),
        );
      }
    }
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  return FeedNotifier(ref);
});

final userFeedPostsProvider = Provider.family<List<FeedPostModel>, String>((ref, userId) {
  final allPosts = ref.watch(feedProvider).posts;
  return allPosts.where((p) => p.userId == userId).toList();
});
