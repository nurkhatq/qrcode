// lib/services/pdf_parser_service.dart
// ВЕРСИЯ ДЛЯ ANDROID - Построчное извлечение данных

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
      _logger.i('========================================');
      _logger.i('НАЧАЛО ПАРСИНГА PDF');
      _logger.i('Путь к файлу: $pdfPath');
      _logger.i('Источник: $source');
      _logger.i('========================================');

      // Загрузка PDF документа
      final File file = File(pdfPath);
      
      if (!await file.exists()) {
        _logger.e('❌ ФАЙЛ НЕ СУЩЕСТВУЕТ: $pdfPath');
        throw Exception('PDF файл не найден: $pdfPath');
      }
      
      _logger.i('✓ Файл существует');
      
      final bytes = await file.readAsBytes();
      _logger.i('✓ Файл загружен, размер: ${bytes.length} байт');
      
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      _logger.i('✓ PDF документ открыт, количество страниц: ${document.pages.count}');

      // Извлечение текста из всех страниц
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String fullText = extractor.extractText();

      _logger.i('✓ Текст извлечён, длина: ${fullText.length} символов');

      // Парсинг текста
      final records = _parseText(fullText, source);

      // Закрытие документа
      document.dispose();

      _logger.i('========================================');
      _logger.i('ПАРСИНГ ЗАВЕРШЕН');
      _logger.i('Найдено записей: ${records.length}');
      _logger.i('========================================');
      
      return records;
    } catch (e, stackTrace) {
      _logger.e('❌ КРИТИЧЕСКАЯ ОШИБКА ПАРСИНГА PDF', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Парсинг извлеченного текста
  List<ScannedRecord> _parseText(String text, String source) {
    final List<ScannedRecord> records = [];

    try {
      // Очистка текста
      final cleanedText = _cleanText(text);

      // Извлечение даты
      final transferDate = _extractTransferDate(cleanedText);
      if (transferDate == null) {
        _logger.e('❌ НЕ НАЙДЕНА ДАТА ПРИЕМА-ПЕРЕДАЧИ');
        throw Exception('Не удалось извлечь дату приема-передачи из PDF');
      }

      _logger.i('✓ Дата: $transferDate');

      // Извлечение "Сдал"
      final handedBy = _extractHandedBy(cleanedText);
      _logger.i('✓ Сдал: "$handedBy"');

      // Извлечение таблицы - ПОСТРОЧНЫЙ МЕТОД
      final tableRecords = _extractTableRecordsLineByLine(cleanedText, source, transferDate, handedBy);
      records.addAll(tableRecords);

      if (records.isEmpty) {
        _logger.e('❌ НЕ НАЙДЕНО НИ ОДНОЙ ЗАПИСИ');
        throw Exception('Не удалось извлечь записи из таблицы PDF');
      }

      return records;
    } catch (e, stackTrace) {
      _logger.e('❌ ОШИБКА ПАРСИНГА ТЕКСТА', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Очистка текста
  String _cleanText(String text) {
    text = text.replaceAll('\u00AD', '-');
    text = text.replaceAll('\u200B', '');
    text = text.replaceAll('\xa0', ' ');
    text = text.split('\n').map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim()).join('\n');
    return text.trim();
  }

  /// Извлечение даты
  DateTime? _extractTransferDate(String text) {
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
      return null;
    }
  }

  /// Извлечение "Сдал"
  String _extractHandedBy(String text) {
    final handedByPattern = RegExp(
      r'Сдал:\s*([^\n]+?)(?:\s+Принял:|$)',
      caseSensitive: false,
      multiLine: true,
    );

    final match = handedByPattern.firstMatch(text);
    if (match != null && match.group(1) != null) {
      String handedBy = match.group(1)!.trim();
      handedBy = handedBy.replaceAll(RegExp(r'\s+'), ' ');
      final parts = handedBy.split(RegExp(r'\s+PickUp\s+Point', caseSensitive: false));
      if (parts.isNotEmpty) {
        handedBy = parts[0];
      }
      return handedBy.trim();
    }
    return '';
  }

  /// ПОСТРОЧНОЕ извлечение записей - для Android
  List<ScannedRecord> _extractTableRecordsLineByLine(
    String text,
    String source,
    DateTime transferDate,
    String handedBy,
  ) {
    final List<ScannedRecord> records = [];

    _logger.i('========================================');
    _logger.i('ПОСТРОЧНОЕ ИЗВЛЕЧЕНИЕ (для Android)');
    _logger.i('========================================');

    final lines = text.split('\n');
    _logger.i('Всего строк: ${lines.length}');

    // Ищем паттерн: Вес → Номер → Заказ → Место (4 последовательные строки)
    for (int i = 0; i < lines.length - 3; i++) {
      final line1 = lines[i].trim();
      final line2 = lines[i + 1].trim();
      final line3 = lines[i + 2].trim();
      final line4 = lines[i + 3].trim();

      // Проверяем паттерн:
      // Строка 1: Вес (число с точкой/запятой, например "7.25")
      // Строка 2: Номер (просто цифра, например "1")
      // Строка 3: Заказ (цифры с пробелом, например "69616 6030")
      // Строка 4: Номер места (формат XXX-N, например "696166030-1")

      final weightMatch = RegExp(r'^(\d+[,\.]\d+)$').firstMatch(line1);
      final numberMatch = RegExp(r'^(\d+)$').firstMatch(line2);
      final orderMatch = RegExp(r'^(\d+)\s+(\d+)$').firstMatch(line3);
      final placeMatch = RegExp(r'^(\d+\-\d+)$').firstMatch(line4);

      if (weightMatch != null && numberMatch != null && orderMatch != null && placeMatch != null) {
        try {
          // Извлекаем данные
          final weightStr = weightMatch.group(1)!.replaceAll(',', '.');
          final weight = double.tryParse(weightStr);
          final orderNumber = int.tryParse(numberMatch.group(1)!);
          final orderPart1 = orderMatch.group(1)!;
          final orderPart2 = orderMatch.group(2)!;
          final orderCode = orderPart1 + orderPart2;
          final placeNumber = placeMatch.group(1)!;

          if (weight == null || weight <= 0 || orderNumber == null) {
            continue;
          }

          // Создаем запись
          final record = ScannedRecord(
            transferDate: transferDate,
            source: source,
            orderNumber: orderNumber,
            placeNumber: placeNumber,
            weight: weight,
            orderCode: orderCode,
            handedBy: handedBy,
          );

          records.add(record);
          _logger.i('✓ Запись #$orderNumber: $placeNumber ($weightкг) → $orderCode');

          // Пропускаем обработанные строки
          i += 3;
        } catch (e) {
          _logger.w('Ошибка обработки строк: $e');
          continue;
        }
      }
    }

    _logger.i('========================================');
    _logger.i('НАЙДЕНО ЗАПИСЕЙ: ${records.length}');
    _logger.i('========================================');

    return records;
  }

  /// Валидация PDF
  Future<bool> validatePdf(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        return false;
      }

      final bytes = await file.readAsBytes();
      
      if (bytes.length < 5 || 
          bytes[0] != 0x25 || bytes[1] != 0x50 || 
          bytes[2] != 0x44 || bytes[3] != 0x46) {
        return false;
      }

      final document = PdfDocument(inputBytes: bytes);
      document.dispose();

      return true;
    } catch (e) {
      return false;
    }
  }
}