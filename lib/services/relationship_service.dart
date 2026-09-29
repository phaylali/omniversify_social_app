import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who the signed-in user keeps up with (follows) and who they have asked to
/// get acquainted with (friend request).
///
/// Both sets mirror into [ValueNotifier]s so profile buttons, the scrolls
/// "Keep up" tab and the inline follow pill rebuild the moment either changes.
class RelationshipService {
  RelationshipService._();

  static final RelationshipService instance = RelationshipService._();

  static const String _followingKey = 'rel_following_v1';
  static const String _requestsKey = 'rel_requests_v1';

  /// Handles the user follows — drives the scrolls "Keep up" tab.
  final ValueNotifier<Set<String>> following = ValueNotifier(<String>{});

  /// Handles with a pending "get acquainted" request.
  final ValueNotifier<Set<String>> requests = ValueNotifier(<String>{});

  bool _loaded = false;

  /// Loads persisted relationships — call once before the first frame.
  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    following.value = (prefs.getStringList(_followingKey) ?? const []).toSet();
    requests.value = (prefs.getStringList(_requestsKey) ?? const []).toSet();
    _loaded = true;
  }

  bool isFollowing(String handle) => following.value.contains(handle);

  bool hasRequested(String handle) => requests.value.contains(handle);

  /// Follows or unfollows [handle]. Returns true when now following.
  bool toggleFollow(String handle) {
    final next = {...following.value};
    final nowFollowing = !next.contains(handle);
    if (nowFollowing) {
      next.add(handle);
    } else {
      next.remove(handle);
    }
    following.value = next;
    _persist(_followingKey, next);
    return nowFollowing;
  }

  /// Sends or withdraws a friend request to [handle]. Returns true when sent.
  bool toggleRequest(String handle) {
    final next = {...requests.value};
    final nowRequested = !next.contains(handle);
    if (nowRequested) {
      next.add(handle);
    } else {
      next.remove(handle);
    }
    requests.value = next;
    _persist(_requestsKey, next);
    return nowRequested;
  }

  Future<void> _persist(String key, Set<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, value.toList());
  }
}
