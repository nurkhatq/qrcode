// lib/services/pdf_download_service.dart

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:logger/logger.dart';
import '../config/constants.dart';

/// Сервис для скачивания PDF файлов по URL
class PdfDownloadService {
  final Dio _dio;
  final Logger _logger = Logger();

  PdfDownloadService()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: Duration(seconds: AppConstants.downloadTimeout),
            receiveTimeout: Duration(seconds: AppConstants.downloadTimeout),
            validateStatus: (status) => status! < 500,
          ),
        );

  /// Скачивание PDF файла по URL
  /// Возвращает путь к скачанному файлу
  Future<String> downloadPdf(String url) async {
    try {
      _logger.i('Начало скачивания PDF: $url');

      // Проверка URL
      if (!_isValidUrl(url)) {
        throw Exception('Невалидный URL: $url');
      }

      // Получение временной директории
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'pdf_$timestamp.pdf';
      final filePath = path.join(tempDir.path, fileName);

      _logger.d('Путь для сохранения: $filePath');

      // Скачивание файла
      final response = await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(1);
            _logger.d('Прогресс скачивания: $progress%');
          }
        },
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

      // Проверка статуса ответа
      if (response.statusCode != 200) {
        throw Exception('Ошибка HTTP: ${response.statusCode}');
      }

      // Проверка размера файла
      final file = File(filePath);
      final fileSize = await file.length();
      
      _logger.i('Файл скачан. Размер: ${_formatBytes(fileSize)}');

      if (fileSize == 0) {
        await file.delete();
        throw Exception('Скачанный файл пустой');
      }

      if (fileSize > AppConstants.maxPdfSize) {
        await file.delete();
        throw Exception('Файл слишком большой: ${_formatBytes(fileSize)}');
      }

      // Проверка, что это действительно PDF
      if (!await _isPdfFile(filePath)) {
        await file.delete();
        throw Exception('Скачанный файл не является PDF');
      }

      return filePath;
    } on DioException catch (e) {
      _logger.e('Ошибка Dio при скачивании: ${e.message}');
      throw Exception(_getDioErrorMessage(e));
    } catch (e, stackTrace) {
      _logger.e('Ошибка скачивания PDF: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Проверка валидности URL
  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// Проверка, что файл является PDF
  Future<bool> _isPdfFile(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.openRead(0, 5).first;
      
      // Проверка сигнатуры PDF файла (%PDF-)
      return bytes.length >= 5 &&
          bytes[0] == 0x25 && // %
          bytes[1] == 0x50 && // P
          bytes[2] == 0x44 && // D
          bytes[3] == 0x46 && // F
          bytes[4] == 0x2D;   // -
    } catch (e) {
      _logger.w('Ошибка проверки PDF файла: $e');
      return false;
    }
  }

  /// Форматирование размера в читаемый вид
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Получение понятного сообщения об ошибке Dio
  String _getDioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Превышено время ожидания подключения';
      case DioExceptionType.receiveTimeout:
        return 'Превышено время ожидания получения данных';
      case DioExceptionType.sendTimeout:
        return 'Превышено время ожидания отправки данных';
      case DioExceptionType.badResponse:
        return 'Ошибка сервера: ${e.response?.statusCode}';
      case DioExceptionType.cancel:
        return 'Запрос был отменен';
      case DioExceptionType.connectionError:
        return 'Ошибка подключения к серверу';
      case DioExceptionType.badCertificate:
        return 'Ошибка сертификата безопасности';
      case DioExceptionType.unknown:
        return 'Неизвестная ошибка: ${e.message}';
    }
  }

  /// Удаление временного файла
  Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        _logger.d('Файл удален: $filePath');
      }
    } catch (e) {
      _logger.w('Ошибка удаления файла: $e');
    }
  }

  /// Очистка всех временных PDF файлов
  Future<int> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      int deletedCount = 0;

      for (var file in files) {
        if (file is File && file.path.endsWith('.pdf')) {
          try {
            await file.delete();
            deletedCount++;
          } catch (e) {
            _logger.w('Не удалось удалить файл: ${file.path}');
          }
        }
      }

      _logger.i('Удалено временных файлов: $deletedCount');
      return deletedCount;
    } catch (e) {
      _logger.e('Ошибка очистки временных файлов: $e');
      return 0;
    }
  }

  /// Получение размера файла по URL без полного скачивания
  Future<int?> getFileSize(String url) async {
    try {
      final response = await _dio.head(url);
      final contentLength = response.headers.value('content-length');
      
      if (contentLength != null) {
        return int.tryParse(contentLength);
      }
      
      return null;
    } catch (e) {
      _logger.w('Не удалось получить размер файла: $e');
      return null;
    }
  }

  /// Проверка доступности URL
  Future<bool> isUrlAccessible(String url) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(
          validateStatus: (status) => status! < 500,
        ),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      _logger.w('URL недоступен: $url');
      return false;
    }
  }
}