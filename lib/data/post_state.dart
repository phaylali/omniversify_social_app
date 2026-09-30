import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/post.dart';
import '../data/dummy_data.dart';
import '../services/daily_tasks.dart';

class Comment {
  final String id;
  final PostUser user;
  final String text;
  final DateTime timestamp;

  /// Local file path of an attached image (jpeg/jpg/png/webp/gif), if any.
  final String? imagePath;

  /// Raw image bytes — used on web where there is no file path.
  final Uint8List? imageBytes;

  final bool likedByMe;
  final int likeCount;

  /// Id of the comment this one replies to, for one level of nesting.
  final String? replyTo;

  const Comment({
    required this.id,
    required this.user,
    required this.text,
    required this.timestamp,
    this.imagePath,
    this.imageBytes,
    this.likedByMe = false,
    this.likeCount = 0,
    this.replyTo,
  });

  Comment copyWith({
    String? imagePath,
    Uint8List? imageBytes,
    bool? likedByMe,
    int? likeCount,
    String? replyTo,
  }) {
    return Comment(
      id: id,
      user: user,
      text: text,
      timestamp: timestamp,
      imagePath: imagePath ?? this.imagePath,
      imageBytes: imageBytes ?? this.imageBytes,
      likedByMe: likedByMe ?? this.likedByMe,
      likeCount: likeCount ?? this.likeCount,
      replyTo: replyTo ?? this.replyTo,
    );
  }
}

class PostState {
  final int likes;
  final bool liked;
  final int comments;
  final int shares;
  final bool saved;
  final List<PostUser> likers;
  final List<Comment> commentList;
  final List<PostUser> sharers;

  /// Mirrors the source post's audience so widgets can gate sharing by id.
  final PostVisibility visibility;

  const PostState({
    required this.likes,
    required this.liked,
    required this.comments,
    required this.shares,
    this.saved = false,
    required this.likers,
    required this.commentList,
    required this.sharers,
    this.visibility = PostVisibility.public,
  });

  PostState copyWith({
    int? likes,
    bool? liked,
    int? comments,
    int? shares,
    bool? saved,
    List<PostUser>? likers,
    List<Comment>? commentList,
    List<PostUser>? sharers,
    PostVisibility? visibility,
  }) {
    return PostState(
      likes: likes ?? this.likes,
      liked: liked ?? this.liked,
      comments: comments ?? this.comments,
      shares: shares ?? this.shares,
      saved: saved ?? this.saved,
      likers: likers ?? this.likers,
      commentList: commentList ?? this.commentList,
      sharers: sharers ?? this.sharers,
      visibility: visibility ?? this.visibility,
    );
  }
}

class PostStateNotifier extends StateNotifier<Map<String, PostState>> {
  PostStateNotifier() : super({}) {
    // Initialize from dummy data
    for (final post in dummyPosts) {
      state = {
        ...state,
        post.id: PostState(
          likes: post.likes,
          liked: post.liked,
          comments: post.comments,
          shares: post.shares,
          likers: _generateLikers(post.likes),
          commentList: _generateComments(post.id, post.comments),
          sharers: _generateSharers(post.shares),
          visibility: post.visibility,
        ),
      };
    }
    // Scrolls share the same state map so they comment/like like posts do.
    for (final scroll in dummyScrolls) {
      state = {
        ...state,
        scroll.id: PostState(
          likes: scroll.likes,
          liked: false,
          comments: scroll.comments,
          shares: 0,
          likers: _generateLikers(scroll.likes),
          commentList: _generateComments(scroll.id, scroll.comments),
          sharers: const [],
          visibility: scroll.visibility,
        ),
      };
    }
  }

  List<PostUser> _generateLikers(int count) {
    final names = [
      ('Ahmed', '@ahmed_m', false),
      ('Sara', '@sara_dev', true),
      ('Omar', '@omar_x', false),
      ('Fatima', '@fatima_art', true),
      ('Karim', '@karim_c', false),
      ('Amina', '@amina_w', false),
      ('Youssef', '@youssef_2', false),
      ('Nadia', '@nadia_p', true),
      ('Hamza', '@hamza_g', false),
      ('Leila', '@leila_s', false),
    ];
    return List.generate(
      count.clamp(0, names.length),
      (i) => PostUser(name: names[i].$1, handle: names[i].$2, verified: names[i].$3),
    );
  }

  List<Comment> _generateComments(String postId, int count) {
    final texts = [
      'This is amazing!',
      'Love this so much',
      'Can\'t wait to try this',
      'Incredible work',
      'Need to check this out',
      'One of my favorites',
      'Absolutely brilliant',
      'This made my day',
    ];
    final users = [
      PostUser(name: 'Ahmed', handle: '@ahmed_m'),
      PostUser(name: 'Sara', handle: '@sara_dev', verified: true),
      PostUser(name: 'Omar', handle: '@omar_x'),
      PostUser(name: 'Fatima', handle: '@fatima_art', verified: true),
    ];
    return List.generate(
      count.clamp(0, texts.length),
      (i) => Comment(
        id: '$postId-c$i',
        user: users[i % users.length],
        text: texts[i],
        timestamp: DateTime.now().subtract(Duration(hours: i + 1)),
        likeCount: (i * 7) % 23,
      ),
    );
  }

  List<PostUser> _generateSharers(int count) {
    return _generateLikers(count);
  }

  void toggleLike(String postId) {
    final current = state[postId];
    if (current == null) return;
    // Only a like counts — unliking again can't run the task up and down.
    if (!current.liked) DailyTasks.instance.recordLike();
    state = {
      ...state,
      postId: current.copyWith(
        liked: !current.liked,
        likes: current.liked ? current.likes - 1 : current.likes + 1,
      ),
    };
  }

  void addComment(
    String postId,
    String text,
    PostUser user, {
    String? imagePath,
    Uint8List? imageBytes,
    String? replyTo,
  }) {
    final current = state[postId];
    if (current == null) return;
    final comment = Comment(
      id: '$postId-c${current.comments}',
      user: user,
      text: text,
      timestamp: DateTime.now(),
      imagePath: imagePath,
      imageBytes: imageBytes,
      replyTo: replyTo,
    );
    state = {
      ...state,
      postId: current.copyWith(
        comments: current.comments + 1,
        commentList: [comment, ...current.commentList],
      ),
    };
    DailyTasks.instance.recordComment();
  }

  void toggleCommentLike(String postId, String commentId) {
    final current = state[postId];
    if (current == null) return;
    state = {
      ...state,
      postId: current.copyWith(
        commentList: [
          for (final c in current.commentList)
            c.id == commentId
                ? c.copyWith(
                    likedByMe: !c.likedByMe,
                    likeCount: c.likedByMe ? c.likeCount - 1 : c.likeCount + 1,
                  )
                : c,
        ],
      ),
    };
  }

  void share(String postId) {
    final current = state[postId];
    if (current == null) return;
    DailyTasks.instance.recordShare();
    state = {
      ...state,
      postId: current.copyWith(shares: current.shares + 1),
    };
  }

  void toggleBookmark(String postId) {
    final current = state[postId];
    if (current == null) return;
    state = {
      ...state,
      postId: current.copyWith(saved: !current.saved),
    };
  }
}

final postStateProvider = StateNotifierProvider<PostStateNotifier, Map<String, PostState>>((ref) {
  return PostStateNotifier();
});

PostState getPostState(WidgetRef ref, String postId) {
  return ref.watch(postStateProvider)[postId] ?? const PostState(
    likes: 0, liked: false, comments: 0, shares: 0,
    likers: [], commentList: [], sharers: [],
  );
}
