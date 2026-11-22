import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// Allows the browser to send and persist the HttpOnly session cookies.
void enableBrowserCredentials(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
}
