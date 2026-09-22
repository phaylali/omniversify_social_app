import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/post.dart';
import '../data/dummy_data.dart';

class Comment {
  final String id;
  final PostUser user;
  final String text;
  final DateTime timestamp;

  const Comment({
    required this.id,
    required this.user,
    required this.text,
    required this.timestamp,
  });
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

  const PostState({
    required this.likes,
    required this.liked,
    required this.comments,
    required this.shares,
    this.saved = false,
    required this.likers,
    required this.commentList,
    required this.sharers,
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
      ),
    );
  }

  List<PostUser> _generateSharers(int count) {
    return _generateLikers(count);
  }

  void toggleLike(String postId) {
    final current = state[postId];
    if (current == null) return;
    state = {
      ...state,
      postId: current.copyWith(
        liked: !current.liked,
        likes: current.liked ? current.likes - 1 : current.likes + 1,
      ),
    };
  }

  void addComment(String postId, String text, PostUser user) {
    final current = state[postId];
    if (current == null) return;
    final comment = Comment(
      id: '$postId-${current.comments}',
      user: user,
      text: text,
      timestamp: DateTime.now(),
    );
    state = {
      ...state,
      postId: current.copyWith(
        comments: current.comments + 1,
        commentList: [comment, ...current.commentList],
      ),
    };
  }

  void share(String postId) {
    final current = state[postId];
    if (current == null) return;
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
