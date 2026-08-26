import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) SharedPreferencesWindows.registerWith();
  PaintingBinding.instance.imageCache.maximumSize = 160;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 60 << 20;
  MediaKit.ensureInitialized();
  runApp(const StreamVistaApp());
}

const _accent = Color(0xFF2F4BFF);
const _surface = Color(0xFF12143A);
const _surfaceLight = Color(0xFF1A1D52);
const _screen = Color(0xFF080A27);
const _logoAsset = 'icon.png';
const _credentialStore = FlutterSecureStorage();

class StreamVistaApp extends StatefulWidget {
  const StreamVistaApp({super.key});
  @override
  State<StreamVistaApp> createState() => _StreamVistaAppState();
}

class _StreamVistaAppState extends State<StreamVistaApp> {
  PortalConfig? config;
  AppSettings settings = const AppSettings();
  final api = IptvApi();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final values =
        await Future.wait([PortalConfig.restore(), AppSettings.restore()]);
    if (mounted) {
      setState(() {
        config = values[0] as PortalConfig?;
        settings = values[1] as AppSettings;
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'StreamVista',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
              seedColor: _accent, brightness: Brightness.dark),
          scaffoldBackgroundColor: _screen,
          cardTheme: const CardThemeData(color: _surface, elevation: 0),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: _surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide.none),
          ),
        ),
        home: config == null
            ? ConnectPage(
                onConnected: (value) => setState(() => config = value),
                api: api)
            : HomePage(
                config: config!,
                api: api,
                settings: settings,
                onSettingsChanged: (value) async {
                  await value.save();
                  if (mounted) setState(() => settings = value);
                },
                onDisconnect: () async {
                  await PortalConfig.clear();
                  if (mounted) setState(() => config = null);
                }),
      );
}

enum SourceType { xtream, m3u }

enum PlaybackProfile { balanced, hd, ultra }

class AppSettings {
  const AppSettings({this.profile = PlaybackProfile.hd});
  final PlaybackProfile profile;

  int get bufferSize => switch (profile) {
        PlaybackProfile.balanced => 64 * 1024 * 1024,
        PlaybackProfile.hd => 128 * 1024 * 1024,
        PlaybackProfile.ultra => 256 * 1024 * 1024,
      };

  String get profileLabel => switch (profile) {
        PlaybackProfile.balanced => 'Equilibrado',
        PlaybackProfile.hd => '1080p fluido',
        PlaybackProfile.ultra => '4K fluido',
      };

  Future<void> save() async => (await SharedPreferences.getInstance())
      .setString('playback_profile', profile.name);

  static Future<AppSettings> restore() async {
    final raw =
        (await SharedPreferences.getInstance()).getString('playback_profile');
    try {
      return AppSettings(
          profile:
              PlaybackProfile.values.byName(raw ?? PlaybackProfile.hd.name));
    } catch (_) {
      return const AppSettings();
    }
  }
}

class PortalConfig {
  PortalConfig(
      {required this.type,
      required this.server,
      this.username,
      this.password,
      this.userAgent});
  final SourceType type;
  final String server;
  final String? username;
  final String? password;
  final String? userAgent;

  String get normalizedServer => server.trim().replaceAll(RegExp(r'/$'), '');
  Map<String, String> get headers => userAgent?.trim().isNotEmpty == true
      ? {'User-Agent': userAgent!.trim()}
      : {};
  Map<String, String> get xtreamQuery =>
      {'username': username!.trim(), 'password': password!.trim()};

  Future<void> save() async {
    await _credentialStore.write(
        key: 'portal',
        value: jsonEncode({
          'type': type.name,
          'server': server,
          'username': username,
          'password': password,
          'userAgent': userAgent
        }));
  }

  static Future<PortalConfig?> restore() async {
    final raw = await _credentialStore.read(key: 'portal');
    if (raw == null) {
      // Remove legacy plaintext credentials from versions released before secure storage.
      await (await SharedPreferences.getInstance()).remove('portal');
      return null;
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return PortalConfig(
          type: SourceType.values.byName(j['type'] as String),
          server: j['server'] as String,
          username: j['username'] as String?,
          password: j['password'] as String?,
          userAgent: j['userAgent'] as String?);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    await _credentialStore.delete(key: 'portal');
    await (await SharedPreferences.getInstance()).remove('portal');
  }
}

class MediaItem {
  const MediaItem(
      {required this.id,
      required this.title,
      required this.streamUrl,
      required this.kind,
      this.category = 'Sin categoría',
      this.logo,
      this.poster,
      this.year,
      this.headers = const {}});
  final String id, title, streamUrl, category;
  final MediaKind kind;
  final String? logo, poster, year;
  final Map<String, String> headers;
}

enum MediaKind { live, movie, series }

class IptvApi {
  Future<void> validate(PortalConfig config) async {
    if (config.type == SourceType.m3u) {
      await _m3u(config);
      return;
    }
    final response = await _get(config, null);
    if (response is! Map) {
      throw const FormatException('La respuesta del servidor no es válida.');
    }
    final user = response['user_info'];
    if (user is! Map || '${user['auth']}' != '1') {
      throw const FormatException('Usuario o contraseña incorrectos.');
    }
  }

