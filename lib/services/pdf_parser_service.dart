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

      _logger.d('Очищенный текст (первые 500 символов):\n${cleanedText.length > 500 ? cleanedText.substring(0, 500) : cleanedText}');

      // Извлечение даты приема-передачи
      final transferDate = _extractTransferDate(cleanedText);
      if (transferDate == null) {
        _logger.e('Не найдена дата приема-передачи. Проверьте формат даты в PDF.');
        _logger.d('Полный текст для отладки:\n$cleanedText');
        throw Exception('Не удалось извлечь дату приема-передачи из PDF. Проверьте формат документа.');
      }

      _logger.d('Дата приема-передачи: $transferDate');

      // Извлечение информации о том, кто сдал
      final handedBy = _extractHandedBy(cleanedText);
      _logger.d('Сдал: $handedBy');

      // Извлечение таблицы с данными
      final tableRecords = _extractTableRecords(cleanedText, source, transferDate, handedBy);
      records.addAll(tableRecords);

      if (records.isEmpty) {
        _logger.e('Не найдено ни одной записи в таблице. Полный текст для отладки:\n$cleanedText');
        throw Exception('Не удалось извлечь записи из таблицы PDF. Проверьте формат документа.');
      }

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

  /// Извлечение информации о том, кто сдал груз
  String _extractHandedBy(String text) {
    // Ищем паттерн "Сдал:" и извлекаем текст после него
    // Пример: "Сдал: Производство мебели TURAN PickUp Point 6 AS"
    final handedByPattern = RegExp(
      r'Сдал:\s*([^\n]+?)(?:\s+Принял:|$)',
      caseSensitive: false,
      multiLine: true,
    );

    final match = handedByPattern.firstMatch(text);
    if (match != null && match.group(1) != null) {
      String handedBy = match.group(1)!.trim();
      // Очистка от лишних символов
      handedBy = handedBy.replaceAll(RegExp(r'\s+'), ' ');
      // Удаляем "PickUp Point" и всё после него
      handedBy = handedBy.split(RegExp(r'\s+PickUp\s+Point', caseSensitive: false))[0];
      _logger.d('Извлечено "Сдал": $handedBy');
      return handedBy.trim();
    }

    _logger.w('Не удалось извлечь информацию "Сдал"');
    return '';
  }

  /// Извлечение записей из таблицы
  List<ScannedRecord> _extractTableRecords(
    String text,
    String source,
    DateTime transferDate,
    String handedBy,
  ) {
    final List<ScannedRecord> records = [];

    // Новый паттерн для строки таблицы
    // Формат из вашего PDF: [номер] [номер_места с дефисом] [вес] [заказ часть1] [заказ часть2]
    // Пример: "1 696166030­1 7.25 69616 6030"
    // Примечание: дефис может быть обычным "-" или мягким переносом "­" (U+00AD)

    final rowPattern = RegExp(
      r'(\d+)\s+([\d]+[\-\u00AD][\d]+)\s+([\d,\.]+)\s+([\d]+)\s+([\d]+)',
      multiLine: true,
    );

    final matches = rowPattern.allMatches(text);

    _logger.i('Основной паттерн: найдено совпадений: ${matches.length}');

    for (var match in matches) {
      try {
        final orderNumber = int.parse(match.group(1)!);

        // Номер места - заменяем мягкий перенос на обычный дефис
        String placeNumber = match.group(2)!;
        placeNumber = placeNumber.replaceAll('\u00AD', '-');

        // Вес
        final weightStr = match.group(3)!.replaceAll(',', '.');
        final weight = double.parse(weightStr);

        // Номер заказа - объединяем две части без пробела
        final orderPart1 = match.group(4)!;
        final orderPart2 = match.group(5)!;
        final orderCode = orderPart1 + orderPart2;

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
          handedBy: handedBy,
        );

        records.add(record);
        _logger.d('Добавлена запись: $placeNumber - вес: $weight - заказ: $orderCode');
      } catch (e) {
        _logger.w('Ошибка парсинга строки таблицы: $e');
        continue;
      }
    }

    // Если основной паттерн не сработал, пробуем альтернативный метод
    if (records.isEmpty) {
      _logger.w('Основной паттерн не нашел записей. Пробуем альтернативный метод...');
      final altRecords = _extractTableRecordsAlternative(text, source, transferDate, handedBy);
      records.addAll(altRecords);
      _logger.i('Альтернативный метод нашел записей: ${altRecords.length}');
    }

    return records;
  }

  /// Альтернативный метод извлечения записей (для плохо отформатированных PDF)
  List<ScannedRecord> _extractTableRecordsAlternative(
    String text,
    String source,
    DateTime transferDate,
    String handedBy,
  ) {
    final List<ScannedRecord> records = [];

    try {
      // Разбиваем текст на строки
      final lines = text.split('\n');
      _logger.d('Всего строк для анализа: ${lines.length}');

      int checkedLines = 0;
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        checkedLines++;
        // Попробуем найти строку формата: [номер] [цифры­цифра] [вес] [цифры] [цифры]
        // Более простой паттерн без жестких требований
        final simplePattern = RegExp(
          r'^(\d+)\s+([\d]+[\-\u00AD\s]*[\d]+)\s+([\d,\.]+)\s+([\d\s]+)$',
        );

        final match = simplePattern.firstMatch(line);
        if (match == null) {
          // Логируем первые несколько непрошедших строк для отладки
          if (checkedLines <= 5 && line.contains(RegExp(r'\d'))) {
            _logger.d('Строка не подошла под паттерн: "$line"');
          }
          continue;
        }

        try {
          final orderNumber = int.parse(match.group(1)!);

          // Извлекаем номер места
          String placeNumber = match.group(2)!.trim();
          placeNumber = placeNumber.replaceAll('\u00AD', '-');
          placeNumber = placeNumber.replaceAll(RegExp(r'\s+'), '');

          // Извлекаем вес
          final weightStr = match.group(3)!.replaceAll(',', '.');
          final weight = double.tryParse(weightStr);
          if (weight == null || weight <= 0) continue;

          // Извлекаем номер заказа (может быть с пробелами)
          String orderCode = match.group(4)!.trim();
          orderCode = orderCode.replaceAll(RegExp(r'\s+'), '');

          if (placeNumber.isEmpty || orderCode.isEmpty) continue;

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
          _logger.d('Альтернативный метод: добавлена запись $placeNumber - $orderCode');
        } catch (e) {
          _logger.w('Ошибка обработки строки: $line - $e');
          continue;
        }
      }
    } catch (e) {
      _logger.w('Ошибка в альтернативном методе парсинга: $e');
    }

    return records;
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