// lib/providers/app_provider.dart

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../models/scanned_record.dart';
import '../services/database_service.dart';
import '../services/pdf_download_service.dart';
import '../services/pdf_parser_service.dart';
import '../services/google_sheets_service.dart';

/// Главный Provider приложения для управления состоянием
class AppProvider with ChangeNotifier {
  final Logger _logger = Logger();
  
  // Сервисы
  final DatabaseService _dbService = DatabaseService();
  final PdfDownloadService _downloadService = PdfDownloadService();
  final PdfParserService _parserService = PdfParserService();
  final GoogleSheetsService _sheetsService = GoogleSheetsService();

  // Состояние
  List<ScannedRecord> _records = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _errorMessage;
  String? _successMessage;
  Map<String, int> _statistics = {'total': 0, 'synced': 0, 'unsynced': 0};

  // Getters
  List<ScannedRecord> get records => _records;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  Map<String, int> get statistics => _statistics;
  
  int get totalRecords => _statistics['total'] ?? 0;
  int get syncedRecords => _statistics['synced'] ?? 0;
  int get unsyncedRecords => _statistics['unsynced'] ?? 0;

  /// Инициализация приложения
  Future<void> initialize() async {
    try {
      _logger.i('Инициализация приложения');
      
      // Загрузка записей из базы
      await loadRecords();
      
      // Обновление статистики
      await updateStatistics();
      
      _logger.i('Приложение инициализировано');
    } catch (e) {
      _logger.e('Ошибка инициализации: $e');
      _setError('Ошибка инициализации: $e');
    }
  }

  /// Загрузка всех записей из базы данных
  Future<void> loadRecords() async {
    try {
      _logger.i('Загрузка записей из БД');
      _records = await _dbService.getAllRecords();
      _logger.i('Загружено записей: ${_records.length}');
      notifyListeners();
    } catch (e) {
      _logger.e('Ошибка загрузки записей: $e');
      _setError('Ошибка загрузки записей: $e');
    }
  }

  /// Обработка отсканированного QR кода
  Future<void> processQrCode(String qrData) async {
    if (_isLoading) {
      _logger.w('Уже идет обработка QR кода');
      return;
    }

    _setLoading(true);
    _clearMessages();

    try {
      _logger.i('Обработка QR кода: $qrData');

      // Проверка, что это URL
      if (!_isValidUrl(qrData)) {
        throw Exception('QR код не содержит валидный URL');
      }

      // Шаг 1: Скачивание PDF
      _logger.d('Скачивание PDF...');
      final pdfPath = await _downloadService.downloadPdf(qrData);

      // Шаг 2: Парсинг PDF
      _logger.d('Парсинг PDF...');
      final newRecords = await _parserService.parsePdf(pdfPath, qrData);

      if (newRecords.isEmpty) {
        throw Exception('Не удалось извлечь данные из PDF');
      }

      // Шаг 3: Фильтрация дубликатов
      final uniqueRecords = <ScannedRecord>[];
      for (var record in newRecords) {
        final exists = await _dbService.recordExists(
          record.placeNumber,
          record.orderCode,
        );
        if (!exists) {
          uniqueRecords.add(record);
        }
      }

      if (uniqueRecords.isEmpty) {
        _setSuccess('Все записи из этого документа уже добавлены');
      } else {
        // Шаг 4: Сохранение в БД
        await _dbService.insertRecords(uniqueRecords);
        _setSuccess('Добавлено новых записей: ${uniqueRecords.length}');
        
        // Обновление списка
        await loadRecords();
        await updateStatistics();
      }

      // Очистка временного файла
      await _downloadService.deleteFile(pdfPath);

      _logger.i('QR код успешно обработан');
    } catch (e, stackTrace) {
      _logger.e('Ошибка обработки QR кода: $e', error: e, stackTrace: stackTrace);
      _setError(_getErrorMessage(e));
    } finally {
      _setLoading(false);
    }
  }