  Future<List<MediaItem>> fetch(PortalConfig config, MediaKind kind) async {
    if (config.type == SourceType.m3u) {
      return (await _m3u(config)).where((item) => item.kind == kind).toList();
    }
    final action = switch (kind) {
      MediaKind.live => 'get_live_streams',
      MediaKind.movie => 'get_vod_streams',
      MediaKind.series => 'get_series'
    };
    final categoryAction = switch (kind) {
      MediaKind.live => 'get_live_categories',
      MediaKind.movie => 'get_vod_categories',
      MediaKind.series => 'get_series_categories'
    };
    final rows = _asList(await _get(config, action), 'catálogo');
    dynamic categoryResult = const <dynamic>[];
    try {
      categoryResult = await _get(config, categoryAction);
    } catch (_) {
      // El catálogo se puede reproducir aunque un portal no exponga categorías.
    }
    final categories = <String, String>{
      for (final raw
          in categoryResult is List ? categoryResult : const <dynamic>[])
        if (raw is Map && raw['category_id'] != null)
          '${raw['category_id']}': '${raw['category_name'] ?? 'Sin categoría'}',
    };
    return rows.map((raw) {
      if (raw is! Map)
        throw const FormatException('Hay elementos no válidos en el catálogo.');
      final x = raw;
      final id = '${x['stream_id'] ?? x['series_id'] ?? x['num']}';
      final extension = x['container_extension'] ?? 'm3u8';
      final segment = switch (kind) {
        MediaKind.live => 'live',
        MediaKind.movie => 'movie',
        MediaKind.series => 'series'
      };
      final stream = kind == MediaKind.series
          ? ''
          : '${config.normalizedServer}/$segment/${config.username}/${config.password}/$id.$extension';
      return MediaItem(
          id: id,
          title: (x['name'] ?? 'Sin título').toString(),
          streamUrl: stream,
          kind: kind,
          category: (x['category_name'] ??
                  categories['${x['category_id']}'] ??
                  'Sin categoría')
              .toString(),
          logo: x['stream_icon']?.toString(),
          poster: x['stream_icon']?.toString(),
          year: x['year']?.toString(),
          headers: config.headers);
    }).toList();
  }

  Future<dynamic> _get(PortalConfig config, String? action) async {
    final parameters = <String, String>{...config.xtreamQuery};
    if (action != null) parameters['action'] = action;
    final uri = Uri.parse('${config.normalizedServer}/player_api.php')
        .replace(queryParameters: parameters);
    final response = await http
        .get(uri, headers: config.headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('El servidor respondió ${response.statusCode}.');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const FormatException(
          'El servidor no devolvió datos JSON válidos.');
    }
  }

  List<dynamic> _asList(dynamic value, String name) {
    if (value is List) return value;
    if (value is Map &&
        (value['user_info']?['auth'] == 0 || value['auth'] == 0)) {
      throw const FormatException('Usuario o contraseña incorrectos.');
    }
    throw FormatException('No se pudo cargar el $name.');
  }

  Future<List<MediaItem>> _m3u(PortalConfig config) async {
    final response = await http
        .get(Uri.parse(config.server.trim()), headers: config.headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception(
          'No se pudo descargar la playlist (${response.statusCode}).');
    }
    final lines = const LineSplitter().convert(utf8.decode(response.bodyBytes));
    final items = <MediaItem>[];
    String? metadata;
    for (final line in lines) {
      if (line.startsWith('#EXTINF:')) {
        metadata = line;
        continue;
      }
      if (metadata != null && line.trim().isNotEmpty && !line.startsWith('#')) {
        final streamUri = Uri.tryParse(line.trim());
        if (streamUri == null ||
            streamUri.scheme != 'https' ||
            streamUri.host.isEmpty) {
          metadata = null;
          continue;
        }
        final title =
            RegExp(r',(.*)$').firstMatch(metadata)?.group(1)?.trim() ??
                'Sin título';
        final group =
            RegExp(r'group-title="([^"]*)"').firstMatch(metadata)?.group(1) ??
                'TV en vivo';
        final logo =
            RegExp(r'tvg-logo="([^"]*)"').firstMatch(metadata)?.group(1);
        final groupLower = group.toLowerCase();
        final itemKind =
            groupLower.contains('movie') || groupLower.contains('película')
                ? MediaKind.movie
                : groupLower.contains('series')
                    ? MediaKind.series
                    : MediaKind.live;
        items.add(MediaItem(
            id: line.hashCode.toString(),
            title: title,
            streamUrl: line.trim(),
            kind: itemKind,
            category: group,
            logo: logo,
            headers: config.headers));
        metadata = null;
      }
    }
    if (items.isEmpty) {
      throw const FormatException(
          'La playlist no contiene entradas M3U válidas.');
    }
    return items;
  }

