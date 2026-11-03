import 'package:flutter/foundation.dart';

class FeedCommentModel {
  final String id;
  final String postId;
  final String userId;
  final String authorName;
  final String authorStudentId;
  final String commentText;
  final DateTime createdAt;

  const FeedCommentModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.authorName,
    required this.authorStudentId,
    required this.commentText,
    required this.createdAt,
  });

  factory FeedCommentModel.fromJson(Map<String, dynamic> json) {
    return FeedCommentModel(
      id: json['id'] as String? ?? 'cmt_${DateTime.now().millisecondsSinceEpoch}',
      postId: (json['post_id'] ?? json['postId'] ?? '').toString(),
      userId: (json['user_id'] ?? json['author_id'] ?? json['userId'] ?? '').toString(),
      authorName: json['author_name'] as String? ?? json['authorName'] as String? ?? 'DIU Student',
      authorStudentId: json['author_student_id'] as String? ?? json['authorDept'] as String? ?? '',
      commentText: (json['comment_text'] ?? json['content'] ?? json['text'] ?? '').toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'post_id': postId,
      'user_id': userId,
      'author_name': authorName,
      'author_student_id': authorStudentId,
      'comment_text': commentText,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}

@immutable
class FeedPostModel {
  final String id;
  final String userId;
  final String authorName;
  final String authorStudentId;
  final String authorDepartment;
  final String? authorAvatar;
  final String content;
  final String category;
  final String tag;
  final String? imageUrl;
  final int likesCount;
  final int commentsCount;
  final bool isLiked;
  final DateTime createdAt;
  final List<FeedCommentModel> latestComments;

  const FeedPostModel({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.authorStudentId,
    required this.authorDepartment,
    this.authorAvatar,
    required this.content,
    required this.category,
    required this.tag,
    this.imageUrl,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLiked = false,
    required this.createdAt,
    this.latestComments = const [],
  });

  factory FeedPostModel.fromJson(Map<String, dynamic> json) {
    var rawComments = json['latest_comments'];
    List<FeedCommentModel> commentsList = [];
    if (rawComments is List) {
      commentsList = rawComments
          .map((c) => FeedCommentModel.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList();
    }

    return FeedPostModel(
      id: json['id'] as String? ?? 'post_${DateTime.now().millisecondsSinceEpoch}',
      userId: (json['user_id'] ?? json['author_id'] ?? '').toString(),
      authorName: json['author_name'] as String? ?? 'DIU Student',
      authorStudentId: json['author_student_id'] as String? ?? 'DIU-STU',
      authorDepartment: json['author_department'] as String? ?? 'CSE',
      authorAvatar: json['author_avatar'] as String?,
      content: json['content'] as String? ?? '',
      category: json['category'] as String? ?? 'Campus Life',
      tag: json['tag'] as String? ?? '#CampusLife',
      imageUrl: json['image_url'] as String?,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      isLiked: json['is_liked'] == true || json['is_liked'] == 1,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      latestComments: commentsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'author_name': authorName,
      'author_student_id': authorStudentId,
      'author_department': authorDepartment,
      'author_avatar': authorAvatar,
      'content': content,
      'category': category,
      'tag': tag,
      'image_url': imageUrl,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'is_liked': isLiked,
      'created_at': createdAt.toIso8601String(),
      'latest_comments': latestComments.map((c) => c.toJson()).toList(),
    };
  }

  FeedPostModel copyWith({
    String? id,
    String? userId,
    String? authorName,
    String? authorStudentId,
    String? authorDepartment,
    String? authorAvatar,
    String? content,
    String? category,
    String? tag,
    String? imageUrl,
    int? likesCount,
    int? commentsCount,
    bool? isLiked,
    DateTime? createdAt,
    List<FeedCommentModel>? latestComments,
  }) {
    return FeedPostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      authorStudentId: authorStudentId ?? this.authorStudentId,
      authorDepartment: authorDepartment ?? this.authorDepartment,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      content: content ?? this.content,
      category: category ?? this.category,
      tag: tag ?? this.tag,
      imageUrl: imageUrl ?? this.imageUrl,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt ?? this.createdAt,
      latestComments: latestComments ?? this.latestComments,
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
