// lib/models/scanned_record.dart

import 'package:uuid/uuid.dart';

/// Модель данных для одной записи из PDF таблицы
class ScannedRecord {
  /// Уникальный ID записи (генерируется автоматически)
  final String id;
  
  /// Дата когда запись была загружена в приложение
  final DateTime uploadDate;
  
  /// Дата приема-передачи из PDF документа
  final DateTime transferDate;
  
  /// Источник (URL или название документа)
  final String source;
  
  /// Номер по порядку в таблице
  final int orderNumber;
  
  /// Номер места (например ZMKZ0000001)
  final String placeNumber;
  
  /// Вес (в килограммах)
  final double weight;
  
  /// Номер заказа (например WB123456789)
  final String orderCode;
  
  /// Флаг - была ли запись отправлена в Google Sheets
  final bool isSynced;
  
  /// Дата синхронизации с Google Sheets
  final DateTime? syncDate;

  ScannedRecord({
    String? id,
    DateTime? uploadDate,
    required this.transferDate,
    required this.source,
    required this.orderNumber,
    required this.placeNumber,
    required this.weight,
    required this.orderCode,
    this.isSynced = false,
    this.syncDate,
  })  : id = id ?? const Uuid().v4(),
        uploadDate = uploadDate ?? DateTime.now();

  /// Создание копии записи с изменениями
  ScannedRecord copyWith({
    String? id,
    DateTime? uploadDate,
    DateTime? transferDate,
    String? source,
    int? orderNumber,
    String? placeNumber,
    double? weight,
    String? orderCode,
    bool? isSynced,
    DateTime? syncDate,
  }) {
    return ScannedRecord(
      id: id ?? this.id,
      uploadDate: uploadDate ?? this.uploadDate,
      transferDate: transferDate ?? this.transferDate,
      source: source ?? this.source,
      orderNumber: orderNumber ?? this.orderNumber,
      placeNumber: placeNumber ?? this.placeNumber,
      weight: weight ?? this.weight,
      orderCode: orderCode ?? this.orderCode,
      isSynced: isSynced ?? this.isSynced,
      syncDate: syncDate ?? this.syncDate,
    );
  }

  /// Преобразование в Map для сохранения в базу данных
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uploadDate': uploadDate.toIso8601String(),
      'transferDate': transferDate.toIso8601String(),
      'source': source,
      'orderNumber': orderNumber,
      'placeNumber': placeNumber,
      'weight': weight,
      'orderCode': orderCode,
      'isSynced': isSynced ? 1 : 0,
      'syncDate': syncDate?.toIso8601String(),
    };
  }

  /// Создание из Map (из базы данных)
  factory ScannedRecord.fromMap(Map<String, dynamic> map) {
    return ScannedRecord(
      id: map['id'] as String,
      uploadDate: DateTime.parse(map['uploadDate'] as String),
      transferDate: DateTime.parse(map['transferDate'] as String),
      source: map['source'] as String,
      orderNumber: map['orderNumber'] as int,
      placeNumber: map['placeNumber'] as String,
      weight: map['weight'] as double,
      orderCode: map['orderCode'] as String,
      isSynced: (map['isSynced'] as int) == 1,
      syncDate: map['syncDate'] != null 
          ? DateTime.parse(map['syncDate'] as String) 
          : null,
    );
  }

  /// Преобразование в список значений для Google Sheets
  /// Порядок должен соответствовать AppConstants.sheetHeaders
  List<String> toSheetRow() {
    return [
      _formatDate(uploadDate),
      _formatDate(transferDate),
      source,
      orderNumber.toString(),
      placeNumber,
      weight.toString(),
      orderCode,
    ];
  }

  /// Форматирование даты в читаемый формат
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'ScannedRecord{id: $id, placeNumber: $placeNumber, orderCode: $orderCode, weight: $weight, isSynced: $isSynced}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is ScannedRecord &&
        other.placeNumber == placeNumber &&
        other.orderCode == orderCode;
  }

  @override
  int get hashCode => placeNumber.hashCode ^ orderCode.hashCode;
}

/// Модель для группировки записей по документу
class ScannedDocument {
  final String source;
  final DateTime transferDate;
  final List<ScannedRecord> records;
  
  ScannedDocument({
    required this.source,
    required this.transferDate,
    required this.records,
  });
  
  /// Количество записей в документе
  int get recordCount => records.length;
  
  /// Все ли записи синхронизированы
  bool get isFullySynced => records.every((r) => r.isSynced);
  
  /// Количество синхронизированных записей
  int get syncedCount => records.where((r) => r.isSynced).length;
  
  /// Общий вес всех записей
  double get totalWeight => records.fold(0.0, (sum, r) => sum + r.weight);
}