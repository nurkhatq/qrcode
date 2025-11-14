// lib/config/constants_ex.dart

/// Пример конфигурационного файла с константами приложения
///
/// ВАЖНО: Скопируйте этот файл в constants.dart и заполните своими данными!
/// НЕ КОММИТЬТЕ constants.dart в публичный репозиторий!
///
/// Инструкция:
/// 1. Скопируйте этот файл: cp lib/config/constants_ex.dart lib/config/constants.dart
/// 2. Откройте lib/config/constants.dart
/// 3. Замените значения своими реальными данными
library;


class AppConstants {
  // ============================================
  // Google Sheets Configuration
  // ============================================

  /// JSON credentials для Service Account
  /// Получите его из Google Cloud Console:
  /// 1. Перейдите в https://console.cloud.google.com
  /// 2. Создайте новый проект или выберите существующий
  /// 3. Включите Google Sheets API и Google Drive API
  /// 4. Создайте Service Account (IAM & Admin -> Service Accounts)
  /// 5. Создайте ключ (Keys -> Add Key -> JSON)
  /// 6. Скопируйте содержимое JSON файла сюда
  static const String googleCredentials = r'''
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "your-private-key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY_HERE\n-----END PRIVATE KEY-----\n",
  "client_email": "your-service-account@your-project-id.iam.gserviceaccount.com",
  "client_id": "your-client-id",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/your-service-account%40your-project-id.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
''';

  /// ID вашей Google Sheets таблицы
  /// Найдите его в URL таблицы:
  /// https://docs.google.com/spreadsheets/d/[SPREADSHEET_ID]/edit
  static const String spreadsheetId = 'YOUR_SPREADSHEET_ID_HERE';

  /// Название листа в таблице (по умолчанию "Sheet1")
  static const String worksheetName = 'QR Data';

  // ============================================
  // App Configuration
  // ============================================

  /// Название приложения
  static const String appName = 'QR Scanner';

  /// Версия приложения
  static const String appVersion = '1.0.0';

  // ============================================
  // Scanning Configuration
  // ============================================

  /// Таймаут для скачивания PDF (в секундах)
  static const int downloadTimeout = 30;

  /// Максимальный размер PDF для скачивания (в байтах)
  /// 50 MB = 50 * 1024 * 1024
  static const int maxPdfSize = 52428800;

  /// Задержка перед повторным сканированием того же QR кода (в секундах)
  static const int scanCooldown = 3;

  // ============================================
  // Database Configuration
  // ============================================

  /// Название локальной базы данных
  static const String dbName = 'qr_scanner.db';

  /// Версия базы данных
  /// ВАЖНО: Увеличьте это число если изменили структуру БД
  static const int dbVersion = 2;

  // ============================================
  // Google Sheets Column Names
  // ============================================

  /// Названия колонок в Google Sheets
  /// Порядок важен! Должен соответствовать порядку в ScannedRecord.toSheetRow()
  static const List<String> sheetHeaders = [
    'Дата загрузки',
    'Дата приема-передачи',
    'Источник',
    'Номер по порядку',
    'Номер места',
    'Вес',
    'Номер заказа',
    'Сдал',
  ];

  // ============================================
  // UI Configuration
  // ============================================

  /// Цвета приложения
  static const int primaryColorValue = 0xFF2196F3;
  static const int accentColorValue = 0xFF4CAF50;
  static const int errorColorValue = 0xFFF44336;

  // ============================================
  // Logging
  // ============================================

  /// Включить детальное логирование
  static const bool enableDetailedLogging = true;

  /// Сохранять логи в файл
  static const bool saveLogsToFile = false;
}