  Future<List<MediaItem>> episodes(
      PortalConfig config, MediaItem series) async {
    if (config.type == SourceType.m3u) {
      throw UnsupportedError(
          'Las listas M3U no incluyen la información de episodios.');
    }
    final uri = Uri.parse('${config.normalizedServer}/player_api.php').replace(
      queryParameters: {
        ...config.xtreamQuery,
        'action': 'get_series_info',
        'series_id': series.id
      },
    );
    final raw = await http
        .get(uri, headers: config.headers)
        .timeout(const Duration(seconds: 20));
    if (raw.statusCode != 200)
      throw Exception('El servidor respondió ${raw.statusCode}.');
    final data = jsonDecode(utf8.decode(raw.bodyBytes));
    if (data is! Map || data['episodes'] is! Map) {
      throw const FormatException('La serie no tiene episodios disponibles.');
    }
    final output = <MediaItem>[];
    (data['episodes'] as Map).forEach((season, values) {
      if (values is! List) return;
      for (final value in values) {
        if (value is! Map) continue;
        final id = '${value['id'] ?? value['episode_id']}';
        if (id == 'null') continue;
        final extension = '${value['container_extension'] ?? 'mp4'}';
        final episode = '${value['episode_num'] ?? ''}';
        output.add(MediaItem(
          id: id,
          title: 'T$season · E$episode — ${value['title'] ?? 'Sin título'}',
          streamUrl:
              '${config.normalizedServer}/series/${config.username}/${config.password}/$id.$extension',
          kind: MediaKind.series,
          category: 'Temporada $season',
          logo: value['info'] is Map
              ? value['info']['movie_image']?.toString()
              : series.logo,
          headers: config.headers,
        ));
      }
    });
    if (output.isEmpty)
      throw const FormatException('La serie no tiene episodios reproducibles.');
    return output;
  }
}

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.onConnected, required this.api});
  final ValueChanged<PortalConfig> onConnected;
  final IptvApi api;
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  SourceType type = SourceType.xtream;
  final server = TextEditingController(),
      user = TextEditingController(),
      pass = TextEditingController(),
      agent = TextEditingController();
  bool loading = false;
  @override
  void dispose() {
    server.dispose();
    user.dispose();
    pass.dispose();
    agent.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    if (server.text.trim().isEmpty ||
        (type == SourceType.xtream &&
            (user.text.isEmpty || pass.text.isEmpty))) {
      return _error('Completa los campos requeridos.');
    }
    final endpoint = Uri.tryParse(server.text.trim());
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty) {
      return _error('Use a valid HTTPS address to protect the connection.');
    }
    setState(() => loading = true);
    final config = PortalConfig(
        type: type,
        server: server.text,
        username: user.text,
        password: pass.text,
        userAgent: agent.text);
    try {
      await widget.api.validate(config);
      await config.save();
      widget.onConnected(config);
    } catch (e) {
      _error('No se pudo conectar: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  void _error(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(_logoAsset, width: 82, height: 82),
                  const SizedBox(height: 16),
                  Text(
                    'StreamVista',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text('Tu contenido autorizado, en una sola pantalla.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 30),
                  SegmentedButton<SourceType>(
                    segments: const [
                      ButtonSegment(
                          value: SourceType.xtream,
                          label: Text('Xtream Codes')),
                      ButtonSegment(
                          value: SourceType.m3u, label: Text('M3U / M3U8')),
                    ],
                    selected: {type},
                    onSelectionChanged: (v) => setState(() => type = v.first),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: server,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: type == SourceType.xtream
                          ? 'URL del servidor'
                          : 'URL de la playlist',
                      hintText: type == SourceType.xtream
                          ? 'https://servidor.ejemplo'
                          : 'https://proveedor.ejemplo/lista.m3u',
                    ),
                  ),
                  if (type == SourceType.xtream) ...[
                    const SizedBox(height: 12),
                    TextField(
                        controller: user,
                        decoration:
                            const InputDecoration(labelText: 'Usuario')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: pass,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'Contraseña')),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                      controller: agent,
                      decoration: const InputDecoration(
                          labelText: 'User-Agent (opcional)')),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: loading ? null : connect,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 17)),
                    child: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator())
                        : const Text('Conectar'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Usa únicamente servicios y listas para los que tienes autorización.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage(
      {super.key,
      required this.config,
      required this.api,
      required this.settings,
      required this.onSettingsChanged,
      required this.onDisconnect});
  final PortalConfig config;
  final IptvApi api;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final Future<void> Function() onDisconnect;
  @override
  State<HomePage> createState() => _VistaHomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  final types = const [MediaKind.live, MediaKind.movie, MediaKind.series];
  @override
  Widget build(BuildContext context) {
    final type = types[index];
    final title = ['TV en vivo', 'Películas', 'Series'][index];
    return Scaffold(
      appBar: AppBar(
          title: Row(children: [
            Image.asset(_logoAsset, width: 30, height: 30),
            const SizedBox(width: 9),
            const Text('StreamVista',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          actions: [
            IconButton(
                tooltip: 'Configuración',
                onPressed: () async {
                  final value = await Navigator.push<AppSettings>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(settings: widget.settings),
                    ),
                  );
                  if (value != null) widget.onSettingsChanged(value);
                },
                icon: const Icon(Icons.settings_outlined)),
            IconButton(
                tooltip: 'Desconectar',
                onPressed: widget.onDisconnect,
                icon: const Icon(Icons.logout_rounded))
          ]),
      body: CatalogPage(
          title: title,
          type: type,
          config: widget.config,
          api: widget.api,
          settings: widget.settings),
      bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.live_tv_outlined),
                selectedIcon: Icon(Icons.live_tv),
                label: 'En vivo'),
            NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie),
                label: 'Películas'),
            NavigationDestination(
                icon: Icon(Icons.tv_outlined),
                selectedIcon: Icon(Icons.tv),
                label: 'Series')
          ]),
    );
  }
}

class _VistaHomePageState extends State<HomePage> {
  int selected = 0;
  bool browsing = false;
  final types = const [MediaKind.live, MediaKind.movie, MediaKind.series];

  void _open(int value) => setState(() {
        selected = value;
        browsing = true;
      });

  Future<void> _settings() async {
    final value = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
          builder: (_) => SettingsPage(settings: widget.settings)),
    );
    if (value != null) widget.onSettingsChanged(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: browsing
            ? CatalogPage(
                title: const ['Live TV', 'Movies', 'Series'][selected],
                type: types[selected],
                config: widget.config,
                api: widget.api,
                settings: widget.settings,
                onBack: () => setState(() => browsing = false),
                onNavigate: (kind) =>
                    setState(() => selected = types.indexOf(kind)),
              )
            : _IptvHome(
                onOpen: _open,
                onSettings: _settings,
                onDisconnect: widget.onDisconnect),
      );
}

