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
  /// Паттерн: Вес → Номер → Заказ → Место (4 строки)
  List<ScannedRecord> _extractTableRecordsAndroid(
    String text,
    String source,
    DateTime transferDate,
  ) {
    final List<ScannedRecord> records = [];
    final lines = text.split('\n').map((l) => l.trim()).toList();

    _logger.i('=== ANDROID МЕТОД: Построчный парсинг (Вес → Номер → Заказ → Место) ===');
    _logger.d('Всего строк: ${lines.length}');

    // Извлекаем "Сдал"
    final handedBy = _extractHandedBy(text);

    // Фильтруем только непустые строки
    final nonEmptyLines = lines.where((line) => line.isNotEmpty).toList();
    _logger.d('Непустых строк: ${nonEmptyLines.length}');

    // Ищем последовательность: Вес → Номер → Заказ → Место (4 строки)
    for (int i = 0; i < nonEmptyLines.length - 3; i++) {
      final line1 = nonEmptyLines[i];
      final line2 = nonEmptyLines[i + 1];
      final line3 = nonEmptyLines[i + 2];
      final line4 = nonEmptyLines[i + 3];

      // Проверяем паттерны
      // Строка 1: Вес (число с точкой, например "15.6")
      final weightMatch = RegExp(r'^(\d+[,\.]\d+)$').firstMatch(line1);
      // Строка 2: Номер (просто цифра, например "1")
      final numberMatch = RegExp(r'^(\d+)$').firstMatch(line2);
      // Строка 3: Заказ (две части, например "71037 1844")
      final orderMatch = RegExp(r'^(\d+)\s+(\d+)$').firstMatch(line3);
      // Строка 4: Место (формат XXX-N, например "710371844-1")
      final placeMatch = RegExp(r'^(\d+\-\d+)$').firstMatch(line4);

      if (weightMatch != null && numberMatch != null && orderMatch != null && placeMatch != null) {
        try {
          final weightStr = weightMatch.group(1)!.replaceAll(',', '.');
          final weight = double.tryParse(weightStr);
          final orderNumber = int.tryParse(numberMatch.group(1)!);
          final orderPart1 = orderMatch.group(1)!;
          final orderPart2 = orderMatch.group(2)!;
          final orderCode = orderPart1 + orderPart2;
          final placeNumber = placeMatch.group(1)!;

          if (weight == null || weight <= 0 || orderNumber == null || orderCode.isEmpty || placeNumber.isEmpty) {
            continue;
          }

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
          _logger.d('✓ #$orderNumber: $placeNumber ($weight кг) → $orderCode');

          // Пропускаем обработанные строки
          i += 3;
        } catch (e) {
          _logger.w('Ошибка обработки строк: $e');
          continue;
        }
      }
    }

    _logger.i('Android метод: найдено ${records.length} записей');
    return records;
  }

  /// DESKTOP МЕТОД: Построчный (Вес → Номер → Заказ → Место)
  List<ScannedRecord> _extractTableRecords(
    String text,
    String source,
    DateTime transferDate,
  ) {
    final List<ScannedRecord> records = [];

    _logger.i('=== DESKTOP МЕТОД: Построчный (Вес → Номер → Заказ → Место) ===');

    // Извлекаем "Сдал"
    final handedBy = _extractHandedBy(text);

    final lines = text.split('\n').map((l) => l.trim()).toList();
    
    // Фильтруем только непустые строки
    final nonEmptyLines = lines.where((line) => line.isNotEmpty).toList();
    _logger.d('Непустых строк: ${nonEmptyLines.length}');

    // Ищем паттерн: Вес → Номер → Заказ → Место (4 строки)
    for (int i = 0; i < nonEmptyLines.length - 3; i++) {
      final line1 = nonEmptyLines[i];
      final line2 = nonEmptyLines[i + 1];
      final line3 = nonEmptyLines[i + 2];
      final line4 = nonEmptyLines[i + 3];

      // Проверяем паттерны
      // Строка 1: Вес
      final weightMatch = RegExp(r'^(\d+[,\.]\d+)$').firstMatch(line1);
      // Строка 2: Номер
      final numberMatch = RegExp(r'^(\d+)$').firstMatch(line2);
      // Строка 3: Заказ (две части)
      final orderMatch = RegExp(r'^(\d+)\s+(\d+)$').firstMatch(line3);
      // Строка 4: Место
      final placeMatch = RegExp(r'^(\d+\-\d+)$').firstMatch(line4);

      if (weightMatch != null && numberMatch != null && orderMatch != null && placeMatch != null) {
        try {
          final weightStr = weightMatch.group(1)!.replaceAll(',', '.');
          final weight = double.tryParse(weightStr);
          final orderNumber = int.tryParse(numberMatch.group(1)!);
          final orderPart1 = orderMatch.group(1)!;
          final orderPart2 = orderMatch.group(2)!;
          final orderCode = orderPart1 + orderPart2;
          final placeNumber = placeMatch.group(1)!;

          if (weight == null || weight <= 0 || orderNumber == null || orderCode.isEmpty || placeNumber.isEmpty) {
            continue;
          }

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
          _logger.d('✓ #$orderNumber: $placeNumber ($weight кг) → $orderCode');

          // Пропускаем обработанные строки
          i += 3;
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
    // Ищем строку ПОСЛЕ даты приема-передачи
    // Формат: "Дата приёма-передачи:\n\n14.11.2025 13:06:30\n\nПроизводство мебели TURAN"
    final handedByPattern = RegExp(
      r'\d{2}\.\d{2}\.\d{4}\s+\d{2}:\d{2}:\d{2}\s*\n+\s*([^\n]+)',
      caseSensitive: false,
      multiLine: true,
    );

    final match = handedByPattern.firstMatch(text);
    if (match != null && match.group(1) != null) {
      String handedBy = match.group(1)!.trim();
      handedBy = handedBy.replaceAll(RegExp(r'\s+'), ' ');
      
      // Убираем "PickUp Point" и всё после, если есть
      final parts = handedBy.split(RegExp(r'\s+PickUp\s+Point', caseSensitive: false));
      if (parts.isNotEmpty) {
        handedBy = parts[0];
      }
      
      return handedBy.trim();
    }
    
    // Если не нашли по новому паттерну, пробуем старый
    final oldPattern = RegExp(
      r'Сдал:\s*([^\n]+?)(?:\s+Принял:|$)',
      caseSensitive: false,
      multiLine: true,
    );
    
    final oldMatch = oldPattern.firstMatch(text);
    if (oldMatch != null && oldMatch.group(1) != null) {
      String handedBy = oldMatch.group(1)!.trim();
      handedBy = handedBy.replaceAll(RegExp(r'\s+'), ' ');
      
      final parts = handedBy.split(RegExp(r'\s+PickUp\s+Point', caseSensitive: false));
      if (parts.isNotEmpty) {
        handedBy = parts[0];
      }
      
      return handedBy.trim();
    }
    
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