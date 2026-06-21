import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Tiny cached HTTP layer, ported from the Python `Net` class.
///
/// On device there is no need to persist responses to disk between runs, so the
/// cache is in-memory and lives for the duration of one analysis. It still
/// dedupes repeated calls (e.g. the same bbox queried twice) and retries with
/// backoff on transient throttling, exactly like the reference implementation.
class Net {
  final Map<String, dynamic> _jsonCache = {};
  final Map<String, String> _textCache = {};
  final http.Client _client = http.Client();

  /// Optional callback so the UI can show what the analyzer is doing.
  final void Function(String message)? onProgress;

  Net({this.onProgress});

  void close() => _client.close();

  String _key(String tag, String url, String? body) => '$tag|$url|${body ?? ''}';

  Future<String> _fetch(
    String url, {
    String? body,
    Map<String, String>? headers,
    String method = 'GET',
    Duration timeout = const Duration(seconds: 25),
    int tries = 2,
  }) async {
    Object? last;
    for (var i = 0; i < tries; i++) {
      try {
        final uri = Uri.parse(url);
        final h = headers ?? {'User-Agent': 'gpx-water-analysis'};
        late http.Response resp;
        if (body != null || method == 'POST') {
          resp = await _client
              .post(uri, headers: h, body: body)
              .timeout(timeout);
        } else {
          resp = await _client.get(uri, headers: h).timeout(timeout);
        }
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return resp.body;
        }
        last = 'HTTP ${resp.statusCode}';
        if (resp.statusCode == 404) break; // not found won't fix with retry
      } catch (ex) {
        last = ex;
      }
      // one short backoff on transient throttling; don't sleep after the last try
      if (i < tries - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    throw Exception('fetch failed for $url: $last');
  }

  Future<dynamic> getJson(
    String tag,
    String url, {
    String? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final key = _key(tag, url, body);
    if (_jsonCache.containsKey(key)) return _jsonCache[key];
    final raw = await _fetch(url,
        body: body,
        headers: headers,
        method: body != null ? 'POST' : 'GET',
        timeout: timeout);
    final data = jsonDecode(raw);
    _jsonCache[key] = data;
    return data;
  }

  Future<String> getText(
    String tag,
    String url, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final key = _key(tag, url, null);
    if (_textCache.containsKey(key)) return _textCache[key]!;
    final raw = await _fetch(url, timeout: timeout);
    _textCache[key] = raw;
    return raw;
  }
}