class _IptvHome extends StatelessWidget {
  const _IptvHome(
      {required this.onOpen,
      required this.onSettings,
      required this.onDisconnect});
  final ValueChanged<int> onOpen;
  final VoidCallback onSettings;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_screen, Color(0xFF15164B), Color(0xFF07081E)]),
        ),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, size) {
            final compact = size.maxWidth < 820;
            return Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 26 : 58, vertical: compact ? 22 : 36),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _BrandMark(size: compact ? 42 : 52),
                      const SizedBox(width: 13),
                      Text('StreamVista',
                          style: TextStyle(
                              fontSize: compact ? 24 : 31,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.7)),
                      const SizedBox(width: 18),
                      Container(width: 1, height: 34, color: Colors.white38),
                      const SizedBox(width: 18),
                      const _ClockLabel(),
                      const Spacer(),
                      _HeaderAction(
                          icon: Icons.search_rounded,
                          label: 'Search',
                          onTap: () => onOpen(0)),
                      _HeaderIcon(
                          icon: Icons.notifications_none_rounded, onTap: () {}),
                      _HeaderIcon(
                          icon: Icons.settings_outlined, onTap: onSettings),
                      _HeaderIcon(
                          icon: Icons.logout_rounded, onTap: onDisconnect),
                    ]),
                    const Spacer(flex: 2),
                    Center(
                        child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: compact ? 14 : 20,
                            runSpacing: 14,
                            children: [
                          _HomeTile(
                              icon: Icons.live_tv_rounded,
                              title: 'Live TV',
                              subtitle: 'Channels',
                              selected: true,
                              onTap: () => onOpen(0)),
                          _HomeTile(
                              icon: Icons.local_movies_rounded,
                              title: 'Movies',
                              subtitle: 'On demand',
                              onTap: () => onOpen(1)),
                          _HomeTile(
                              icon: Icons.video_library_rounded,
                              title: 'Series',
                              subtitle: 'Shows',
                              onTap: () => onOpen(2)),
                        ])),
                    const SizedBox(height: 20),
                    Center(
                        child: Wrap(spacing: 12, runSpacing: 10, children: [
                      _QuickButton(
                          icon: Icons.playlist_play_rounded,
                          label: 'Playlists',
                          onTap: () => onOpen(0)),
                      _QuickButton(
                          icon: Icons.history_rounded,
                          label: 'Catch Up',
                          onTap: () => onOpen(0)),
                      _QuickButton(
                          icon: Icons.favorite_border_rounded,
                          label: 'Favorites',
                          onTap: () => onOpen(0)),
                      _QuickButton(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          onTap: onSettings),
                    ])),
                    const Spacer(),
                    const Text('Current playlist: Connected',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white70)),
                    const SizedBox(height: 5),
                    const Text('Authorized streaming library',
                        style: TextStyle(color: Colors.white38)),
                  ]),
            );
          }),
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(size * .27),
          boxShadow: [
            BoxShadow(color: _accent.withValues(alpha: .5), blurRadius: 18)
          ]),
      child:
          Icon(Icons.live_tv_rounded, size: size * .63, color: Colors.white));
}

class _ClockLabel extends StatelessWidget {
  const _ClockLabel();
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Text(
        '${TimeOfDay.fromDateTime(now).format(context)}\n${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35));
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white));
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white10,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)));
}

class _HomeTile extends StatelessWidget {
  const _HomeTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.selected = false});
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
          width: 250,
          height: 275,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected ? _accent : _surface.withValues(alpha: .84),
              border: Border.all(
                  color: selected ? const Color(0xFF8493FF) : Colors.white12,
                  width: selected ? 2 : 1),
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: _accent.withValues(alpha: .38),
                          blurRadius: 30,
                          spreadRadius: 2)
                    ]
                  : null),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 72, color: Colors.white),
            const SizedBox(height: 23),
            Text(title,
                style:
                    const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(fontSize: 16, color: Colors.white70))
          ])));
}

class _QuickButton extends StatelessWidget {
  const _QuickButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF151658),
          foregroundColor: Colors.white,
          minimumSize: const Size(170, 50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late PlaybackProfile profile;

  @override
  void initState() {
    super.initState();
    profile = widget.settings.profile;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Configuración'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, AppSettings(profile: profile)),
              child: const Text('Guardar'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('REPRODUCCIÓN', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            const Text(
              'Elige el búfer según tu conexión. La resolución final depende de la señal que entregue tu proveedor.',
            ),
            const SizedBox(height: 14),
            ...PlaybackProfile.values.map((value) => Card(
                  child: RadioListTile<PlaybackProfile>(
                    value: value,
                    groupValue: profile,
                    onChanged: (selected) =>
                        setState(() => profile = selected!),
                    title: Text(AppSettings(profile: value).profileLabel),
                    subtitle: Text(switch (value) {
                      PlaybackProfile.balanced =>
                        '64 MB de búfer · conexión estable',
                      PlaybackProfile.hd =>
                        '128 MB de búfer · recomendado para 1080p',
                      PlaybackProfile.ultra =>
                        '256 MB de búfer · recomendado para 4K',
                    }),
                  ),
                )),
            const SizedBox(height: 20),
            Text('CONTROLES DEL REPRODUCTOR',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            const Text(
              'El menú inferior del reproductor permanece visible durante 15 segundos y después se oculta automáticamente. Mueve el ratón o toca el vídeo para mostrarlo de nuevo.',
            ),
          ],
        ),
      );
}

class CatalogPage extends StatefulWidget {
  const CatalogPage(
      {super.key,
      required this.title,
      required this.type,
      required this.config,
      required this.api,
      required this.settings,
      this.onBack,
      this.onNavigate});
  final String title;
  final MediaKind type;
  final PortalConfig config;
  final IptvApi api;
  final AppSettings settings;
  final VoidCallback? onBack;
  final ValueChanged<MediaKind>? onNavigate;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late Future<List<MediaItem>> future;
  String query = '';
  String category = 'Todas';
  @override
  void initState() {
    super.initState();
    future = widget.api.fetch(widget.config, widget.type);
  }

  @override
  void didUpdateWidget(covariant CatalogPage old) {
    super.didUpdateWidget(old);
    if (old.type != widget.type) {
      future = widget.api.fetch(widget.config, widget.type);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MediaItem>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Error al cargar el catálogo\n${snapshot.error}',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() =>
                        future = widget.api.fetch(widget.config, widget.type)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ]),
              ),
            );
          }
          final all = snapshot.data!;
          if (widget.type == MediaKind.live) {
            return _LiveTvBrowser(
              items: all,
              settings: widget.settings,
              onBack: widget.onBack,
              onNavigate: widget.onNavigate,
            );
          }
          final categories = all.map((item) => item.category).toSet().toList()
            ..sort();
          final selectedCategory =
              categories.contains(category) ? category : 'Todas';
          final shown = all
              .where((i) =>
                  (selectedCategory == 'Todas' ||
                      i.category == selectedCategory) &&
                  i.title.toLowerCase().contains(query.toLowerCase()))
              .toList();
          final catalog = RefreshIndicator(
              onRefresh: () async => setState(
                  () => future = widget.api.fetch(widget.config, widget.type)),
              child: CustomScrollView(slivers: [
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                    sliver: SliverToBoxAdapter(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            IconButton(
                                onPressed: widget.onBack,
                                icon: const Icon(Icons.arrow_back_rounded)),
                            const SizedBox(width: 6),
                            _BrandMark(size: 30),
                            const SizedBox(width: 10),
                            Text(widget.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                          ]),
                          Text('${all.length} disponibles',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 16),
                          TextField(
                              onChanged: (v) => setState(() => query = v),
                              decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: 'Buscar')),
                        ]))),
                SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 190,
                                mainAxisExtent: 232,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12),
                        itemCount: shown.length,
                        itemBuilder: (_, i) => MediaCard(
                            item: shown[i],
                            config: widget.config,
                            api: widget.api,
                            settings: widget.settings,
                            playlist: shown,
                            position: i))),
              ]));
          return LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 760) return catalog;
            return Row(children: [
              SizedBox(
                width: 250,
                child: _CategorySidebar(
                  categories: ['Todas', ...categories],
                  selected: selectedCategory,
                  onSelected: (value) => setState(() => category = value),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: catalog),
            ]);
          });
        },
      );
}