  /// Синхронизация с Google Sheets
  Future<void> syncWithGoogleSheets() async {
    if (_isSyncing) {
      _logger.w('Синхронизация уже идет');
      return;
    }

    _isSyncing = true;
    _clearMessages();
    notifyListeners();

    try {
      _logger.i('Начало синхронизации с Google Sheets');

      // Получение несинхронизированных записей
      final unsyncedRecords = await _dbService.getUnsyncedRecords();

      if (unsyncedRecords.isEmpty) {
        _setSuccess('Нет записей для синхронизации');
        return;
      }

      _logger.i('Записей для синхронизации: ${unsyncedRecords.length}');

      // Отправка в Google Sheets
      final uploadedCount = await _sheetsService.uploadRecords(unsyncedRecords);

      if (uploadedCount > 0) {
        // Пометка записей как синхронизированных
        final ids = unsyncedRecords.take(uploadedCount).map((r) => r.id).toList();
        await _dbService.markMultipleAsSynced(ids);

        _setSuccess('Синхронизировано записей: $uploadedCount');
        
        // Обновление данных
        await loadRecords();
        await updateStatistics();
      } else {
        _setSuccess('Все записи уже существуют в Google Sheets');
      }

      _logger.i('Синхронизация завершена');
    } catch (e, stackTrace) {
      _logger.e('Ошибка синхронизации: $e', error: e, stackTrace: stackTrace);
      _setError('Ошибка синхронизации: ${_getErrorMessage(e)}');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Удаление записи
  Future<void> deleteRecord(String recordId) async {
    try {
      _logger.i('Удаление записи: $recordId');
      
      await _dbService.deleteRecord(recordId);
      await loadRecords();
      await updateStatistics();
      
      _setSuccess('Запись удалена');
    } catch (e) {
      _logger.e('Ошибка удаления записи: $e');
      _setError('Ошибка удаления: $e');
    }
  }

  /// Удаление всех синхронизированных записей
  Future<void> deleteSyncedRecords() async {
    try {
      _logger.i('Удаление синхронизированных записей');
      
      final count = await _dbService.deleteSyncedRecords();
      await loadRecords();
      await updateStatistics();
      
      _setSuccess('Удалено записей: $count');
    } catch (e) {
      _logger.e('Ошибка удаления записей: $e');
      _setError('Ошибка удаления: $e');
    }
  }

  /// Удаление всех записей
  Future<void> deleteAllRecords() async {
    try {
      _logger.i('Удаление всех записей');
      
      final count = await _dbService.deleteAllRecords();
      await loadRecords();
      await updateStatistics();
      
      _setSuccess('Удалено всех записей: $count');
    } catch (e) {
      _logger.e('Ошибка удаления всех записей: $e');
      _setError('Ошибка удаления: $e');
    }
  }

  /// Обновление статистики
  Future<void> updateStatistics() async {
    try {
      _statistics = await _dbService.getStatistics();
      notifyListeners();
    } catch (e) {
      _logger.e('Ошибка обновления статистики: $e');
    }
  }

  /// Тестирование подключения к Google Sheets
  Future<bool> testGoogleSheetsConnection() async {
    try {
      _logger.i('Тестирование подключения к Google Sheets');
      return await _sheetsService.testConnection();
    } catch (e) {
      _logger.e('Ошибка тестирования подключения: $e');
      return false;
    }
  }

  /// Получение группированных записей по документам
  List<ScannedDocument> getGroupedRecords() {
    final Map<String, List<ScannedRecord>> grouped = {};

    for (var record in _records) {
      if (!grouped.containsKey(record.source)) {
        grouped[record.source] = [];
      }
      grouped[record.source]!.add(record);
    }

    return grouped.entries.map((entry) {
      final records = entry.value;
      return ScannedDocument(
        source: entry.key,
        transferDate: records.first.transferDate,
        records: records,
      );
    }).toList()
      ..sort((a, b) => b.transferDate.compareTo(a.transferDate));
  }

  // Вспомогательные методы

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _successMessage = null;
    notifyListeners();
  }

  void _setSuccess(String message) {
    _successMessage = message;
    _errorMessage = null;
    notifyListeners();
  }

  void _clearMessages() {
    _errorMessage = null;
    _successMessage = null;
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  String _getErrorMessage(dynamic error) {
    final message = error.toString();
    
    if (message.contains('SocketException') || message.contains('Connection')) {
      return 'Ошибка сети. Проверьте подключение к интернету';
    }
    
    if (message.contains('TimeoutException') || message.contains('timeout')) {
      return 'Превышено время ожидания. Попробуйте еще раз';
    }
    
    if (message.contains('FormatException')) {
      return 'Ошибка формата данных в PDF';
    }
    
    if (message.contains('не является валидным PDF') || message.contains('not a valid PDF')) {
      return 'Файл не является PDF документом';
    }
    
    return message.replaceFirst('Exception: ', '');
  }

  /// Очистка сообщений
  void clearMessages() {
    _clearMessages();
    notifyListeners();
  }

  @override
  void dispose() {
    _logger.i('AppProvider dispose');
    super.dispose();
  }
}