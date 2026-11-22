import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.detail,
    this.isNetwork = false,
    this.isTimeout = false,
  });

  final String message;
  final int? statusCode;
  final dynamic detail;
  final bool isNetwork;
  final bool isTimeout;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  factory ApiException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    final detail = error.response?.data is Map
        ? (error.response!.data as Map)['detail'] ?? error.response!.data
        : error.response?.data;
    final message = _messageFor(detail) ?? _fallback(error, status);
    final type = error.type;
    return ApiException(
      message: message,
      statusCode: status,
      detail: detail,
      isNetwork:
          type == DioExceptionType.connectionError ||
          type == DioExceptionType.badCertificate,
      isTimeout:
          type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.sendTimeout ||
          type == DioExceptionType.receiveTimeout,
    );
  }

  static String? _messageFor(dynamic detail) {
    if (detail == null) return null;
    if (detail is String) return detail;
    if (detail is List) {
      final parts = detail
          .map((item) {
            if (item is Map && item['msg'] != null) return '${item['msg']}';
            return '$item';
          })
          .where((part) => part.trim().isNotEmpty)
          .toList();
      if (parts.isNotEmpty) return parts.join(' · ');
      return null;
    }
    if (detail is Map) {
      final message = detail['message'] ?? detail['detail'];
      if (message != null) return '$message';
    }
    return null;
  }

  static String _fallback(DioException error, int? status) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond. Check your connection and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach SAFAR. Check the API address and your network.';
      case DioExceptionType.badCertificate:
        return 'The secure connection could not be verified.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      default:
        if (status == 401) return 'Your session has expired. Sign in again.';
        if (status == 403) return 'You do not have access to this action.';
        if (status == 404) return 'This item could not be found.';
        if (status == 409) return 'That conflicts with the current plan.';
        if (status == 422) return 'Please check the information you entered.';
        if (status != null && status >= 500) {
          return 'SAFAR had a problem completing that request.';
        }
        return 'The request could not be completed.';
    }
  }

  @override
  String toString() => message;
}