class _LiveTvBrowser extends StatefulWidget {
  const _LiveTvBrowser(
      {required this.items,
      required this.settings,
      this.onBack,
      this.onNavigate});
  final List<MediaItem> items;
  final AppSettings settings;
  final VoidCallback? onBack;
  final ValueChanged<MediaKind>? onNavigate;
  @override
  State<_LiveTvBrowser> createState() => _LiveTvBrowserState();
}

class _LiveTvBrowserState extends State<_LiveTvBrowser> {
  String category = 'All';
  String query = '';
  int selected = 0;

  List<MediaItem> get _shown => widget.items
      .where((item) =>
          (category == 'All' || item.category == category) &&
          item.title.toLowerCase().contains(query.toLowerCase()))
      .toList();

  void _open(MediaItem item, int index, List<MediaItem> items,
          {bool fullscreen = false}) =>
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PlayerPage(
                  item: item,
                  playlist: items,
                  position: index,
                  settings: widget.settings,
                  startFullscreen: fullscreen)));

  @override
  Widget build(BuildContext context) {
    final categories = widget.items.map((i) => i.category).toSet().toList()
      ..sort();
    final shown = _shown;
    if (shown.isEmpty && selected != 0) selected = 0;
    final current =
        shown.isEmpty ? null : shown[selected.clamp(0, shown.length - 1)];
    return Container(
      color: _screen,
      child: SafeArea(
        child: Column(children: [
          _LiveTopBar(
              onBack: widget.onBack,
              onTab: (tab) => widget.onNavigate?.call(tab == 1
                  ? MediaKind.movie
                  : tab == 2
                      ? MediaKind.series
                      : MediaKind.live)),
          Expanded(child: LayoutBuilder(builder: (context, size) {
            if (size.maxWidth < 900) return _compactView(shown, current);
            return Row(children: [
              SizedBox(width: 285, child: _groupPane(categories)),
              const VerticalDivider(width: 1, color: Colors.white24),
              SizedBox(width: size.maxWidth * .36, child: _channelPane(shown)),
              const VerticalDivider(width: 1, color: Colors.white24),
              Expanded(child: _detailsPane(current, shown)),
            ]);
          })),
        ]),
      ),
    );
  }

  Widget _compactView(List<MediaItem> shown, MediaItem? current) =>
      Column(children: [
        _searchField(),
        SizedBox(
          height: 49,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: ['All', ...widget.items.map((i) => i.category).toSet()]
                .map((name) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: category == name,
                        onSelected: (_) => setState(() {
                          category = name;
                          selected = 0;
                        }),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(child: _channelPane(shown)),
        if (current != null)
          SizedBox(height: 245, child: _detailsPane(current, shown)),
      ]);

  Widget _groupPane(List<String> categories) => Container(
        color: const Color(0xFF0D1033),
        child: Column(children: [
          _searchField(),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
                  children: [
                _categoryRow('Recently Viewed', Icons.history_rounded, 0),
                _categoryRow(
                    'All', Icons.grid_view_rounded, widget.items.length),
                const Padding(
                    padding: EdgeInsets.fromLTRB(10, 16, 10, 6),
                    child: Text('CHANNEL GROUPS',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1))),
                ...categories.map((value) => _categoryRow(
                    value,
                    Icons.play_circle_outline_rounded,
                    widget.items.where((i) => i.category == value).length)),
              ])),
        ]),
      );

  Widget _categoryRow(String name, IconData icon, int count) {
    final active =
        category == name || (name == 'Recently Viewed' && category == 'All');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
          color: active ? const Color(0xFF20255F) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: () => setState(() {
              category = name == 'Recently Viewed' ? 'All' : name;
              selected = 0;
            }),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                child: Row(children: [
                  Icon(icon,
                      size: 18,
                      color: active ? const Color(0xFFE7F01A) : Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight:
                                  active ? FontWeight.w800 : FontWeight.w500,
                              color: active
                                  ? const Color(0xFFE7F01A)
                                  : Colors.white))),
                  Text('$count',
                      style: TextStyle(
                          color:
                              active ? const Color(0xFFE7F01A) : Colors.white70,
                          fontWeight: FontWeight.w700)),
                ])),
          )),
    );
  }

  Widget _searchField() => Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: TextField(
        onChanged: (value) => setState(() {
          query = value;
          selected = 0;
        }),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
            hintText: 'Search',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            contentPadding: EdgeInsets.zero,
            fillColor: const Color(0xFF17194B),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: Colors.white54))),
      ));

  Widget _channelPane(List<MediaItem> shown) => Container(
        color: const Color(0xFF10133C),
        child: shown.isEmpty
            ? const Center(child: Text('No channels found'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final item = shown[index];
                  final active = selected == index;
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Material(
                          color: active ? _accent : const Color(0xFF191B52),
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: () => setState(() => selected = index),
                            onDoubleTap: () =>
                                _open(item, index, shown, fullscreen: true),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 13),
                                child: Row(children: [
                                  SizedBox(
                                      width: 28,
                                      child: Text('${index + 1}',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: active
                                                  ? const Color(0xFFE7F01A)
                                                  : Colors.white70))),
                                  _ChannelLogo(item: item, active: active),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontWeight: active
                                                  ? FontWeight.w800
                                                  : FontWeight.w600))),
                                  if (active)
                                    const Icon(Icons.play_arrow_rounded,
                                        size: 20),
                                ])),
                          )));
                },
              ),
      );

  Widget _detailsPane(MediaItem? current, List<MediaItem> shown) {
    if (current == null) return const Center(child: Text('Select a channel'));
    return Container(
        color: const Color(0xFF0C0E30),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                flex: 7,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(fit: StackFit.expand, children: [
                      _PreviewArtwork(item: current),
                      const Positioned(left: 12, top: 12, child: _LivePill()),
                      const Positioned(
                          right: 12,
                          bottom: 12,
                          child: Icon(Icons.fullscreen_rounded,
                              color: Colors.white70)),
                    ]))),
            const SizedBox(height: 13),
            Row(children: [
              _ChannelLogo(item: current, active: true, large: true),
              const SizedBox(width: 11),
              Expanded(
                  child: Text(current.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)))
            ]),
            const SizedBox(height: 12),
            const Text('NOW PLAYING',
                style: TextStyle(
                    color: Color(0xFFE7F01A),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8)),
            const SizedBox(height: 4),
            Text('Live broadcast on ${current.category}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
                'Select a channel to preview it. Press play or double-click to start watching.',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
            const Spacer(),
            Row(children: [
              FilledButton.icon(
                  onPressed: () => _open(current, selected, shown),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Watch live'),
                  style: FilledButton.styleFrom(
                      backgroundColor: _accent, foregroundColor: Colors.white)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.favorite_border_rounded),
                  label: const Text('Favorite')),
            ]),
          ]),
        ));
  }
}

