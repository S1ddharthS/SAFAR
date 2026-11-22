import 'package:dio/dio.dart';

/// Native builds rely on [CookieManager]; browsers attach cookies themselves.
void enableBrowserCredentials(Dio dio) {}
