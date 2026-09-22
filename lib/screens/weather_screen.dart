import 'package:flutter/material.dart';
import '../services/weather_service.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final _searchCtrl = TextEditingController();
  WeatherData? _weather;
  GeoLocation? _location;
  List<GeoLocation> _suggestions = [];
  bool _loading = false;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) { setState(() => _suggestions = []); return; }
    final results = await WeatherService.searchLocation(q);
    if (mounted) setState(() => _suggestions = results);
  }

  Future<void> _selectLocation(GeoLocation loc) async {
    setState(() { _loading = true; _searching = false; _error = null; _suggestions = []; _searchCtrl.clear(); });
    try {
      final data = await WeatherService.fetchWeather(loc.lat, loc.lon);
      if (mounted) setState(() { _weather = data; _location = loc; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Weather')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search location...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchCtrl.clear(); setState(() => _suggestions = []); })
                        : null,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withAlpha(80),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: _search,
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (_, i) {
                        final loc = _suggestions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined, size: 18),
                          title: Text(loc.name, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(loc.displayName, style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(120))),
                          onTap: () => _selectLocation(loc),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.cloud_off, size: 48, color: cs.onSurface.withAlpha(80)),
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: cs.onSurface.withAlpha(150))),
                      ]))
                    : _weather == null
                        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.wb_sunny_outlined, size: 64, color: cs.onSurface.withAlpha(60)),
                            const SizedBox(height: 12),
                            Text('Search for a location', style: TextStyle(color: cs.onSurface.withAlpha(120))),
                          ]))
                        : _buildWeather(cs),
          ),
        ],
      ),
    );
  }

  Widget _buildWeather(ColorScheme cs) {
    final w = _weather!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (_location != null)
            Text(_location!.displayName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(w.current.icon, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 4),
          Text('${w.current.temp.round()}°C', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
          Text(w.current.description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurface.withAlpha(160))),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statChip(Icons.thermostat_outlined, 'Feels ${w.current.feelsLike.round()}°', cs),
              const SizedBox(width: 8),
              _statChip(Icons.water_drop_outlined, '${w.current.humidity}%', cs),
              const SizedBox(width: 8),
              _statChip(Icons.air, '${w.current.windSpeed.round()} km/h', cs),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('7-DAY FORECAST', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 11, letterSpacing: 1)),
          ),
          const SizedBox(height: 8),
          ...w.daily.map((d) => _dailyRow(d, cs)),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: cs.primary),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(160))),
      ]),
    );
  }

  Widget _dailyRow(DailyForecast d, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(60),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(d.dayName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface.withAlpha(160)))),
          Text(d.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Text(d.description, style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(120)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text('${d.maxTemp.round()}°', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withAlpha(200))),
          const SizedBox(width: 4),
          Text('${d.minTemp.round()}°', style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(100))),
          if (d.precipProb > 0) ...[
            const SizedBox(width: 6),
            Text('💧${d.precipProb}%', style: TextStyle(fontSize: 10, color: cs.primary)),
          ],
        ],
      ),
    );
  }
}
