import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

class _PortalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) SharedPreferencesWindows.registerWith();
  HttpOverrides.global = _PortalHttpOverrides();
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

  // Live streams benefit from a deeper demuxer cache. This absorbs brief Wi-Fi
  // or provider hiccups without making on-demand seeking less responsive.
  int bufferSizeFor(MediaKind kind) {
    if (kind != MediaKind.live) return bufferSize;
    return switch (profile) {
      PlaybackProfile.balanced => 96 * 1024 * 1024,
      PlaybackProfile.hd => 192 * 1024 * 1024,
      PlaybackProfile.ultra => 256 * 1024 * 1024,
    };
  }

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
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'portal',
        jsonEncode({
          'type': type.name,
          'server': server,
          'username': username,
          'password': password,
          'userAgent': userAgent
        }));
  }

  static Future<PortalConfig?> restore() async {
    final raw = (await SharedPreferences.getInstance()).getString('portal');
    if (raw == null) return null;
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

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove('portal');
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

const _vodExtensions = {
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'm4v', 'webm', 'mpg', 'mpeg',
  '3gp', 'divx', 'ogv',
};

String _normalize(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

bool _hasWord(String text, List<String> words) =>
    words.any((w) => RegExp('(^|[^a-z])$w([^a-z]|\$)').hasMatch(text));

/// Decides whether an M3U entry is live TV, a movie or a series episode.
/// Signals are checked from most to least reliable: an explicit type
/// attribute, the Xtream-style URL path (/live/, /movie/, /series/), an
/// episode pattern in the title, a video-file extension, the group name and
/// finally the EXTINF duration. Anything left over is live TV.
MediaKind classifyM3uEntry({
  required String metadata,
  required String url,
  required String group,
  required String title,
}) {
  final type = RegExp(r'(?:tvg-type|type)="([^"]*)"', caseSensitive: false)
      .firstMatch(metadata)
      ?.group(1);
  if (type != null) {
    final t = _normalize(type);
    if (_hasWord(t, ['series', 'serie', 'show', 'shows', 'episode'])) {
      return MediaKind.series;
    }
    if (_hasWord(t, ['movie', 'movies', 'vod', 'film', 'pelicula'])) {
      return MediaKind.movie;
    }
    if (_hasWord(t, ['live', 'channel', 'tv', 'stream'])) return MediaKind.live;
  }

  final uri = Uri.tryParse(url);
  final segments =
      uri?.pathSegments.map((e) => e.toLowerCase()).toList() ?? const [];
  if (segments.contains('series')) return MediaKind.series;
  if (segments.contains('movie') || segments.contains('movies')) {
    return MediaKind.movie;
  }
  if (segments.contains('live')) return MediaKind.live;

  final g = _normalize(group);
  final n = _normalize(title);
  const seriesWords = [
    'series', 'serie', 'tv shows', 'shows', 'novelas', 'telenovelas',
    'temporada', 'temporadas', 'season', 'seasons', 'doramas', 'anime',
    'docuseries', 'miniseries',
  ];
  const movieWords = [
    'movies', 'movie', 'films', 'film', 'peliculas', 'pelicula', 'cine',
    'cinema', 'vod', 'filmes', 'estrenos',
  ];
  const liveWords = ['canal', 'canales', 'channel', 'channels', '24/7', 'live'];

  final episode = RegExp(
          r'(^|[^a-z0-9])(s\d{1,2}\s*e\d{1,3}|t\d{1,2}\s*e\d{1,3}|\d{1,2}x\d{2})([^a-z0-9]|$)')
      .hasMatch(n);
  if (episode) return MediaKind.series;

  final last = segments.isEmpty ? '' : segments.last;
  final dot = last.lastIndexOf('.');
  final ext = dot >= 0 ? last.substring(dot + 1) : '';
  if (_vodExtensions.contains(ext)) {
    return _hasWord(g, seriesWords) ? MediaKind.series : MediaKind.movie;
  }

  if (!_hasWord(g, liveWords)) {
    if (_hasWord(g, seriesWords)) return MediaKind.series;
    if (_hasWord(g, movieWords)) return MediaKind.movie;
  }

  final duration = double.tryParse(
          RegExp(r'^#EXTINF:\s*(-?[\d.]+)').firstMatch(metadata)?.group(1) ??
              '') ??
      -1;
  if (duration > 0) return MediaKind.movie;
  return MediaKind.live;
}

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
      final generatedStream = kind == MediaKind.series
          ? ''
          : '${config.normalizedServer}/$segment/${config.username}/${config.password}/$id.$extension';
      final stream = _sourceOrGenerated(
        x['direct_source']?.toString(),
        generatedStream,
      );
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
        final title =
            RegExp(r',(.*)$').firstMatch(metadata)?.group(1)?.trim() ??
                'Sin título';
        final group =
            RegExp(r'group-title="([^"]*)"').firstMatch(metadata)?.group(1) ??
                'TV en vivo';
        final logo =
            RegExp(r'tvg-logo="([^"]*)"').firstMatch(metadata)?.group(1);
        final itemKind = classifyM3uEntry(
            metadata: metadata, url: line.trim(), group: group, title: title);
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
          streamUrl: _sourceOrGenerated(
            value['direct_source']?.toString(),
            '${config.normalizedServer}/series/${config.username}/${config.password}/$id.$extension',
          ),
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

  String _sourceOrGenerated(String? source, String generated) {
    final direct = source?.trim();
    final uri = direct == null ? null : Uri.tryParse(direct);
    return uri?.hasScheme == true ? direct! : generated;
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
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            final paired = await Navigator.push<PortalConfig>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PairDevicePage()),
                            );
                            if (paired != null) widget.onConnected(paired);
                          },
                    icon: const Icon(Icons.phonelink_lock_outlined),
                    label: const Text('Vincular desde la web'),
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

