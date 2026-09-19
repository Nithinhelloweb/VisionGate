import 'dart:convert';
import 'package:http/http.dart' as http;

/// Cache entry with timestamp for expiry tracking
class CacheEntry {
  final String data;
  final DateTime timestamp;

  CacheEntry(this.data, this.timestamp);

  bool isValid(Duration maxAge) {
    return DateTime.now().difference(timestamp) < maxAge;
  }
}

/// Response class that indicates if data came from cache
class CachedResponse {
  final Map<String, dynamic> data;
  final bool isFromCache;
  final int statusCode;

  CachedResponse({
    required this.data,
    required this.isFromCache,
    required this.statusCode,
  });
}

/// Simple in-memory cache service for API responses
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final Map<String, CacheEntry> _cache = {};

  /// Default cache duration - 10 minutes for slow networks
  static const Duration defaultCacheDuration = Duration(minutes: 10);

  /// Get cached data if available and not expired
  String? get(String key, {Duration? maxAge}) {
    final entry = _cache[key];
    if (entry == null) return null;

    final duration = maxAge ?? defaultCacheDuration;
    if (entry.isValid(duration)) {
      return entry.data;
    }

    // Remove expired entry
    _cache.remove(key);
    return null;
  }

  /// Store data in cache
  void set(String key, String data) {
    _cache[key] = CacheEntry(data, DateTime.now());
  }

  /// Remove specific cache entry
  void remove(String key) {
    _cache.remove(key);
  }

  /// Clear all cache
  void clear() {
    _cache.clear();
  }

  /// Check if cache exists and is valid
  bool hasValidCache(String key, {Duration? maxAge}) {
    final entry = _cache[key];
    if (entry == null) return false;

    final duration = maxAge ?? defaultCacheDuration;
    return entry.isValid(duration);
  }
}

/// Helper class to make cached HTTP requests with load-first strategy for slow networks
class CachedHttpClient {
  final CacheService _cacheService = CacheService();
  final http.Client _client = http.Client();

  /// Make a GET request with caching - shows cached data immediately if available
  /// This is the PREFERRED method for slow networks as it loads instantly from cache
  ///
  /// Returns a CachedResponse that contains both cached and fresh data
  Future<CachedResponse> getWithCache(
    String url, {
    String? token,
    String? cacheKey,
    Duration? cacheDuration,
    bool forceRefresh = false,
  }) async {
    final key = cacheKey ?? url;
    final duration = cacheDuration ?? CacheService.defaultCacheDuration;

    // Check if we have valid cached data
    final cachedData = _cacheService.get(key, maxAge: duration);
    final hasValidCache = cachedData != null;

    // If force refresh or no cache, fetch fresh data
    if (forceRefresh || !hasValidCache) {
      try {
        final freshResponse = await _makeRequest(url, token: token);
        if (freshResponse.statusCode == 200) {
          _cacheService.set(key, freshResponse.body);
        }
        return CachedResponse(
          data: jsonDecode(freshResponse.body),
          isFromCache: false,
          statusCode: freshResponse.statusCode,
        );
      } catch (e) {
        // On error, return cached data if available
        if (cachedData != null) {
          return CachedResponse(
            data: jsonDecode(cachedData),
            isFromCache: true,
            statusCode: 200,
          );
        }
        rethrow;
      }
    }

    // We have valid cache - return it immediately (for fast load on slow networks)
    // Also fetch fresh data in background if cache is getting old
    if (!_cacheService.hasValidCache(
      key,
      maxAge: Duration(minutes: duration.inMinutes ~/ 2),
    )) {
      // Cache exists but is older than half the duration - refresh in background
      _makeRequest(url, token: token)
          .then((response) {
            if (response.statusCode == 200) {
              _cacheService.set(key, response.body);
            }
          })
          .catchError((_) {}); // Ignore errors for background refresh
    }

    return CachedResponse(
      data: jsonDecode(cachedData),
      isFromCache: true,
      statusCode: 200,
    );
  }

  Future<http.Response> _makeRequest(String url, {String? token}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return _client.get(Uri.parse(url), headers: headers);
  }

  /// Make a GET request with simple caching (for backwards compatibility)
  Future<http.Response> get(
    String url, {
    String? token,
    String? cacheKey,
    Duration? cacheDuration,
    bool forceRefresh = false,
  }) async {
    final result = await getWithCache(
      url,
      token: token,
      cacheKey: cacheKey,
      cacheDuration: cacheDuration,
      forceRefresh: forceRefresh,
    );
    return http.Response(
      jsonEncode(result.data),
      result.statusCode,
      headers: {'X-Cache': result.isFromCache ? 'HIT' : 'MISS'},
    );
  }

  /// Clear cache for specific key
  void clearCache(String key) {
    _cacheService.remove(key);
  }

  /// Clear all cached data
  void clearAllCache() {
    _cacheService.clear();
  }

  /// Check if cached data exists
  bool hasCache(String key) {
    return _cacheService.hasValidCache(key);
  }
}

// Default cached client instance for easy import
final cachedHttpClient = CachedHttpClient();
