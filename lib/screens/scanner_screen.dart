// lib/screens/scanner_screen.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '../providers/app_provider.dart';
import '../config/constants.dart';

/// Главный экран приложения со сканером QR кодов
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  final Logger _logger = Logger();
  late MobileScannerController _scannerController;
  DateTime? _lastScanTime;
  String? _lastScannedCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Инициализация контроллера сканера
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    
    _logger.i('Scanner screen initialized');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Управление камерой при изменении состояния приложения
    if (state == AppLifecycleState.resumed) {
      _scannerController.start();
    } else if (state == AppLifecycleState.inactive) {
      _scannerController.stop();
    }
  }

  /// Обработка отсканированного кода
  void _handleBarcode(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    
    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;
      
      if (code != null && code.isNotEmpty) {
        // Проверка на повторное сканирование
        final now = DateTime.now();
        
        if (_lastScannedCode == code && _lastScanTime != null) {
          final difference = now.difference(_lastScanTime!);
          if (difference.inSeconds < AppConstants.scanCooldown) {
            _logger.d('Пропуск повторного сканирования: $code');
            return;
          }
        }
        
        _lastScannedCode = code;
        _lastScanTime = now;
        
        _logger.i('QR код отсканирован: $code');
        
        // Вибрация при успешном сканировании
        // HapticFeedback.mediumImpact();
        
        // Обработка кода
        _processCode(code);
      }
    }
  }

  /// Обработка отсканированного кода
  void _processCode(String code) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    provider.processQrCode(code);
  }

  /// Переключение вспышки
  void _toggleTorch() {
    _scannerController.toggleTorch();
    setState(() {});
  }

  /// Переход к списку записей
  void _navigateToRecords() {
    Navigator.pushNamed(context, '/records');
  }

  /// Синхронизация с Google Sheets
  void _syncWithGoogleSheets() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    provider.syncWithGoogleSheets();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканирование QR'),
        centerTitle: true,
        actions: [
          // Кнопка вспышки
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _scannerController,
              builder: (context, value, child) {
                final torchState = value.torchState;
                return Icon(
                  torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                );
              },
            ),
            onPressed: _toggleTorch,
            tooltip: 'Вспышка',
          ),
          // Кнопка списка записей
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _navigateToRecords,
            tooltip: 'Список записей',
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              // Область предпросмотра камеры
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    // Сканер
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _handleBarcode,
                      errorBuilder: (context, error, child) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 64,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Ошибка камеры: ${error.errorCode}',
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => _scannerController.start(),
                                child: const Text('Повторить'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    
                    // Рамка сканирования
                    Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    
                    // Индикатор загрузки
                    if (provider.isLoading)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                  ],
                ),
              ),
              
              // Информационная панель
              Expanded(
                flex: 2,
                child: Container(
                  color: Colors.grey[100],
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Сообщения
                      if (provider.errorMessage != null)
                        _buildErrorMessage(provider.errorMessage!),
                      
                      if (provider.successMessage != null)
                        _buildSuccessMessage(provider.successMessage!),
                      
                      const SizedBox(height: 16),
                      
                      // Статистика
                      _buildStatistics(provider),
                      
                      const Spacer(),
                      
                      // Кнопка синхронизации
                      ElevatedButton.icon(
                        onPressed: provider.isSyncing || provider.unsyncedRecords == 0
                            ? null
                            : _syncWithGoogleSheets,
                        icon: provider.isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload),
                        label: Text(
                          provider.isSyncing
                              ? 'Синхронизация...'
                              : 'Отправить в Google Sheets (${provider.unsyncedRecords})',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              Provider.of<AppProvider>(context, listen: false).clearMessages();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.green),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              Provider.of<AppProvider>(context, listen: false).clearMessages();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics(AppProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Статистика',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatRow('Всего записей:', provider.totalRecords.toString()),
            _buildStatRow(
              'Не синхронизировано:',
              provider.unsyncedRecords.toString(),
              color: provider.unsyncedRecords > 0 ? Colors.orange : null,
            ),
            _buildStatRow(
              'Синхронизировано:',
              provider.syncedRecords.toString(),
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}