class PairDevicePage extends StatefulWidget {
  const PairDevicePage({super.key});
  @override
  State<PairDevicePage> createState() => _PairDevicePageState();
}

class _PairDevicePageState extends State<PairDevicePage> {
  final endpoint = TextEditingController();
  final random = Random.secure();
  Timer? poller;
  String? deviceId;
  String? pin;
  String status = 'Introduce la URL de tu portal de StreamVista.';
  bool loading = false;

  @override
  void dispose() {
    poller?.cancel();
    endpoint.dispose();
    super.dispose();
  }

  Future<void> begin() async {
    final base = endpoint.text.trim().replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
      setState(() => status = 'Introduce una URL HTTPS v\u00e1lida.');
      return;
    }
    final id =
        'SV-${List.generate(24, (_) => random.nextInt(16).toRadixString(16).toUpperCase()).join()}';
    final code = (100000 + random.nextInt(900000)).toString();
    setState(() {
      loading = true;
      status = 'Registrando dispositivo\u2026';
    });
    try {
      final response = await http
          .post(Uri.parse('$base/register'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'deviceId': id, 'pin': code}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 204)
        throw Exception('El portal no acept\u00f3 el dispositivo.');
      setState(() {
        deviceId = id;
        pin = code;
        loading = false;
        status =
            'En la web, inicia sesi\u00f3n y env\u00eda una lista a este dispositivo.';
      });
      poller = Timer.periodic(
          const Duration(seconds: 5), (_) => _poll(base, id, code));
    } catch (error) {
      if (mounted)
        setState(() {
          loading = false;
          status = 'No se pudo conectar: $error';
        });
    }
  }

  Future<void> _poll(String base, String id, String code) async {
    try {
      final response = await http
          .get(Uri.parse('$base/config')
              .replace(queryParameters: {'deviceId': id, 'pin': code}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 204) return;
      if (response.statusCode != 200)
        throw Exception('El portal respondi\u00f3 ${response.statusCode}.');
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final config = PortalConfig(
          type: SourceType.values.byName(data['sourceType'] as String),
          server: data['server'] as String,
          username: data['username'] as String?,
          password: data['password'] as String?,
          userAgent: data['userAgent'] as String?);
      await config.save();
      poller?.cancel();
      if (mounted) Navigator.pop(context, config);
    } catch (error) {
      if (mounted)
        setState(() => status = 'Esperando configuraci\u00f3n: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vincular dispositivo')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Gestiona tus listas desde la web',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        const Text(
                            'No uses una direcci\u00f3n MAC. StreamVista crea un ID privado que funciona en TV, tablet y m\u00f3vil.'),
                        const SizedBox(height: 20),
                        TextField(
                            controller: endpoint,
                            enabled: deviceId == null,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                                labelText:
                                    'URL de la funci\u00f3n de emparejamiento',
                                hintText:
                                    'https://us-central1-tu-proyecto.cloudfunctions.net/pairing')),
                        const SizedBox(height: 14),
                        if (deviceId == null)
                          FilledButton(
                              onPressed: loading ? null : begin,
                              child: loading
                                  ? const CircularProgressIndicator()
                                  : const Text('Generar c\u00f3digo'))
                        else ...[
                          SelectableText(deviceId!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          SelectableText(pin!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 8)),
                        ],
                        const SizedBox(height: 16),
                        Text(status, textAlign: TextAlign.center),
                      ]),
                ))),
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
                      if (!compact) ...[
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
                            icon: Icons.notifications_none_rounded,
                            onTap: () {}),
                      ] else
                        const Spacer(),
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
                              compact: compact,
                              onTap: () => onOpen(0)),
                          _HomeTile(
                              icon: Icons.local_movies_rounded,
                              title: 'Movies',
                              subtitle: 'On demand',
                              compact: compact,
                              onTap: () => onOpen(1)),
                          _HomeTile(
                              icon: Icons.video_library_rounded,
                              title: 'Series',
                              subtitle: 'Shows',
                              compact: compact,
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
      required this.compact,
      this.selected = false});
  final IconData icon;
  final String title, subtitle;
  final bool compact, selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
          width: compact ? 220 : 250,
          height: compact ? 190 : 275,
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
            Icon(icon, size: compact ? 55 : 72, color: Colors.white),
            SizedBox(height: compact ? 14 : 23),
            Text(title,
                style: TextStyle(
                    fontSize: compact ? 23 : 27, fontWeight: FontWeight.w800)),
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
                        '64 MB bajo demanda · 96 MB en TV en directo',
                      PlaybackProfile.hd =>
                        '128 MB bajo demanda · 192 MB en TV en directo',
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
                            const _BrandMark(size: 30),
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

  void _open(MediaItem item, int index, List<MediaItem> items) =>
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PlayerPage(
                  item: item,
                  playlist: items,
                  position: index,
                  settings: widget.settings)));

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
                children:
                    ['All', ...widget.items.map((i) => i.category).toSet()]
                        .map((name) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(name),
                                selected: category == name,
                                onSelected: (_) => setState(() {
                                      category = name;
                                      selected = 0;
                                    }))))
                        .toList())),
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
                            onDoubleTap: () => _open(item, index, shown),
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
          const _BrandMark(size: 32),
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

