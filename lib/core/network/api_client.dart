import 'package:dio/dio.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/constants/app_constants.dart';
import 'package:diu_ride/core/errors/failure.dart';
import 'package:diu_ride/core/storage/secure_storage_service.dart';
import 'package:diu_ride/core/network/api_endpoints.dart';

class ApiClient {
  final Dio dio;
  final SecureStorageService secureStorage;

  ApiClient({Dio? dio, required this.secureStorage})
      : dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.current.apiBaseUrl,
                connectTimeout: AppConstants.connectTimeout,
                receiveTimeout: AppConstants.receiveTimeout,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    _setupInterceptors();
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await secureStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            final refreshToken = await secureStorage.getRefreshToken();
            if (refreshToken != null) {
              try {
                // Attempt token refresh
                final refreshResponse = await Dio().post(
                  '${AppConfig.current.apiBaseUrl}${ApiEndpoints.refreshToken}',
                  data: {'refreshToken': refreshToken},
                );
                final newAccessToken = refreshResponse.data['accessToken'] as String?;
                if (newAccessToken != null) {
                  await secureStorage.saveTokens(
                    accessToken: newAccessToken,
                    refreshToken: refreshToken,
                  );
                  error.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                  final retryResponse = await dio.fetch(error.requestOptions);
                  return handler.resolve(retryResponse);
                }
              } catch (_) {
                await secureStorage.clearTokens();
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Failure handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return const NetworkFailure('Connection timed out. Please check your network.');
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final data = error.response?.data;
          String message = 'Server error occurred ($statusCode)';
          if (data is Map && data['message'] != null) {
            message = data['message'].toString();
          }
          if (statusCode == 401) {
            return AuthFailure(message);
          } else if (statusCode == 409) {
            if (message.toLowerCase().contains('seat')) {
              return SeatUnavailableFailure(message);
            }
            return DuplicateBookingFailure(message);
          }
          return ServerFailure(message, statusCode);
        default:
          return NetworkFailure(error.message ?? 'Unknown network error');
      }
    }
    return Failure(error.toString());
  }
}
