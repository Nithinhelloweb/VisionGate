import 'dart:convert';
import 'package:http/http.dart' as http;
import 'cache_service.dart';

/// Custom HTTP client for fast, cached API requests with connection pooling.
class ApiClient {
  final http.Client _client = http.Client();
  final CacheService _cacheService = CacheService();
  static const Duration defaultTimeout = Duration(seconds: 15);

  Map<String, String> _buildHeaders({
    String? token,
    Map<String, String>? extraHeaders,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept-Encoding': 'gzip, deflate',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  Future<http.Response> get(
    String url, {
    String? token,
    String? cacheKey,
    Duration? cacheDuration,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final key = cacheKey;
    final maxAge = cacheDuration ?? CacheService.defaultCacheDuration;

    // Return cached response instantly if available and requested
    if (key != null) {
      final cachedBody = _cacheService.get(key, maxAge: maxAge);
      if (cachedBody != null) {
        return http.Response(
          cachedBody,
          200,
          headers: {'x-cache': 'HIT', 'content-type': 'application/json'},
        );
      }
    }

    final response = await _client
        .get(
          Uri.parse(url),
          headers: _buildHeaders(token: token, extraHeaders: headers),
        )
        .timeout(timeout ?? defaultTimeout);

    // Save to cache on successful GET
    if (key != null && response.statusCode == 200) {
      _cacheService.set(key, response.body);
    }

    return response;
  }

  Future<http.Response> post(
    String url, {
    String? token,
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    return _client
        .post(
          Uri.parse(url),
          headers: _buildHeaders(token: token, extraHeaders: headers),
          body: body,
          encoding: encoding,
        )
        .timeout(timeout ?? defaultTimeout);
  }

  Future<http.Response> put(
    String url, {
    String? token,
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    return _client
        .put(
          Uri.parse(url),
          headers: _buildHeaders(token: token, extraHeaders: headers),
          body: body,
          encoding: encoding,
        )
        .timeout(timeout ?? defaultTimeout);
  }

  Future<http.Response> delete(
    String url, {
    String? token,
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    return _client
        .delete(
          Uri.parse(url),
          headers: _buildHeaders(token: token, extraHeaders: headers),
          body: body,
          encoding: encoding,
        )
        .timeout(timeout ?? defaultTimeout);
  }

  /// Invalidate a cache entry by key or clear all cache
  void invalidateCache(String? key) {
    if (key != null) {
      _cacheService.remove(key);
    } else {
      _cacheService.clear();
    }
  }

  void close() {
    _client.close();
  }
}

/// Global API client instance - use this instead of direct http.get/post calls
final apiClient = ApiClient();