class _OnDemandPill extends StatelessWidget {
  const _OnDemandPill();

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: _accent, borderRadius: BorderRadius.circular(14)),
      child: const Text('ON DEMAND',
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
  });
  final MediaItem item;
  final AppSettings settings;
  final List<MediaItem> playlist;
  final int position;
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
  bool isStopping = false;
  Future<void> playerOperations = Future.value();

  MediaItem get current => playlist[position];
  bool get canSeek => current.kind != MediaKind.live;

  @override
  void initState() {
    super.initState();
    playlist = widget.playlist.isEmpty ? [widget.item] : widget.playlist;
    position = widget.position.clamp(0, playlist.length - 1);
    player = Player(
      configuration: PlayerConfiguration(
        bufferSize: widget.settings.bufferSizeFor(current.kind),
        title: 'StreamVista',
      ),
    );
    controller = VideoController(
      player,
      configuration: Platform.isLinux
          ? const VideoControllerConfiguration(
              hwdec: 'auto-copy',
              enableHardwareAcceleration: false,
            )
          : const VideoControllerConfiguration(),
    );
    channelFocus.onKeyEvent = _onKey;
    _openCurrent();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => channelFocus.requestFocus());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _showNowPlayingForTenSeconds();
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
    if (canSeek && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _skip(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    if (canSeek && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _skip(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _skip(Duration offset) {
    if (!canSeek) return;
    _showNowPlayingForTenSeconds();
    final duration = player.state.duration;
    var target = player.state.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    unawaited(player.seek(target));
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

  void _toggleFullscreen() {
    _showNowPlayingForTenSeconds();
    final videoState = videoKey.currentState;
    if (videoState != null) unawaited(videoState.toggleFullscreen());
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

  void _stopPlayback() {
    if (isStopping || isDisposing) return;
    setState(() => isStopping = true);
    playerOperations = playerOperations.catchError((_) {}).then((_) async {
      await player.stop();
    });
    unawaited(playerOperations.then((_) {
      if (mounted) Navigator.maybePop(context);
    }).catchError((_) {
      if (mounted) setState(() => isStopping = false);
    }));
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
              child: MouseRegion(
                onHover: (_) => _showNowPlayingForTenSeconds(),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _showNowPlayingForTenSeconds(),
                  child: Stack(children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: MaterialVideoControlsTheme(
                        normal: MaterialVideoControlsThemeData(
                          // The overlay below draws its own time bar for
                          // movies and episodes, so the built-in one is off.
                          displaySeekBar: false,
                          visibleOnMount: true,
                          controlsHoverDuration: Duration(seconds: 10),
                          controlsTransitionDuration:
                              Duration(milliseconds: 180),
                          volumeGesture: true,
                        ),
                        fullscreen: MaterialVideoControlsThemeData(
                          displaySeekBar: canSeek,
                          seekOnDoubleTap: canSeek,
                          primaryButtonBar: canSeek
                              ? [
                                  const Spacer(flex: 2),
                                  MaterialCustomButton(
                                    icon: const Icon(Icons.replay_10_rounded),
                                    iconSize: 40,
                                    onPressed: () => _skip(
                                        const Duration(seconds: -10)),
                                  ),
                                  const Spacer(),
                                  const MaterialPlayOrPauseButton(
                                      iconSize: 56),
                                  const Spacer(),
                                  MaterialCustomButton(
                                    icon: const Icon(Icons.forward_10_rounded),
                                    iconSize: 40,
                                    onPressed: () =>
                                        _skip(const Duration(seconds: 10)),
                                  ),
                                  const Spacer(flex: 2),
                                ]
                              : const [
                                  Spacer(flex: 2),
                                  MaterialPlayOrPauseButton(iconSize: 56),
                                  Spacer(flex: 2),
                                ],
                          bottomButtonBar: [
                            if (canSeek) const MaterialPositionIndicator(),
                            const Spacer(),
                            const MaterialFullscreenButton(),
                          ],
                          visibleOnMount: true,
                          controlsHoverDuration: Duration(seconds: 10),
                          controlsTransitionDuration:
                              Duration(milliseconds: 180),
                          volumeGesture: true,
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
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _LivePlayerHeader(
                        item: current,
                        visible: showNowPlaying,
                        isLive: current.kind == MediaKind.live,
                        onBack: () => Navigator.maybePop(context),
                      ),
                    ),
                  Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _LivePlayerOverlay(
                        item: current,
                        player: player,
                        visible: showNowPlaying,
                        isLive: current.kind == MediaKind.live,
                        canChangeChannel: playlist.length > 1,
                        onRewind: () =>
                            _skip(const Duration(seconds: -10)),
                        onForward: () => _skip(const Duration(seconds: 10)),
                        onPrevious: () => _changeChannel(-1),
                        onNext: () => _changeChannel(1),
                        onVolume: _showVolumeControl,
                        onFullscreen: _toggleFullscreen,
                        onInteraction: _showNowPlayingForTenSeconds,
                      ),
                    ),
                ]),
                ),
              ),
            ),
          ]);
          return playerView;
        }),
      );
}

