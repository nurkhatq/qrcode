// lib/services/pdf_parser_service.dart

import 'dart:io';
import 'package:logger/logger.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/scanned_record.dart';

/// Сервис для парсинга PDF документов и извлечения данных
class PdfParserService {
  final Logger _logger = Logger();

  /// Парсинг PDF файла и извлечение записей
  Future<List<ScannedRecord>> parsePdf(
    String pdfPath,
    String source,
  ) async {
    try {
      _logger.i('Начало парсинга PDF: $pdfPath');

      // Загрузка PDF документа
      final File file = File(pdfPath);
      final bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      // Извлечение текста из всех страниц
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String fullText = extractor.extractText();

      _logger.d('Извлечен текст длиной: ${fullText.length} символов');

      // Парсинг текста
      final records = _parseText(fullText, source);

      // Закрытие документа
      document.dispose();

      _logger.i('Парсинг завершен. Найдено записей: ${records.length}');
      return records;
    } catch (e, stackTrace) {
      _logger.e('Ошибка парсинга PDF: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Парсинг извлеченного текста
  List<ScannedRecord> _parseText(String text, String source) {
    final List<ScannedRecord> records = [];

    try {
      // Очистка текста от лишних пробелов и переносов
      final cleanedText = _cleanText(text);
      
      _logger.d('Очищенный текст:\n$cleanedText');

      // Извлечение даты приема-передачи
      final transferDate = _extractTransferDate(cleanedText);
      if (transferDate == null) {
        throw Exception('Не удалось извлечь дату приема-передачи');
      }

      _logger.d('Дата приема-передачи: $transferDate');

      // Извлечение таблицы с данными
      final tableRecords = _extractTableRecords(cleanedText, source, transferDate);
      records.addAll(tableRecords);

      return records;
    } catch (e, stackTrace) {
      _logger.e('Ошибка парсинга текста: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Очистка текста от служебных символов
  String _cleanText(String text) {
    // Удаление мягких переносов (Unicode soft hyphen)
    text = text.replaceAll('\u00AD', '');
    text = text.replaceAll('\u200B', ''); // Zero-width space
    
    // Нормализация пробелов
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    
    // Удаление лишних переносов строк
    text = text.replaceAll(RegExp(r'\n\s*\n'), '\n');
    
    return text.trim();
  }

  /// Извлечение даты приема-передачи из текста
  DateTime? _extractTransferDate(String text) {
    // Паттерн для даты: "11.11.2025 17:17:30" или "11.11.2025"
    final datePattern = RegExp(
      r'(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{1,2}):(\d{1,2}))?',
    );

    final match = datePattern.firstMatch(text);
    if (match == null) return null;

    try {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      
      int hour = 0, minute = 0, second = 0;
      
      if (match.group(4) != null) {
        hour = int.parse(match.group(4)!);
        minute = int.parse(match.group(5)!);
        second = int.parse(match.group(6)!);
      }

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      _logger.w('Ошибка парсинга даты: $e');
      return null;
    }
  }

  /// Извлечение записей из таблицы
  List<ScannedRecord> _extractTableRecords(
    String text,
    String source,
    DateTime transferDate,
  ) {
    final List<ScannedRecord> records = [];

    // Паттерн для строки таблицы
    // Формат: [номер] [номер_места] [вес кг] [номер_заказа]
    // Пример: "1 ZMKZ0000001 5.2 кг WB123456789"
    
    // Более гибкий паттерн, который учитывает разные варианты форматирования
    final rowPattern = RegExp(
      r'(\d+)\s+([A-Z0-9]+)\s+([\d,\.]+)\s*(?:кг|kg)?\s+([A-Z0-9]+)',
      caseSensitive: false,
      multiLine: true,
    );

    final matches = rowPattern.allMatches(text);
    
    _logger.d('Найдено совпадений паттерна: ${matches.length}');

    for (var match in matches) {
      try {
        final orderNumber = int.parse(match.group(1)!);
        final placeNumber = _normalizeString(match.group(2)!);
        final weightStr = match.group(3)!.replaceAll(',', '.');
        final weight = double.parse(weightStr);
        final orderCode = _normalizeString(match.group(4)!);

        // Проверка валидности данных
        if (placeNumber.isEmpty || orderCode.isEmpty || weight <= 0) {
          _logger.w('Пропуск невалидной записи: $orderNumber');
          continue;
        }

        final record = ScannedRecord(
          transferDate: transferDate,
          source: source,
          orderNumber: orderNumber,
          placeNumber: placeNumber,
          weight: weight,
          orderCode: orderCode,
        );

        records.add(record);
        _logger.d('Добавлена запись: $placeNumber - $orderCode');
      } catch (e) {
        _logger.w('Ошибка парсинга строки таблицы: $e');
        continue;
      }
    }

    // Если основной паттерн не сработал, пробуем альтернативный метод
    if (records.isEmpty) {
      _logger.i('Основной паттерн не нашел записей. Пробуем альтернативный метод...');
      records.addAll(_extractTableRecordsAlternative(text, source, transferDate));
    }

    return records;
  }

  /// Альтернативный метод извлечения записей (для плохо отформатированных PDF)
  List<ScannedRecord> _extractTableRecordsAlternative(
    String text,
    String source,
    DateTime transferDate,
  ) {
    final List<ScannedRecord> records = [];

    try {
      // Разбиваем текст на строки
      final lines = text.split('\n');
      
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        // Ищем строки, которые содержат номер места (начинается с букв, содержит цифры)
        final placePattern = RegExp(r'([A-Z]{2,}[0-9]+)', caseSensitive: false);
        final placeMatch = placePattern.firstMatch(line);
        
        if (placeMatch == null) continue;

        final placeNumber = _normalizeString(placeMatch.group(1)!);

        // Ищем вес в этой строке
        final weightPattern = RegExp(r'([\d,\.]+)\s*(?:кг|kg)?', caseSensitive: false);
        final weightMatch = weightPattern.firstMatch(line);
        
        if (weightMatch == null) continue;

        final weightStr = weightMatch.group(1)!.replaceAll(',', '.');
        final weight = double.tryParse(weightStr);
        
        if (weight == null || weight <= 0) continue;

        // Ищем номер заказа (обычно начинается с WB или других букв)
        final orderPattern = RegExp(r'([A-Z]{2}[0-9]+)', caseSensitive: false);
        final orderMatches = orderPattern.allMatches(line);
        
        String? orderCode;
        for (var match in orderMatches) {
          final code = match.group(1)!;
          if (code != placeNumber) {
            orderCode = _normalizeString(code);
            break;
          }
        }

        if (orderCode == null || orderCode.isEmpty) continue;

        // Пытаемся найти номер по порядку (обычно в начале строки)
        final numberPattern = RegExp(r'^(\d+)');
        final numberMatch = numberPattern.firstMatch(line);
        final orderNumber = numberMatch != null 
            ? int.tryParse(numberMatch.group(1)!) ?? records.length + 1
            : records.length + 1;

        final record = ScannedRecord(
          transferDate: transferDate,
          source: source,
          orderNumber: orderNumber,
          placeNumber: placeNumber,
          weight: weight,
          orderCode: orderCode,
        );

        records.add(record);
        _logger.d('Альтернативный метод: добавлена запись $placeNumber - $orderCode');
      }
    } catch (e) {
      _logger.w('Ошибка в альтернативном методе парсинга: $e');
    }

    return records;
  }

  /// Нормализация строки (удаление пробелов между символами)
  String _normalizeString(String str) {
    // Удаление всех пробелов
    str = str.replaceAll(RegExp(r'\s+'), '');
    // Приведение к верхнему регистру
    return str.toUpperCase();
  }

  /// Валидация PDF файла
  Future<bool> validatePdf(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        _logger.w('PDF файл не существует: $pdfPath');
        return false;
      }

      final bytes = await file.readAsBytes();
      
      // Проверка сигнатуры PDF файла
      if (bytes.length < 5 || 
          bytes[0] != 0x25 || bytes[1] != 0x50 || 
          bytes[2] != 0x44 || bytes[3] != 0x46) {
        _logger.w('Файл не является валидным PDF');
        return false;
      }

      // Пытаемся открыть документ
      final document = PdfDocument(inputBytes: bytes);
      document.dispose();

      return true;
    } catch (e) {
      _logger.e('Ошибка валидации PDF: $e');
      return false;
    }
  }
}