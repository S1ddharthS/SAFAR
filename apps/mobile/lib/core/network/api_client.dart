import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';

import '../services/diagnostics_service.dart';
import '../storage/json_store.dart';
import 'api_exception.dart';
import 'browser_credentials_stub.dart'
    if (dart.library.js_interop) 'browser_credentials_web.dart';
import 'cookie_jar.dart';

const _unsafeMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required SafarCookieJar jar,
    required JsonStore store,
    this.onUnauthorized,
  }) : _jar = jar,
       _store = store {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
      ),
    );
    if (!kIsWeb) {
      // Native clients need a persistent jar so the HttpOnly refresh cookie
      // survives restarts. Browsers own cookies for the web verification build.
      dio.interceptors.add(CookieManager(_jar));
    } else {
      enableBrowserCredentials(dio);
    }
    dio.interceptors.add(_TelemetryInterceptor());
    dio.interceptors.add(_AuthInterceptor(this));
  }

  final String baseUrl;
  final SafarCookieJar _jar;
  // ignore: unused_field
  final JsonStore _store;
  late final Dio dio;

  String? accessToken;
  String? csrfToken;
  void Function()? onUnauthorized;

  Future<bool>? _refreshInFlight;

  bool get hasSession => accessToken != null;

  Future<bool> refreshSession() {
    return _refreshInFlight ??= _refresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _refresh() async {
    try {
      final response = await dio.post<dynamic>(
        '/api/auth/refresh',
        options: Options(extra: const {'skipAuth': true}),
      );
      final data = response.data;
      if (data is! Map) return false;
      final access = data['access_token'];
      final csrf = data['csrf_token'];
      if (access is! String || access.isEmpty) return false;
      accessToken = access;
      csrfToken = csrf is String ? csrf : null;
      return true;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        await clearSession();
        return false;
      }
      rethrow;
    }
  }

  Future<void> clearSession() async {
    accessToken = null;
    csrfToken = null;
    await _jar.deleteAll();
  }

  void notifyUnauthorized() {
    onUnauthorized?.call();
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool raw = false,
  }) => _request('GET', path, query: query, raw: raw);

  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    bool raw = false,
  }) => _request('POST', path, data: data, query: query, raw: raw);

  Future<dynamic> put(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) => _request('PUT', path, data: data, query: query);

  Future<dynamic> patch(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) => _request('PATCH', path, data: data, query: query);

  Future<dynamic> delete(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) => _request('DELETE', path, data: data, query: query);

  /// Uploads one file as multipart form data under the `file` field.
  Future<Map<String, dynamic>> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    try {
      final response = await dio.post<dynamic>(
        path,
        data: form,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      final data = response.data;
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    bool raw = false,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      );
      if (raw) return response.data;
      return response.data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Absolute URL for seeded imagery and locally issued media paths.
  String mediaUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final value = raw.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return value.startsWith('/') ? '$baseUrl$value' : '$baseUrl/$value';
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this.client);

  final ApiClient client;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['skipAuth'] != true) {
      final token = client.accessToken;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      final csrf = client.csrfToken;
      if (_unsafeMethods.contains(options.method.toUpperCase()) &&
          csrf != null &&
          csrf.isNotEmpty) {
        options.headers['X-CSRF-Token'] = csrf;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final status = err.response?.statusCode;
    final isAuthPath = options.path.startsWith('/api/auth/');
    final retried = options.extra['retried'] == true;
    if (status == 401 && !retried && !isAuthPath) {
      try {
        final refreshed = await client.refreshSession();
        if (refreshed) {
          final headers = Map<String, dynamic>.from(options.headers);
          final token = client.accessToken;
          if (token != null) headers['Authorization'] = 'Bearer $token';
          final csrf = client.csrfToken;
          if (_unsafeMethods.contains(options.method.toUpperCase()) &&
              csrf != null) {
            headers['X-CSRF-Token'] = csrf;
          }
          final retryOptions = options.copyWith(
            headers: headers,
            extra: {...options.extra, 'retried': true},
          );
          final response = await client.dio.fetch<dynamic>(retryOptions);
          return handler.resolve(response);
        }
        client.notifyUnauthorized();
      } on Object {
        // A network failure while refreshing must not sign the user out.
      }
    }
    handler.next(err);
  }
}

class _TelemetryInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['__startTime'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start = response.requestOptions.extra['__startTime'] as int?;
    final durationMs = start != null ? DateTime.now().millisecondsSinceEpoch - start : 0;
    DiagnosticsService.instance.recordNetwork(
      response.requestOptions.path,
      response.requestOptions.method,
      response.statusCode,
      durationMs,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final start = err.requestOptions.extra['__startTime'] as int?;
    final durationMs = start != null ? DateTime.now().millisecondsSinceEpoch - start : 0;
    DiagnosticsService.instance.recordNetwork(
      err.requestOptions.path,
      err.requestOptions.method,
      err.response?.statusCode,
      durationMs,
      error: err.message,
    );
    if (err.response?.statusCode == 401) {
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.auth,
        level: SafarDiagnosticLevel.warning,
        message: 'Authentication failure (401) on ${err.requestOptions.path}',
      );
    }
    handler.next(err);
  }
}