class _PlayerBottomMenu extends StatelessWidget {
  const _PlayerBottomMenu({
    required this.visible,
    required this.selectedIndex,
    required this.onSelected,
    required this.onInteraction,
  });

  final bool visible;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onInteraction;

  static const _items = <_PlayerMenuItem>[
    _PlayerMenuItem(Icons.favorite_border_rounded, 'Favorita', Color(0xFFFFD900)),
    _PlayerMenuItem(Icons.movie_filter_outlined, 'Cine', Color(0xFFFF3B30)),
    _PlayerMenuItem(Icons.video_library_outlined, 'Serie', Color(0xFF35D05E)),
    _PlayerMenuItem(Icons.search_rounded, 'Buscar'),
    _PlayerMenuItem(Icons.chat_bubble_outline_rounded, 'Pista de subtítulos'),
    _PlayerMenuItem(Icons.music_note_rounded, 'Pista de audio'),
  ];

  @override
  Widget build(BuildContext context) => Focus(
        onKeyEvent: (_, __) {
          onInteraction();
          return KeyEventResult.ignored;
        },
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, .28),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color.fromRGBO(0, 0, 0, .78),
                    border: Border(top: BorderSide(color: Colors.white12)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      return SizedBox(
                        height: compact ? 88 : 102,
                        child: Row(
                          children: List.generate(_items.length, (index) {
                            final item = _items[index];
                            return Expanded(
                              child: _PlayerMenuButton(
                                item: item,
                                selected: index == selectedIndex,
                                compact: compact,
                                onPressed: () => onSelected(index),
                                onFocus: onInteraction,
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
          ),
        ),
      );
}

class _PlayerMenuItem {
  const _PlayerMenuItem(this.icon, this.label, [this.indicator]);
  final IconData icon;
  final String label;
  final Color? indicator;
}

class _PlayerMenuButton extends StatelessWidget {
  const _PlayerMenuButton({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onPressed,
    required this.onFocus,
  });

  final _PlayerMenuItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? Colors.white : const Color(0xFFD3D3D3);
    final labelColor = selected ? Colors.white : const Color(0xFFD0D0D0);
    final iconSize = selected ? (compact ? 31.0 : 35.0) : (compact ? 25.0 : 28.0);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: TextButton(
        onPressed: onPressed,
        onFocusChange: (hasFocus) {
          if (hasFocus) onFocus();
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          shape: const RoundedRectangleBorder(),
          foregroundColor: Colors.white,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: selected ? (compact ? 48 : 56) : (compact ? 38 : 44),
            height: selected ? (compact ? 48 : 56) : (compact ? 38 : 44),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFBFC1BA).withValues(alpha: .72) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: iconColor, size: iconSize),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: compact ? 22 : 25,
            child: Text(
              item.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: compact ? 9 : 12,
                height: 1.1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 3,
            width: item.indicator == null ? 0 : (compact ? 27 : 38),
            decoration: BoxDecoration(
              color: item.indicator,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LivePlayerOverlay extends StatelessWidget {
  const _LivePlayerOverlay({
    required this.item,
    required this.player,
    required this.visible,
    required this.isLive,
    required this.canChangeChannel,
    required this.onRewind,
    required this.onForward,
    required this.onPrevious,
    required this.onNext,
    required this.onVolume,
    required this.onFullscreen,
    required this.onInteraction,
  });

  final MediaItem item;
  final bool visible;
  final bool isLive;
  final Player player;
  final bool canChangeChannel;
  final VoidCallback onRewind, onForward;
  final VoidCallback onPrevious, onNext, onVolume, onFullscreen;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) => Focus(
        onKeyEvent: (_, __) {
          onInteraction();
          return KeyEventResult.ignored;
        },
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, .22),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xD9000000), Color(0x99000000), Colors.transparent],
                  stops: [0, .72, 1],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 42, 28, 18),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final compact = constraints.maxWidth < 560;
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        if (item.logo?.isNotEmpty == true)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Image.network(item.logo!, width: 38, height: 38, fit: BoxFit.cover),
                          )
                        else
                          const Icon(Icons.live_tv_rounded, size: 34),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(isLive ? 'EN DIRECTO' : 'REPRODUCIENDO', style: TextStyle(color: isLive ? const Color(0xFFFF4545) : const Color(0xFF67D7FF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 15 : 18, fontWeight: FontWeight.w800)),
                          Text(item.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFD0D0D0), fontSize: 12)),
                        ])),
                        _LiveControlButton(tooltip: 'Volumen', icon: Icons.volume_up_outlined, onPressed: onVolume),
                        _LiveControlButton(tooltip: 'Pantalla completa', icon: Icons.fullscreen_rounded, onPressed: onFullscreen),
                      ]),
                      const SizedBox(height: 18),
                      if (isLive)
                        const Divider(color: Colors.white30, height: 1)
                      else
                        _VodTimeBar(player: player, onInteraction: onInteraction),
                      const SizedBox(height: 14),
                      if (isLive)
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _LiveControlButton(tooltip: 'Canal anterior', icon: Icons.skip_previous_rounded, label: compact ? null : 'Anterior', onPressed: canChangeChannel ? onPrevious : null),
                          const SizedBox(width: 24),
                          _LiveControlButton(tooltip: 'Canal siguiente', icon: Icons.skip_next_rounded, label: compact ? null : 'Siguiente', onPressed: canChangeChannel ? onNext : null),
                        ])
                      else
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (canChangeChannel) ...[
                            _LiveControlButton(tooltip: 'Anterior', icon: Icons.skip_previous_rounded, onPressed: onPrevious),
                            SizedBox(width: compact ? 8 : 20),
                          ],
                          _LiveControlButton(tooltip: 'Retroceder 10 segundos', icon: Icons.replay_10_rounded, label: compact ? null : '-10 s', onPressed: onRewind),
                          SizedBox(width: compact ? 8 : 20),
                          StreamBuilder<bool>(
                            stream: player.stream.playing,
                            initialData: player.state.playing,
                            builder: (_, playing) => _LiveControlButton(
                              tooltip: playing.data == true ? 'Pausa' : 'Reproducir',
                              icon: playing.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              onPressed: () => unawaited(player.playOrPause()),
                            ),
                          ),
                          SizedBox(width: compact ? 8 : 20),
                          _LiveControlButton(tooltip: 'Adelantar 10 segundos', icon: Icons.forward_10_rounded, label: compact ? null : '+10 s', onPressed: onForward),
                          if (canChangeChannel) ...[
                            SizedBox(width: compact ? 8 : 20),
                            _LiveControlButton(tooltip: 'Siguiente', icon: Icons.skip_next_rounded, onPressed: onNext),
                          ],
                        ]),
                    ]);
                  }),
                ),
              ),
            ),
          ),
          ),
        ),
      );
}