class _LiveTopBar extends StatelessWidget {
  const _LiveTopBar({required this.onBack, required this.onTab});
  final VoidCallback? onBack;
  final ValueChanged<int> onTab;
  @override
  Widget build(BuildContext context) => Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: const Color(0xFF0C0E30),
        child: Row(children: [
          IconButton(
              onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
          const SizedBox(width: 5),
          _BrandMark(size: 32),
          const SizedBox(width: 12),
          _TopTab(label: 'Live TV', selected: true, onTap: () => onTab(0)),
          _TopTab(label: 'Movies', onTap: () => onTab(1)),
          _TopTab(label: 'Series', onTap: () => onTab(2)),
          const Spacer(),
          const Icon(Icons.search_rounded, color: Colors.white70),
          const SizedBox(width: 16),
          const Icon(Icons.account_circle_outlined, color: Colors.white70),
        ]),
      );
}

class _TopTab extends StatelessWidget {
  const _TopTab(
      {required this.label, required this.onTap, this.selected = false});
  final String label;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(left: 10),
      child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
              foregroundColor:
                  selected ? const Color(0xFFE7F01A) : Colors.white,
              backgroundColor:
                  selected ? const Color(0xFF1A1D58) : Colors.transparent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 19, vertical: 12)),
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w800))));
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo(
      {required this.item, required this.active, this.large = false});
  final MediaItem item;
  final bool active, large;
  @override
  Widget build(BuildContext context) => Container(
      width: large ? 42 : 27,
      height: large ? 42 : 27,
      decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(5)),
      clipBehavior: Clip.antiAlias,
      child: item.logo?.isNotEmpty == true
          ? Image.network(item.logo!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.live_tv_rounded,
                  color: active ? _accent : Colors.white54,
                  size: large ? 26 : 17))
          : Icon(Icons.live_tv_rounded,
              color: active ? _accent : Colors.white54, size: large ? 26 : 17));
}

class _PreviewArtwork extends StatelessWidget {
  const _PreviewArtwork({required this.item});
  final MediaItem item;
  @override
  Widget build(BuildContext context) => item.logo?.isNotEmpty == true
      ? Image.network(item.logo!,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback())
      : _fallback();
  Widget _fallback() => Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
            Color(0xFF233D9B),
            Color(0xFF0A123B),
            Color(0xFF211760)
          ])),
      child: const Center(
          child: Icon(Icons.live_tv_rounded, size: 82, color: Colors.white30)));
}

class _LivePill extends StatelessWidget {
  const _LivePill();
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFF03447),
          borderRadius: BorderRadius.circular(14)),
      child: const Text('LIVE TV',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)));
}

class _CategorySidebar extends StatefulWidget {
  const _CategorySidebar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<_CategorySidebar> createState() => _CategorySidebarState();
}

class _CategorySidebarState extends State<_CategorySidebar> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _surface,
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(10, 18, 10, 18),
            children: [
              Text('CATEGORÍAS',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 10),
              ...widget.categories.map((value) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      selected: value == widget.selected,
                      selectedTileColor: _accent.withValues(alpha: .18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      title: Text(value,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => widget.onSelected(value),
                    ),
                  )),
            ],
          ),
        ),
      );
}

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.config,
    required this.api,
    required this.settings,
    required this.playlist,
    required this.position,
  });
  final MediaItem item;
  final PortalConfig config;
  final IptvApi api;
  final AppSettings settings;
  final List<MediaItem> playlist;
  final int position;
  @override
  Widget build(BuildContext context) => InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  item.kind == MediaKind.series && item.streamUrl.isEmpty
                      ? SeriesPage(
                          series: item,
                          config: config,
                          api: api,
                          settings: settings)
                      : PlayerPage(
                          item: item,
                          playlist: playlist,
                          position: position,
                          settings: settings))),
      child: Card(
          clipBehavior: Clip.antiAlias,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                child: item.logo?.isNotEmpty == true
                    ? Image.network(item.logo!,
                        fit: BoxFit.cover,
                        cacheWidth: 380,
                        cacheHeight: 380,
                        errorBuilder: (_, __, ___) => const _Artwork())
                    : const _Artwork()),
            Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 2),
                child: Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
                child: Text(item.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall))
          ])));
}

