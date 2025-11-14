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
      // Очистка текста
      final cleanedText = _cleanText(text);
      
      _logger.d('Первые 500 символов очищенного текста:\n${cleanedText.length > 500 ? cleanedText.substring(0, 500) : cleanedText}');

      // Извлечение даты
      final transferDate = _extractTransferDate(cleanedText);
      if (transferDate == null) {
        throw Exception('Не удалось извлечь дату приема-передачи');
      }

      _logger.d('Дата приема-передачи: $transferDate');

      // НОВЫЙ МЕТОД: Построчное извлечение для Android
      final androidRecords = _extractTableRecordsAndroid(cleanedText, source, transferDate);
      
      if (androidRecords.isNotEmpty) {
        _logger.i('✓ Android метод нашел ${androidRecords.length} записей');
        records.addAll(androidRecords);
        return records;
      }

      // Если Android метод не сработал, пробуем старый метод (для Desktop)
      _logger.i('Android метод не нашел записей, пробуем Desktop метод...');
      final desktopRecords = _extractTableRecords(cleanedText, source, transferDate);
      
      if (desktopRecords.isNotEmpty) {
        _logger.i('✓ Desktop метод нашел ${desktopRecords.length} записей');
        records.addAll(desktopRecords);
        return records;
      }

      // Если ничего не нашли
      throw Exception('Не удалось извлечь записи из таблицы PDF');
      
    } catch (e, stackTrace) {
      _logger.e('Ошибка парсинга текста: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Очистка текста
  String _cleanText(String text) {
    text = text.replaceAll('\u00AD', '-');
    text = text.replaceAll('\u200B', '');
    text = text.replaceAll('\xa0', ' ');
    
    // НЕ удаляем переносы строк - они важны для Android!
    final lines = text.split('\n');
    final cleanedLines = lines.map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim()).toList();
    
    return cleanedLines.join('\n').trim();
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
      _logger.w('Ошибка парсинга даты: $e');
      return null;
    }
  }

  /// НОВЫЙ МЕТОД: Построчное извлечение для Android
  /// Ищет паттерн с учетом пустых строк между данными
  List<ScannedRecord> _extractTableRecordsAndroid(
    String text,
    String source,
    DateTime transferDate,
  ) {
    final List<ScannedRecord> records = [];
    final lines = text.split('\n').map((l) => l.trim()).toList();

    _logger.i('=== ANDROID МЕТОД: Построчный парсинг (с пропуском пустых строк) ===');
    _logger.d('Всего строк: ${lines.length}');

    // Извлекаем "Сдал" и вес
    final handedBy = _extractHandedBy(text);
    final weightPattern = RegExp(r'(\d+[,\.]\d+)');
    final weightMatch = weightPattern.firstMatch(text);
    final defaultWeight = weightMatch != null 
        ? double.tryParse(weightMatch.group(1)!.replaceAll(',', '.')) ?? 0.0
        : 0.0;

    // Фильтруем только непустые строки
    final nonEmptyLines = lines.where((line) => line.isNotEmpty).toList();
    _logger.d('Непустых строк: ${nonEmptyLines.length}');

    // Ищем последовательность: Номер → Заказ → Место
    for (int i = 0; i < nonEmptyLines.length - 2; i++) {
      final line1 = nonEmptyLines[i];
      final line2 = nonEmptyLines[i + 1];
      final line3 = nonEmptyLines[i + 2];

      // Проверяем паттерны
      final numberMatch = RegExp(r'^(\d+)$').firstMatch(line1);
      final orderMatch = RegExp(r'^(\d+)\s+(\d+)$').firstMatch(line2);
      final placeMatch = RegExp(r'^(\d+\-\d+)$').firstMatch(line3);

      if (numberMatch != null && orderMatch != null && placeMatch != null) {
        try {
          final orderNumber = int.tryParse(numberMatch.group(1)!);
          final orderPart1 = orderMatch.group(1)!;
          final orderPart2 = orderMatch.group(2)!;
          final orderCode = orderPart1 + orderPart2;
          final placeNumber = placeMatch.group(1)!;

          if (orderNumber == null || orderCode.isEmpty || placeNumber.isEmpty) {
            continue;
          }

          final record = ScannedRecord(
            transferDate: transferDate,
            source: source,
            orderNumber: orderNumber,
            placeNumber: placeNumber,
            weight: defaultWeight,
            orderCode: orderCode,
            handedBy: handedBy,
          );

          records.add(record);
          _logger.d('✓ #$orderNumber: $placeNumber ($defaultWeight кг) → $orderCode');

          // Пропускаем обработанные строки
          i += 2;
        } catch (e) {
          _logger.w('Ошибка обработки строк: $e');
          continue;
        }
      }
    }

    _logger.i('Android метод: найдено ${records.length} записей');
    return records;
  }

  /// DESKTOP МЕТОД: Построчный с пропуском пустых строк
  List<ScannedRecord> _extractTableRecords(
    String text,
    String source,
    DateTime transferDate,
  ) {
    final List<ScannedRecord> records = [];

    _logger.i('=== DESKTOP МЕТОД: Построчный с заказом из 2 частей (с пропуском пустых строк) ===');

    // Извлекаем "Сдал" и вес
    final handedBy = _extractHandedBy(text);
    final weightPattern = RegExp(r'(\d+[,\.]\d+)');
    final weightMatch = weightPattern.firstMatch(text);
    final defaultWeight = weightMatch != null 
        ? double.tryParse(weightMatch.group(1)!.replaceAll(',', '.')) ?? 0.0
        : 0.0;

    final lines = text.split('\n').map((l) => l.trim()).toList();
    
    // Фильтруем только непустые строки
    final nonEmptyLines = lines.where((line) => line.isNotEmpty).toList();
    _logger.d('Непустых строк: ${nonEmptyLines.length}');

    // Ищем паттерн: Номер → Заказ → Место
    for (int i = 0; i < nonEmptyLines.length - 2; i++) {
      final line1 = nonEmptyLines[i];
      final line2 = nonEmptyLines[i + 1];
      final line3 = nonEmptyLines[i + 2];

      // Проверяем паттерны
      final numberMatch = RegExp(r'^(\d+)$').firstMatch(line1);
      final orderMatch = RegExp(r'^(\d+)\s+(\d+)$').firstMatch(line2);
      final placeMatch = RegExp(r'^(\d+\-\d+)$').firstMatch(line3);

      if (numberMatch != null && orderMatch != null && placeMatch != null) {
        try {
          final orderNumber = int.tryParse(numberMatch.group(1)!);
          final orderPart1 = orderMatch.group(1)!;
          final orderPart2 = orderMatch.group(2)!;
          final orderCode = orderPart1 + orderPart2;
          final placeNumber = placeMatch.group(1)!;

          if (orderNumber == null || orderCode.isEmpty || placeNumber.isEmpty) {
            continue;
          }

          final record = ScannedRecord(
            transferDate: transferDate,
            source: source,
            orderNumber: orderNumber,
            placeNumber: placeNumber,
            weight: defaultWeight,
            orderCode: orderCode,
            handedBy: handedBy,
          );

          records.add(record);
          _logger.d('✓ #$orderNumber: $placeNumber ($defaultWeight кг) → $orderCode');

          // Пропускаем обработанные строки
          i += 2;
        } catch (e) {
          _logger.w('Ошибка обработки строк: $e');
          continue;
        }
      }
    }

    _logger.i('Desktop метод: найдено ${records.length} записей');
    return records;
  }

  /// Извлечение информации "Сдал"
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
      
      // Убираем "PickUp Point" и всё после
      final parts = handedBy.split(RegExp(r'\s+PickUp\s+Point', caseSensitive: false));
      if (parts.isNotEmpty) {
        handedBy = parts[0];
      }
      
      return handedBy.trim();
    }
    
    // Если не нашли, возвращаем пустую строку
    return '';
  }

  /// Нормализация строки
  String _normalizeString(String str) {
    str = str.replaceAll(RegExp(r'\s+'), '');
    return str.toUpperCase();
  }

  /// Валидация PDF
  Future<bool> validatePdf(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        _logger.w('PDF файл не существует: $pdfPath');
        return false;
      }

      final bytes = await file.readAsBytes();
      
      if (bytes.length < 5 || 
          bytes[0] != 0x25 || bytes[1] != 0x50 || 
          bytes[2] != 0x44 || bytes[3] != 0x46) {
        _logger.w('Файл не является валидным PDF');
        return false;
      }

      final document = PdfDocument(inputBytes: bytes);
      document.dispose();

      return true;
    } catch (e) {
      _logger.e('Ошибка валидации PDF: $e');
      return false;
    }
  }
}