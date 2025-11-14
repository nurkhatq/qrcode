// lib/services/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:logger/logger.dart';
import '../models/scanned_record.dart';
import '../config/constants.dart';

/// Сервис для работы с локальной SQLite базой данных
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  final Logger _logger = Logger();

  /// Получение экземпляра базы данных
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Инициализация базы данных
  Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, AppConstants.dbName);

      _logger.i('Инициализация базы данных: $path');

      return await openDatabase(
        path,
        version: AppConstants.dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      _logger.e('Ошибка инициализации базы данных: $e');
      rethrow;
    }
  }

  /// Создание таблиц при первом запуске
  Future<void> _onCreate(Database db, int version) async {
    _logger.i('Создание таблиц базы данных');
    
    await db.execute('''
      CREATE TABLE scanned_records (
        id TEXT PRIMARY KEY,
        uploadDate TEXT NOT NULL,
        transferDate TEXT NOT NULL,
        source TEXT NOT NULL,
        orderNumber INTEGER NOT NULL,
        placeNumber TEXT NOT NULL,
        weight REAL NOT NULL,
        orderCode TEXT NOT NULL,
        isSynced INTEGER NOT NULL DEFAULT 0,
        syncDate TEXT,
        createdAt TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(placeNumber, orderCode)
      )
    ''');

    // Создание индексов для быстрого поиска
    await db.execute('''
      CREATE INDEX idx_place_order ON scanned_records(placeNumber, orderCode)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_synced ON scanned_records(isSynced)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_transfer_date ON scanned_records(transferDate)
    ''');

    _logger.i('Таблицы успешно созданы');
  }

  /// Обновление базы данных при изменении версии
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.i('Обновление базы данных с версии $oldVersion на $newVersion');
    
    // Здесь будут миграции при обновлении структуры БД
    // Пока оставляем пустым
  }

  /// Сохранение записи в базу данных
  Future<int> insertRecord(ScannedRecord record) async {
    try {
      final db = await database;
      final id = await db.insert(
        'scanned_records',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _logger.d('Запись сохранена: ${record.placeNumber} - ${record.orderCode}');
      return id;
    } catch (e) {
      _logger.e('Ошибка сохранения записи: $e');
      rethrow;
    }
  }

  /// Сохранение списка записей (batch insert)
  Future<void> insertRecords(List<ScannedRecord> records) async {
    try {
      final db = await database;
      final batch = db.batch();
      
      for (var record in records) {
        batch.insert(
          'scanned_records',
          record.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      
      await batch.commit(noResult: true);
      _logger.i('Сохранено записей: ${records.length}');
    } catch (e) {
      _logger.e('Ошибка массового сохранения: $e');
      rethrow;
    }
  }

  /// Получение всех записей
  Future<List<ScannedRecord>> getAllRecords() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'scanned_records',
        orderBy: 'transferDate DESC, orderNumber ASC',
      );
      
      return List.generate(maps.length, (i) => ScannedRecord.fromMap(maps[i]));
    } catch (e) {
      _logger.e('Ошибка получения записей: $e');
      return [];
    }
  }

  /// Получение несинхронизированных записей
  Future<List<ScannedRecord>> getUnsyncedRecords() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'scanned_records',
        where: 'isSynced = ?',
        whereArgs: [0],
        orderBy: 'transferDate DESC, orderNumber ASC',
      );
      
      return List.generate(maps.length, (i) => ScannedRecord.fromMap(maps[i]));
    } catch (e) {
      _logger.e('Ошибка получения несинхронизированных записей: $e');
      return [];
    }
  }

  /// Получение записей по источнику
  Future<List<ScannedRecord>> getRecordsBySource(String source) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'scanned_records',
        where: 'source = ?',
        whereArgs: [source],
        orderBy: 'orderNumber ASC',
      );
      
      return List.generate(maps.length, (i) => ScannedRecord.fromMap(maps[i]));
    } catch (e) {
      _logger.e('Ошибка получения записей по источнику: $e');
      return [];
    }
  }

  /// Проверка существования записи по placeNumber и orderCode
  Future<bool> recordExists(String placeNumber, String orderCode) async {
    try {
      final db = await database;
      final result = await db.query(
        'scanned_records',
        where: 'placeNumber = ? AND orderCode = ?',
        whereArgs: [placeNumber, orderCode],
        limit: 1,
      );
      
      return result.isNotEmpty;
    } catch (e) {
      _logger.e('Ошибка проверки существования записи: $e');
      return false;
    }
  }

  /// Обновление записи
  Future<int> updateRecord(ScannedRecord record) async {
    try {
      final db = await database;
      final count = await db.update(
        'scanned_records',
        record.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
      
      if (count > 0) {
        _logger.d('Запись обновлена: ${record.id}');
      }
      
      return count;
    } catch (e) {
      _logger.e('Ошибка обновления записи: $e');
      rethrow;
    }
  }

  /// Пометка записи как синхронизированной
  Future<int> markAsSynced(String recordId) async {
    try {
      final db = await database;
      final count = await db.update(
        'scanned_records',
        {
          'isSynced': 1,
          'syncDate': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );
      
      if (count > 0) {
        _logger.d('Запись помечена как синхронизированная: $recordId');
      }
      
      return count;
    } catch (e) {
      _logger.e('Ошибка пометки записи как синхронизированной: $e');
      rethrow;
    }
  }

  /// Пометка нескольких записей как синхронизированных
  Future<void> markMultipleAsSynced(List<String> recordIds) async {
    try {
      final db = await database;
      final batch = db.batch();
      final syncDate = DateTime.now().toIso8601String();
      
      for (var id in recordIds) {
        batch.update(
          'scanned_records',
          {
            'isSynced': 1,
            'syncDate': syncDate,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      
      await batch.commit(noResult: true);
      _logger.i('Помечено как синхронизировано записей: ${recordIds.length}');
    } catch (e) {
      _logger.e('Ошибка массовой пометки записей: $e');
      rethrow;
    }
  }

  /// Удаление записи
  Future<int> deleteRecord(String recordId) async {
    try {
      final db = await database;
      final count = await db.delete(
        'scanned_records',
        where: 'id = ?',
        whereArgs: [recordId],
      );
      
      if (count > 0) {
        _logger.d('Запись удалена: $recordId');
      }
      
      return count;
    } catch (e) {
      _logger.e('Ошибка удаления записи: $e');
      rethrow;
    }
  }

  /// Удаление всех синхронизированных записей
  Future<int> deleteSyncedRecords() async {
    try {
      final db = await database;
      final count = await db.delete(
        'scanned_records',
        where: 'isSynced = ?',
        whereArgs: [1],
      );
      
      _logger.i('Удалено синхронизированных записей: $count');
      return count;
    } catch (e) {
      _logger.e('Ошибка удаления синхронизированных записей: $e');
      rethrow;
    }
  }

  /// Удаление всех записей
  Future<int> deleteAllRecords() async {
    try {
      final db = await database;
      final count = await db.delete('scanned_records');
      
      _logger.i('Удалено всех записей: $count');
      return count;
    } catch (e) {
      _logger.e('Ошибка удаления всех записей: $e');
      rethrow;
    }
  }

  /// Получение статистики
  Future<Map<String, int>> getStatistics() async {
    try {
      final db = await database;
      
      final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM scanned_records');
      final syncedResult = await db.rawQuery('SELECT COUNT(*) as count FROM scanned_records WHERE isSynced = 1');
      final unsyncedResult = await db.rawQuery('SELECT COUNT(*) as count FROM scanned_records WHERE isSynced = 0');
      
      return {
        'total': totalResult.first['count'] as int,
        'synced': syncedResult.first['count'] as int,
        'unsynced': unsyncedResult.first['count'] as int,
      };
    } catch (e) {
      _logger.e('Ошибка получения статистики: $e');
      return {'total': 0, 'synced': 0, 'unsynced': 0};
    }
  }

  /// Закрытие базы данных
  Future<void> close() async {
    final db = await database;
    await db.close();
    _logger.i('База данных закрыта');
  }
}