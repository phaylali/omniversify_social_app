enum PostType { text, image, movie, tvShow, game, book, anime, location, workout, video }

class PostUser {
  final String name;
  final String handle;
  final String avatarUrl;
  final bool verified;

  const PostUser({
    required this.name,
    required this.handle,
    this.avatarUrl = '',
    this.verified = false,
  });
}

class MediaMetadata {
  final String title;
  final String? subtitle;
  final String? posterUrl;
  final String? director;
  final String? releaseDate;
  final double? rating;
  final List<String> genres;
  final String? synopsis;
  final String? studio;
  final int? episodes;
  final int? seasons;
  final String? aired;
  final String? status;

  const MediaMetadata({
    required this.title,
    this.subtitle,
    this.posterUrl,
    this.director,
    this.releaseDate,
    this.rating,
    this.genres = const [],
    this.synopsis,
    this.studio,
    this.episodes,
    this.seasons,
    this.aired,
    this.status,
  });
}

class GameMetadata {
  final String title;
  final String? posterUrl;
  final String? releaseDate;
  final List<String> platforms;
  final List<String> genres;
  final double? rating;
  final String? developer;
  final String? publisher;
  final String? synopsis;
  final int? playtime;

  const GameMetadata({
    required this.title,
    this.posterUrl,
    this.releaseDate,
    this.platforms = const [],
    this.genres = const [],
    this.rating,
    this.developer,
    this.publisher,
    this.synopsis,
    this.playtime,
  });
}

class BookMetadata {
  final String title;
  final String? coverUrl;
  final String? author;
  final String? publishDate;
  final int? pages;
  final String? genre;
  final double? rating;
  final String? synopsis;
  final String? isbn;

  const BookMetadata({
    required this.title,
    this.coverUrl,
    this.author,
    this.publishDate,
    this.pages,
    this.genre,
    this.rating,
    this.synopsis,
    this.isbn,
  });
}

class LocationMetadata {
  final String name;
  final String? imageUrl;
  final String? city;
  final String? country;
  final String? description;
  final double? rating;

  const LocationMetadata({
    required this.name,
    this.imageUrl,
    this.city,
    this.country,
    this.description,
    this.rating,
  });
}

class WorkoutMetadata {
  final String type;
  final int? durationMinutes;
  final int? calories;
  final String? notes;
  final String? intensity;

  const WorkoutMetadata({
    required this.type,
    this.durationMinutes,
    this.calories,
    this.notes,
    this.intensity,
  });
}

class Post {
  final String id;
  final PostUser user;
  final PostType type;
  final String text;
  final String? imageUrl;
  final String? videoUrl;
  final DateTime timestamp;
  final int likes;
  final int comments;
  final int shares;
  final bool liked;
  final MediaMetadata? movieData;
  final MediaMetadata? tvShowData;
  final MediaMetadata? animeData;
  final GameMetadata? gameData;
  final BookMetadata? bookData;
  final LocationMetadata? locationData;
  final WorkoutMetadata? workoutData;

  const Post({
    required this.id,
    required this.user,
    required this.type,
    required this.text,
    this.imageUrl,
    this.videoUrl,
    required this.timestamp,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.liked = false,
    this.movieData,
    this.tvShowData,
    this.animeData,
    this.gameData,
    this.bookData,
    this.locationData,
    this.workoutData,
  });
}