class _Artwork extends StatelessWidget {
  const _Artwork();
  @override
  Widget build(BuildContext context) => Container(
      color: const Color(0xFF292744),
      child: const Icon(Icons.play_circle_outline_rounded,
          size: 48, color: Colors.white54));
}

class SeriesPage extends StatefulWidget {
  const SeriesPage({
    super.key,
    required this.series,
    required this.config,
    required this.api,
    required this.settings,
  });
  final MediaItem series;
  final PortalConfig config;
  final IptvApi api;
  final AppSettings settings;

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  late Future<List<MediaItem>> future;

  @override
  void initState() {
    super.initState();
    future = widget.api.episodes(widget.config, widget.series);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.series.title)),
        body: FutureBuilder<List<MediaItem>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        'No se pudieron cargar los episodios.\n${snapshot.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => future =
                          widget.api.episodes(widget.config, widget.series)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ]),
                ),
              );
            }
            final episodes = snapshot.data!;
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: episodes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final episode = episodes[index];
                return ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(episode.title),
                  subtitle: Text(episode.category),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerPage(
                        item: episode,
                        playlist: episodes,
                        position: index,
                        settings: widget.settings,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.item,
    required this.settings,
    this.playlist = const [],
    this.position = 0,
    this.startFullscreen = false,
  });
  final MediaItem item;
  final AppSettings settings;
  final List<MediaItem> playlist;
  final int position;
  final bool startFullscreen;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player player;
  late final VideoController controller;
  final channelFocus = FocusNode();
  final videoKey = GlobalKey<VideoState>();
  late final List<MediaItem> playlist;
  late int position;
  Timer? nowPlayingTimer;
  bool showNowPlaying = true;
  bool isDisposing = false;
  Future<void> playerOperations = Future.value();

  MediaItem get current => playlist[position];

  @override
  void initState() {
    super.initState();
    playlist = widget.playlist.isEmpty ? [widget.item] : widget.playlist;
    position = widget.position.clamp(0, playlist.length - 1);
    player = Player(
      configuration: PlayerConfiguration(
        bufferSize: widget.settings.bufferSize,
        title: 'StreamVista',
      ),
    );
    controller = VideoController(player);
    channelFocus.onKeyEvent = _onKey;
    _openCurrent();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => channelFocus.requestFocus());
    if (widget.startFullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (mounted) await videoKey.currentState?.enterFullscreen();
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _changeChannel(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _changeChannel(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openCurrent() {
    _showNowPlayingForTenSeconds();
    final media = Media(current.streamUrl, httpHeaders: current.headers);
    playerOperations = playerOperations.catchError((_) {}).then((_) async {
      if (isDisposing) return;
      try {
        await player.open(media);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('No se pudo abrir esta transmisión: $error')),
          );
        }
      }
    });
  }

  void _showNowPlayingForTenSeconds() {
    nowPlayingTimer?.cancel();
    if (!showNowPlaying && mounted) setState(() => showNowPlaying = true);
    nowPlayingTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => showNowPlaying = false);
    });
  }

  void _showPlaybackInfo() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: _PlaybackInfo(
          player: player,
          item: current,
          hasChannelList: playlist.length > 1,
        ),
      ),
    );
  }

  void _showVolumeControl() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: StreamBuilder<double>(
            stream: player.stream.volume,
            initialData: player.state.volume,
            builder: (context, snapshot) {
              final volume = (snapshot.data ?? 100).clamp(0, 100).toDouble();
              return Row(children: [
                Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: volume,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${volume.round()}%',
                    onChanged: (value) => unawaited(player.setVolume(value)),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${volume.round()}%', textAlign: TextAlign.end),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  void _changeChannel(int offset) {
    if (playlist.length < 2) return;
    setState(() => position = (position + offset) % playlist.length);
    _openCurrent();
  }

  void _selectChannel(int index) {
    if (index == position) return;
    setState(() => position = index);
    _openCurrent();
  }

  @override
  void dispose() {
    isDisposing = true;
    nowPlayingTimer?.cancel();
    channelFocus.dispose();
    unawaited(playerOperations.whenComplete(player.dispose).catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            toolbarHeight: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: Text(current.title),
            actions: [
              IconButton(
                tooltip: 'Volumen',
                onPressed: _showVolumeControl,
                icon: const Icon(Icons.volume_up_outlined),
              ),
              IconButton(
                tooltip: 'Información de reproducción',
                onPressed: _showPlaybackInfo,
                icon: const Icon(Icons.info_outline),
              ),
            ]),
        body: LayoutBuilder(builder: (context, constraints) {
          final playerView = Column(children: [
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _showNowPlayingForTenSeconds(),
                child: Stack(children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: MaterialVideoControlsTheme(
                        normal: const MaterialVideoControlsThemeData(
                          displaySeekBar: false,
                          visibleOnMount: true,
                          controlsHoverDuration: Duration(seconds: 10),
                          controlsTransitionDuration:
                              Duration(milliseconds: 180),
                          volumeGesture: true,
                        ),
                        fullscreen: MaterialVideoControlsThemeData(
                          displaySeekBar: false,
                          visibleOnMount: true,
                          controlsHoverDuration: Duration(seconds: 10),
                          controlsTransitionDuration:
                              Duration(milliseconds: 180),
                          volumeGesture: true,
                          backdropColor: Colors.black38,
                          buttonBarHeight: 64,
                          topButtonBarMargin:
                              const EdgeInsets.symmetric(horizontal: 18),
                          bottomButtonBarMargin:
                              const EdgeInsets.fromLTRB(22, 0, 22, 22),
                          topButtonBar: [
                            _FullscreenChannelHeader(item: current),
                          ],
                          primaryButtonBar: [
                            _FullscreenControlButton(
                                icon: Icons.skip_previous_rounded,
                                onPressed: () => _changeChannel(-1)),
                            const SizedBox(width: 18),
                            StreamBuilder<bool>(
                              stream: player.stream.playing,
                              initialData: player.state.playing,
                              builder: (context, snapshot) =>
                                  _FullscreenControlButton(
                                icon: snapshot.data == true
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                primary: true,
                                onPressed: () =>
                                    unawaited(player.playOrPause()),
                              ),
                            ),
                            const SizedBox(width: 18),
                            _FullscreenControlButton(
                                icon: Icons.skip_next_rounded,
                                onPressed: () => _changeChannel(1)),
                          ],
                          bottomButtonBar: [
                            _FullscreenTransmissionInfo(item: current),
                            const Spacer(),
                            IconButton(
                                tooltip: 'Subtitles',
                                onPressed: _showPlaybackInfo,
                                icon: const Icon(Icons.subtitles_outlined)),
                            IconButton(
                                tooltip: 'Audio',
                                onPressed: _showVolumeControl,
                                icon: const Icon(Icons.graphic_eq_rounded)),
                            IconButton(
                                tooltip: 'Favorite',
                                onPressed: () {},
                                icon:
                                    const Icon(Icons.favorite_border_rounded)),
                            IconButton(
                                tooltip: 'Exit fullscreen',
                                onPressed: () => unawaited(
                                    videoKey.currentState?.exitFullscreen()),
                                icon:
                                    const Icon(Icons.fullscreen_exit_rounded)),
                          ],
                        ),
                        child: Video(
                          key: videoKey,
                          controller: controller,
                          controls: MaterialVideoControls,
                          focusNode: channelFocus,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: AbsorbPointer(
                      absorbing: false,
                      child: AnimatedOpacity(
                        opacity: showNowPlaying ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(children: [
                              const _LivePill(),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(current.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800))),
                              IconButton(
                                  onPressed: () => Navigator.maybePop(context),
                                  icon: const Icon(Icons.arrow_back_rounded,
                                      size: 20)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
          return playerView;
        }),
      );
}

class _FullscreenChannelHeader extends StatelessWidget {
  const _FullscreenChannelHeader({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            _ChannelLogo(item: item, active: true, large: true),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 12),
            const _LivePill(),
          ]),
        ),
      );
}

class _FullscreenControlButton extends StatelessWidget {
  const _FullscreenControlButton(
      {required this.icon, required this.onPressed, this.primary = false});
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
        color: primary ? _accent : Colors.black45,
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: primary ? 39 : 28),
          color: Colors.white,
          iconSize: primary ? 39 : 28,
          padding: EdgeInsets.all(primary ? 16 : 11),
        ),
      );
}

class _FullscreenTransmissionInfo extends StatelessWidget {
  const _FullscreenTransmissionInfo({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        const _LivePill(),
        const SizedBox(width: 10),
        const Text('LIVE', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(width: 9),
        Container(width: 1, height: 18, color: Colors.white38),
        const SizedBox(width: 9),
        Text(item.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Colors.white70)),
      ]);
}

class _ChannelSidebar extends StatefulWidget {
  const _ChannelSidebar({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<MediaItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  State<_ChannelSidebar> createState() => _ChannelSidebarState();
}

class _ChannelSidebarState extends State<_ChannelSidebar> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Text('CANALES · ${widget.items.length}',
                style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: ListView.builder(
                controller: controller,
                itemCount: widget.items.length,
                itemBuilder: (_, index) {
                  final item = widget.items[index];
                  final active = index == widget.selected;
                  return ListTile(
                    dense: true,
                    selected: active,
                    selectedTileColor: _accent.withValues(alpha: .2),
                    leading: Icon(
                        active
                            ? Icons.play_circle_filled
                            : Icons.play_circle_outline,
                        color: active ? _accent : null),
                    title: Text(item.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.category,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => widget.onSelected(index),
                  );
                },
              ),
            ),
          ),
        ]),
      );
}

class _PlaybackInfo extends StatelessWidget {
  const _PlaybackInfo({
    required this.player,
    required this.item,
    required this.hasChannelList,
  });

  final Player player;
  final MediaItem item;
  final bool hasChannelList;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (context, playing) => StreamBuilder<bool>(
          stream: player.stream.buffering,
          initialData: player.state.buffering,
          builder: (context, buffering) => StreamBuilder<int?>(
            stream: player.stream.width,
            initialData: player.state.width,
            builder: (context, width) => StreamBuilder<int?>(
              stream: player.stream.height,
              initialData: player.state.height,
              builder: (context, height) {
                final waiting = buffering.data == true;
                final online = playing.data == true && !waiting;
                final state = waiting
                    ? 'Conectando…'
                    : online
                        ? 'Conectado'
                        : 'Esperando señal';
                final transmission = switch (item.kind) {
                  MediaKind.live => 'En directo',
                  MediaKind.movie => 'Video bajo demanda',
                  MediaKind.series => 'Episodio de serie',
                };
                final resolution = width.data == null || height.data == null
                    ? 'Detectando…'
                    : '${width.data} × ${height.data}';
                return Container(
                  width: double.infinity,
                  color: _surface,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: Wrap(spacing: 28, runSpacing: 12, children: [
                    _InfoField(label: 'WATCHING', value: item.title),
                    _InfoField(label: 'CATEGORY', value: item.category),
                    _InfoField(label: 'RESOLUTION', value: resolution),
                    _InfoField(
                        label: 'TRANSMISSION',
                        value: '$transmission · $state',
                        color:
                            online ? Colors.greenAccent : Colors.amberAccent),
                    _InfoField(
                        label: 'SOURCE', value: _streamFormat(item.streamUrl)),
                    if (hasChannelList)
                      const _InfoField(
                        label: 'CHANGE CHANNEL',
                        value: 'Up / Down or Page Up / Page Down',
                      ),
                  ]),
                );
              },
            ),
          ),
        ),
      );

  String _streamFormat(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path.toLowerCase() ?? '';
    if (path.endsWith('.m3u8')) return 'HLS';
    if (path.endsWith('.ts')) return 'MPEG-TS';
    if (path.endsWith('.mp4')) return 'MP4';
    final scheme = uri?.scheme.toUpperCase();
    return scheme == null || scheme.isEmpty ? 'Stream' : '$scheme stream';
  }
}

class _InfoField extends StatelessWidget {
  const _InfoField({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 180,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}
