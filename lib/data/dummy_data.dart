import '../models/post.dart';

const currentUser = PostUser(
  name: 'Phaylali',
  handle: '@phaylali',
  verified: true,
);

final dummyPosts = [
  // ── Text Post ──
  Post(
    id: '1',
    user: currentUser,
    type: PostType.text,
    text: 'Just finished setting up my entire media tracking system with Omniversify. Every movie, game, book, and anime — all in one place. This is going to be incredible.',
    timestamp: DateTime.now().subtract(const Duration(hours: 2)),
    likes: 24,
    comments: 5,
    shares: 3,
  ),

  // ── Movie Post ──
  Post(
    id: '2',
    user: currentUser,
    type: PostType.movie,
    text: 'Finally watched Dune Part Two. What a masterpiece!',
    timestamp: DateTime.now().subtract(const Duration(hours: 5)),
    likes: 89,
    comments: 12,
    shares: 7,
    movieData: const MediaMetadata(
      title: 'Dune: Part Two',
      subtitle: 'Denis Villeneuve',
      posterUrl: 'https://image.tmdb.org/t/p/w500/8b8R8l88Qje9dn9OE8PY05Nez7.jpg',
      director: 'Denis Villeneuve',
      releaseDate: '2024',
      rating: 8.5,
      genres: ['Sci-Fi', 'Adventure', 'Drama'],
      synopsis: 'Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen while on a path of revenge against the conspirators who destroyed his family. Facing a choice between the love of his life and the fate of the known universe, he endeavors to prevent a terrible future only he can foresee.',
    ),
  ),

  // ── TV Show Post ──
  Post(
    id: '3',
    user: PostUser(name: 'Amina', handle: '@amina_stream', verified: true),
    type: PostType.tvShow,
    text: 'Season 3 of The Bear is absolutely wild. The tension is unreal.',
    timestamp: DateTime.now().subtract(const Duration(hours: 8)),
    likes: 156,
    comments: 34,
    shares: 12,
    tvShowData: const MediaMetadata(
      title: 'The Bear',
      subtitle: 'Season 3',
      posterUrl: 'https://image.tmdb.org/t/p/w500/p2KvcsMZC5bREIVMz1Jz21OjO0r.jpg',
      releaseDate: '2024',
      rating: 8.7,
      genres: ['Drama', 'Comedy'],
      studio: 'FX Productions',
      seasons: 3,
      episodes: 28,
      aired: 'Jun 2024',
      status: 'Returning',
      synopsis: 'A young chef from the fine dining world returns to Chicago to run his family\'s Italian beef sandwich shop. The series explores the pursuit of excellence in all its forms, and the cost of that pursuit.',
    ),
  ),

  // ── Game Post ──
  Post(
    id: '4',
    user: PostUser(name: 'Omar', handle: '@omar_gamer'),
    type: PostType.game,
    text: '200 hours into Elden Ring and I\'m still finding new areas. This game is endless.',
    timestamp: DateTime.now().subtract(const Duration(hours: 12)),
    likes: 234,
    comments: 45,
    shares: 18,
    gameData: const GameMetadata(
      title: 'Elden Ring',
      posterUrl: 'https://image.tmdb.org/t/p/w500/8xWJhM8sGpPGfXQn5lhYKDUjXrz.jpg',
      releaseDate: '2022-02-25',
      platforms: ['PS5', 'Xbox', 'PC'],
      genres: ['Action RPG', 'Open World', 'Souls-like'],
      rating: 9.4,
      developer: 'FromSoftware',
      publisher: 'Bandai Namco',
      synopsis: 'A new fantasy action RPG. Rise, Tarnished, and be guided by grace to brandish the power of the Elden Ring and become an Elden Lord in the Lands Between.',
      playtime: 200,
    ),
  ),

  // ── Book Post ──
  Post(
    id: '5',
    user: currentUser,
    type: PostType.book,
    text: 'Starting Dune by Frank Herbert. The movie was incredible, excited to read the source material.',
    timestamp: DateTime.now().subtract(const Duration(days: 1)),
    likes: 45,
    comments: 8,
    shares: 2,
    bookData: const BookMetadata(
      title: 'Dune',
      coverUrl: 'https://covers.openlibrary.org/b/isbn/9780441172719-L.jpg',
      author: 'Frank Herbert',
      publishDate: '1965',
      pages: 688,
      genre: 'Science Fiction',
      rating: 4.3,
      isbn: '978-0441172719',
      synopsis: 'Set on the desert planet Arrakis, Dune is the story of the boy Paul Atreides, heir to a noble family tasked with ruling an inhospitable world where the only thing of value is a spice capable of extending life and expanding consciousness.',
    ),
  ),

  // ── Anime Post ──
  Post(
    id: '6',
    user: PostUser(name: 'Fatima', handle: '@fatima_otaku', verified: true),
    type: PostType.anime,
    text: 'Attack on Titan finale was everything I hoped for. What an ending.',
    timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
    likes: 312,
    comments: 67,
    shares: 45,
    animeData: const MediaMetadata(
      title: 'Attack on Titan',
      subtitle: 'The Final Season',
      posterUrl: 'https://cdn.myanimelist.net/images/anime/1000/110531.jpg',
      studio: 'MAPPA',
      releaseDate: '2013',
      rating: 9.0,
      genres: ['Action', 'Drama', 'Fantasy', 'Mystery'],
      episodes: 94,
      seasons: 4,
      aired: '2013 - 2023',
      status: 'Finished',
      synopsis: 'Centuries ago, mankind was slaughtered to near extinction by monstrous humanoid creatures called Titans, forcing humans to hide in fear behind enormous concentric walls. What makes these giants truly terrifying is that their taste for human flesh is not born out of hunger but what appears to be out of pleasure.',
    ),
  ),

  // ── Image Post ──
  Post(
    id: '7',
    user: PostUser(name: 'Karim', handle: '@karim_photo'),
    type: PostType.image,
    text: 'Sunset over the Hassan II Mosque. Casablanca never gets old.',
    timestamp: DateTime.now().subtract(const Duration(days: 2)),
    likes: 478,
    comments: 23,
    shares: 34,
    imageUrl: 'https://images.unsplash.com/photo-1565552645632-d725f8bfc19a?w=800',
  ),

  // ── Location Post ──
  Post(
    id: '8',
    user: currentUser,
    type: PostType.location,
    text: 'Hidden gem in the medina. The best mint tea I\'ve ever had.',
    timestamp: DateTime.now().subtract(const Duration(days: 2, hours: 6)),
    likes: 67,
    comments: 15,
    shares: 8,
    locationData: const LocationMetadata(
      name: 'Café Traditionnel',
      imageUrl: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=800',
      city: 'Fes',
      country: 'Morocco',
      description: 'Traditional café in the heart of the old medina, serving authentic Moroccan mint tea and pastries since 1920.',
      rating: 4.8,
    ),
  ),

  // ── Workout Post ──
  Post(
    id: '9',
    user: PostUser(name: 'Sara', handle: '@sara_fitness', verified: true),
    type: PostType.workout,
    text: 'Morning run by the Corniche. 10K done before sunrise!',
    timestamp: DateTime.now().subtract(const Duration(days: 3)),
    likes: 123,
    comments: 19,
    shares: 5,
    workoutData: const WorkoutMetadata(
      type: 'Running',
      durationMinutes: 52,
      calories: 620,
      intensity: 'High',
      notes: '10K along the Ain Diab Corniche',
    ),
  ),

  // ── Another Movie ──
  Post(
    id: '10',
    user: PostUser(name: 'Amina', handle: '@amina_stream', verified: true),
    type: PostType.movie,
    text: 'Oppenheimer is a masterclass in filmmaking. Nolan outdid himself.',
    timestamp: DateTime.now().subtract(const Duration(days: 3, hours: 8)),
    likes: 201,
    comments: 28,
    shares: 15,
    movieData: const MediaMetadata(
      title: 'Oppenheimer',
      subtitle: 'Christopher Nolan',
      posterUrl: 'https://image.tmdb.org/t/p/w500/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg',
      director: 'Christopher Nolan',
      releaseDate: '2023',
      rating: 8.3,
      genres: ['Drama', 'History', 'Thriller'],
      synopsis: 'The story of American scientist J. Robert Oppenheimer and his role in the development of the atomic bomb during World War II.',
    ),
  ),

  // ── Link Post ──
  Post(
    id: '11',
    user: PostUser(name: 'Karim', handle: '@karim_photo'),
    type: PostType.text,
    text: 'Found this amazing article about the future of open-source gaming engines https://www.gamedeveloper.com/engine/unreal-engine-5-is-now-free-for-indie-developers',
    timestamp: DateTime.now().subtract(const Duration(days: 3, hours: 12)),
    likes: 56,
    comments: 9,
    shares: 11,
  ),
];

