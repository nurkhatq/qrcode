// lib/services/google_sheets_service.dart

import 'package:gsheets/gsheets.dart';
import 'package:logger/logger.dart';
import '../config/constants.dart';
import '../models/scanned_record.dart';

/// Сервис для работы с Google Sheets API
class GoogleSheetsService {
  final Logger _logger = Logger();
  GSheets? _gsheets;
  Spreadsheet? _spreadsheet;
  Worksheet? _worksheet;
  bool _isInitialized = false;

  /// Инициализация подключения к Google Sheets
  Future<void> initialize() async {
    if (_isInitialized) {
      _logger.d('Google Sheets уже инициализирован');
      return;
    }

    try {
      _logger.i('Инициализация Google Sheets...');

      // Создание клиента GSheets
      _gsheets = GSheets(AppConstants.googleCredentials);

      // Получение таблицы
      _spreadsheet = await _gsheets!.spreadsheet(AppConstants.spreadsheetId);
      
      _logger.d('Таблица найдена: ${_spreadsheet!.data.properties.title}');

      // Получение или создание листа
      _worksheet = _spreadsheet!.worksheetByTitle(AppConstants.worksheetName);
      
      if (_worksheet == null) {
        _logger.i('Лист "${AppConstants.worksheetName}" не найден. Создаем...');
        _worksheet = await _spreadsheet!.addWorksheet(AppConstants.worksheetName);
      }

      // Инициализация заголовков, если лист пустой
      await _initializeHeaders();

      _isInitialized = true;
      _logger.i('Google Sheets успешно инициализирован');
    } catch (e, stackTrace) {
      _logger.e('Ошибка инициализации Google Sheets: $e', 
          error: e, stackTrace: stackTrace);
      _isInitialized = false;
      rethrow;
    }
  }

  /// Инициализация заголовков таблицы
  Future<void> _initializeHeaders() async {
    try {
      // Проверяем, есть ли уже заголовки
      final firstRow = await _worksheet!.values.row(1);
      
      if (firstRow.isEmpty || firstRow.every((cell) => cell.isEmpty)) {
        _logger.i('Создание заголовков таблицы...');
        
        // Устанавливаем заголовки
        await _worksheet!.values.insertRow(1, AppConstants.sheetHeaders);
        
        // Форматирование заголовков (жирный шрифт) - опционально
        _logger.d('Заголовки установлены');
      } else {
        _logger.d('Заголовки уже существуют');
      }
    } catch (e) {
      _logger.w('Ошибка при инициализации заголовков: $e');
    }
  }

  /// Отправка записей в Google Sheets
  Future<int> uploadRecords(List<ScannedRecord> records) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (records.isEmpty) {
      _logger.w('Нет записей для отправки');
      return 0;
    }

