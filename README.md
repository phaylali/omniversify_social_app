# Omniversify Social App

A cross-platform social profile app that aggregates your movies, TV shows, games, books, anime, workouts, and locations into a single feed. Built with Flutter and powered by the Omniversify backend API.

## Features

- **Social Feed** — Posts, images, videos, and media-rich content
- **Scrolls** — Video feed with autoplay, looping, and smooth scrolling
- **Music Player** — Full local audio player with:
  - Instant file scanning (2-phase: filenames first, metadata in background)
  - Shuffle and repeat (off / all / one) modes
  - Android media notification with play/pause/next/prev/seek controls
  - Volume control and file sharing
  - Pull-to-refresh for rescanning new files
- **Explore** — Browse trending content by category (movies, games, books, etc.)
- **Profile** — User stats, posts, and settings
- **Tools** — QR scanner and other utilities
- **Notifications & DMs** — Drawer-based notifications and direct messages

## Architecture

```
lib/
├── main.dart                 # App entry, navigation, home screen
├── core/
│   ├── config/               # API config, environment variables
│   └── services/             # Omniversify backend client (media_api.dart)
├── services/
│   ├── audio_player_service.dart      # Singleton player (shuffle/repeat/notification)
│   ├── audio_scanner_linux.dart       # Filesystem scanner (quick + full modes)
│   ├── audio_scanner.dart             # Platform-conditional scanner export
│   ├── audio_scanner_stub.dart        # Stub for unsupported platforms
│   ├── audio_metadata_extractor.dart  # TagLib → pure-Dart → cache pipeline
│   ├── audio_metadata_cache.dart      # SharedPreferences persistent index
│   ├── audio_duration_parser.dart     # Pure-Dart header parser (MP3/FLAC/WAV/etc.)
│   ├── taglib_audio_service.dart      # flutter_taglib FFI wrapper
│   └── music_library_service.dart     # In-memory library cache singleton
├── screens/
│   ├── music_player_screen.dart       # Music player UI
│   ├── scrolls_screen.dart            # Video feed
│   ├── settings_screen.dart           # App settings
│   └── tracker_screen.dart            # Media tracker
├── models/
│   ├── song_item.dart                 # SongItem data model
│   └── post.dart                      # Post data model
└── widgets/
    ├── video_player.dart              # ScrollVideoPlayer with autoplay
    └── ...                            # Various post type widgets
```

## Getting Started

### Prerequisites

- Flutter SDK 3.48+
- Android SDK (for Android builds)
- Dart SDK ^3.14.0

### Setup

1. **Clone the repo:**
   ```bash
   git clone https://github.com/your-org/omniversify_social_app.git
   cd omniversify_social_app
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your API keys
   ```

4. **Run:**
   ```bash
   flutter run
   ```

### Building for Android (arm64)

```bash
flutter build apk --debug --target-platform android-arm64
```

> Note: `flutter_taglib` only ships arm64 native libs. Always target `android-arm64`.

## Environment Variables

| Variable | Description | Required |
|---|---|---|
| `OMNIVERSIFY_API_URL` | Omniversify backend API base URL | Yes |
| `RAWG_API_KEY` | RAWG Video Games Database key | Yes (games) |
| `IGDB_CLIENT_ID` | IGDB Twitch OAuth client ID | Yes (detailed game data) |
| `IGDB_CLIENT_SECRET` | IGDB Twitch OAuth client secret | Yes (detailed game data) |
| `TMDB_API_KEY` | TMDB movies/TV API key | Optional (movies/TV) |
| `TMDB_READ_ACCESS_TOKEN` | TMDB read access token | Optional (movies/TV) |

> **Security:** `.env` is gitignored. Never commit API keys. Use `.env.example` as a template.

## API Keys

This app consumes the Omniversify backend API for media aggregation. API keys for third-party services (RAWG, IGDB, TMDB) are configured server-side in the [omniversify-api](https://github.com/your-org/omniversify-api) project.

The client-side `.env` only needs `OMNIVERSIFY_API_URL` for the backend connection.

## Music Player Details

The music player uses a two-phase scanning approach:

1. **Quick scan** — Reads filenames from the filesystem and displays them instantly
2. **Background enrichment** — Parses metadata (duration, artist, album, artwork) using `flutter_taglib` (FFI) with a pure-Dart fallback, cached in SharedPreferences

### Audio Support

- **Exact duration:** MP3 (Xing/VBRI/CBR headers), FLAC, WAV, M4A/MP4, Ogg/Opus, AAC ADTS
- **Metadata:** Artist, album, title, cover art (via TagLib FFI)
- **Android notification:** Play/pause, next/previous, seek bar (via `audio_service`)

## Dependencies

| Package | Purpose |
|---|---|
| `audioplayers` | Local file audio playback |
| `audio_service` | Android media notification / session |
| `flutter_taglib` | Native metadata + artwork extraction (FFI) |
| `media_kit` | Video playback |
| `share_plus` | File sharing |
| `shared_preferences` | Persistent metadata cache |
| `permission_handler` | Runtime audio/storage permissions |
| `flutter_dotenv` | Environment variable loading |

## License

Private — Omniversify team.