/// People shown in the share sheet's "Send to" list (same crowd as the DM drawer).
const shareRecipients = [
  PostUser(name: 'Ahmed', handle: '@ahmed_m'),
  PostUser(name: 'Sara', handle: '@sara_dev', verified: true),
  PostUser(name: 'Omar', handle: '@omar_92'),
  PostUser(name: 'Fatima', handle: '@fatima_art', verified: true),
  PostUser(name: 'Karim', handle: '@karim_w'),
  PostUser(name: 'Amina', handle: '@amina_stream', verified: true),
];

class ScrollItem {
  final String id;
  final String username;
  final String caption;
  final int likes;
  final int comments;
  final String? videoUrl;
  final String? imageUrl;

  /// Audience for this scroll — private scrolls disable sharing.
  final PostVisibility visibility;

  const ScrollItem({
    required this.id,
    required this.username,
    required this.caption,
    this.likes = 0,
    this.comments = 0,
    this.videoUrl,
    this.imageUrl,
    this.visibility = PostVisibility.public,
  });
}

final dummyScrolls = [
  const ScrollItem(
    id: 'scroll_0',
    username: '@phaylali',
    caption: 'Sunset timelapse from the rooftop #goldenhour # Morocco',
    likes: 2400,
    comments: 186,
    imageUrl: 'https://picsum.photos/seed/scroll0/1080/1920',
  ),
  const ScrollItem(
    id: 'scroll_1',
    username: '@amina_stream',
    caption: 'Elden Ring DLC boss fight was insane #gaming #eldenring',
    likes: 5200,
    comments: 412,
    videoUrl: 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
  ),
  const ScrollItem(
    id: 'scroll_2',
    username: '@omar_gamer',
    caption: 'Cooking tagine with grandma #moroccanfood #homemade',
    likes: 1800,
    comments: 94,
    imageUrl: 'https://picsum.photos/seed/scroll2/1080/1920',
  ),
  const ScrollItem(
    id: 'scroll_3',
    username: '@fatima_otaku',
    caption: 'Attack on Titan OST on the piano #anime #music',
    likes: 8900,
    comments: 623,
    videoUrl: 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4',
  ),
  const ScrollItem(
    id: 'scroll_4',
    username: '@karim_photo',
    caption: 'Streets of Chefchaouen #travel #bluecity',
    likes: 3100,
    comments: 215,
    imageUrl: 'https://picsum.photos/seed/scroll4/1080/1920',
  ),
  const ScrollItem(
    id: 'scroll_5',
    username: '@sara_fitness',
    caption: 'Morning workout routine #fitness #gym',
    likes: 4500,
    comments: 328,
    videoUrl: 'https://filesamples.com/samples/video/mp4/sample_640x360.mp4',
  ),
  const ScrollItem(
    id: 'scroll_6',
    username: '@phaylali',
    caption: 'The Hassan II Mosque at night #casablanca #architecture',
    likes: 7200,
    comments: 489,
    imageUrl: 'https://picsum.photos/seed/scroll6/1080/1920',
  ),
];