    try {
      _logger.i('Начало отправки ${records.length} записей в Google Sheets');

      // Проверка на дубликаты
      final uniqueRecords = await _filterDuplicates(records);
      
      if (uniqueRecords.isEmpty) {
        _logger.i('Все записи уже существуют в таблице');
        return 0;
      }

      _logger.i('Записей после фильтрации дубликатов: ${uniqueRecords.length}');

      // Подготовка данных для вставки
      final rows = uniqueRecords.map((record) => record.toSheetRow()).toList();

      // Вставка данных
      final success = await _worksheet!.values.appendRows(rows);

      if (success) {
        _logger.i('Успешно добавлено записей: ${uniqueRecords.length}');
        return uniqueRecords.length;
      } else {
        throw Exception('Не удалось добавить записи в таблицу');
      }
    } catch (e, stackTrace) {
      _logger.e('Ошибка отправки в Google Sheets: $e',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Фильтрация дубликатов
  Future<List<ScannedRecord>> _filterDuplicates(
      List<ScannedRecord> records) async {
    try {
      // Получаем все существующие записи из таблицы
      final existingData = await _worksheet!.values.allRows();
      
      if (existingData.isEmpty || existingData.length <= 1) {
        // Только заголовки или пустая таблица
        return records;
      }

      // Создаем Set существующих пар (номер_места, номер_заказа)
      final existingPairs = <String>{};
      
      for (var i = 1; i < existingData.length; i++) {
        final row = existingData[i];
        if (row.length >= 7) {
          // Индексы: 4 - номер места, 6 - номер заказа
          final placeNumber = row[4].toString().trim();
          final orderCode = row[6].toString().trim();
          existingPairs.add('$placeNumber:$orderCode');
        }
      }

      _logger.d('Найдено существующих записей: ${existingPairs.length}');

      // Фильтруем новые записи
      final uniqueRecords = records.where((record) {
        final key = '${record.placeNumber}:${record.orderCode}';
        return !existingPairs.contains(key);
      }).toList();

      final duplicatesCount = records.length - uniqueRecords.length;
      if (duplicatesCount > 0) {
        _logger.i('Обнаружено дубликатов: $duplicatesCount');
      }

      return uniqueRecords;
    } catch (e) {
      _logger.w('Ошибка при проверке дубликатов: $e. Отправляем все записи.');
      return records;
    }
  }

  /// Получение всех записей из таблицы
  Future<List<Map<String, String>>> getAllRecords() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.i('Получение всех записей из Google Sheets');

      final data = await _worksheet!.values.map.allRows();
      
      _logger.i('Получено записей: ${data?.length ?? 0}');
      
      return data ?? [];
    } catch (e, stackTrace) {
      _logger.e('Ошибка получения данных из Google Sheets: $e',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Проверка существования записи в таблице
  Future<bool> recordExists(String placeNumber, String orderCode) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final existingData = await _worksheet!.values.allRows();
      
      for (var i = 1; i < existingData.length; i++) {
        final row = existingData[i];
        if (row.length >= 7) {
          final existingPlace = row[4].toString().trim();
          final existingOrder = row[6].toString().trim();
          
          if (existingPlace == placeNumber && existingOrder == orderCode) {
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      _logger.w('Ошибка проверки существования записи: $e');
      return false;
    }
  }

  /// Получение количества записей в таблице
  Future<int> getRecordCount() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final allRows = await _worksheet!.values.allRows();
      // Вычитаем заголовок
      return allRows.isNotEmpty ? allRows.length - 1 : 0;
    } catch (e) {
      _logger.w('Ошибка получения количества записей: $e');
      return 0;
    }
  }

  /// Очистка всех данных (кроме заголовков)
  Future<void> clearAllData() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.i('Очистка всех данных из таблицы');

      final allRows = await _worksheet!.values.allRows();
      final rowCount = allRows.length;

      if (rowCount > 1) {
        // Удаляем все строки кроме заголовка
        // Используем clear для очистки диапазона, начиная со второй строки
        await _worksheet!.deleteRow(2, count: rowCount - 1);
        _logger.i('Данные очищены');
      } else {
        _logger.d('Таблица уже пуста');
      }
    } catch (e, stackTrace) {
      _logger.e('Ошибка очистки данных: $e',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Тестирование подключения
  Future<bool> testConnection() async {
    try {
      _logger.i('Тестирование подключения к Google Sheets');
      
      await initialize();
      
      // Пробуем получить информацию о таблице
      final title = _spreadsheet!.data.properties.title;
      _logger.i('Подключение успешно. Таблица: $title');
      
      return true;
    } catch (e) {
      _logger.e('Ошибка подключения к Google Sheets: $e');
      return false;
    }
  }

  /// Получение информации о таблице
  Future<Map<String, dynamic>> getSpreadsheetInfo() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final properties = _spreadsheet!.data.properties;
      final recordCount = await getRecordCount();
      
      return {
        'title': properties.title,
        'id': _spreadsheet!.id,
        'worksheetTitle': _worksheet!.title,
        'recordCount': recordCount,
      };
    } catch (e) {
      _logger.e('Ошибка получения информации о таблице: $e');
      return {};
    }
  }

  /// Сброс состояния (для переинициализации)
  void reset() {
    _isInitialized = false;
    _worksheet = null;
    _spreadsheet = null;
    _gsheets = null;
    _logger.i('Google Sheets сброшен');
  }
}