/// Time bar for movies and episodes: elapsed time, a draggable slider and the
/// total duration. Live streams don't use it because they have no end.
class _VodTimeBar extends StatefulWidget {
  const _VodTimeBar({required this.player, required this.onInteraction});
  final Player player;
  final VoidCallback onInteraction;

  @override
  State<_VodTimeBar> createState() => _VodTimeBarState();
}

class _VodTimeBarState extends State<_VodTimeBar> {
  // Slider value while the user drags, so the thumb doesn't jump back to the
  // playback position until the seek is released.
  double? dragMs;

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
        stream: widget.player.stream.duration,
        initialData: widget.player.state.duration,
        builder: (context, durationSnap) => StreamBuilder<Duration>(
          stream: widget.player.stream.position,
          initialData: widget.player.state.position,
          builder: (context, positionSnap) {
            final duration = durationSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final positionMs = (positionSnap.data ?? Duration.zero)
                .inMilliseconds
                .toDouble()
                .clamp(0.0, maxMs > 0 ? maxMs : 0.0);
            final value = (dragMs ?? positionMs).clamp(0.0, maxMs > 0 ? maxMs : 0.0);
            const timeStyle = TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            );
            return Row(children: [
              Text(_format(Duration(milliseconds: value.round())), style: timeStyle),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: _accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: value,
                    max: maxMs > 0 ? maxMs : 1,
                    onChangeStart: maxMs > 0
                        ? (v) {
                            widget.onInteraction();
                            setState(() => dragMs = v);
                          }
                        : null,
                    onChanged: maxMs > 0
                        ? (v) {
                            widget.onInteraction();
                            setState(() => dragMs = v);
                          }
                        : null,
                    onChangeEnd: maxMs > 0
                        ? (v) {
                            setState(() => dragMs = null);
                            unawaited(widget.player
                                .seek(Duration(milliseconds: v.round())));
                          }
                        : null,
                  ),
                ),
              ),
              Text(maxMs > 0 ? _format(duration) : '--:--', style: timeStyle),
            ]);
          },
        ),
      );
}

class _LivePlayerHeader extends StatelessWidget {
  const _LivePlayerHeader({
    required this.item,
    required this.visible,
    required this.isLive,
    required this.onBack,
  });

  final MediaItem item;
  final bool visible;
  final bool isLive;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 42),
                child: Row(children: [
                  _LiveControlButton(
                    tooltip: 'Volver',
                    icon: Icons.arrow_back_rounded,
                    onPressed: onBack,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.circle,
                              size: 11, color: Color(0xFFFF504D)),
                          const SizedBox(width: 6),
                          Text(isLive ? 'EN DIRECTO' : 'REPRODUCIENDO',
                              style: TextStyle(
                                  color: isLive
                                      ? const Color(0xFFFF5B55)
                                      : const Color(0xFF67D7FF),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(item.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _LiveControlButton extends StatelessWidget {
  const _LiveControlButton({required this.tooltip, required this.icon, required this.onPressed, this.label});
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 27),
          label: label == null ? const SizedBox.shrink() : Text(label!),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white38,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            backgroundColor: const Color(0x59000000),
            shape: const StadiumBorder(),
          ),
        ),
      );
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
