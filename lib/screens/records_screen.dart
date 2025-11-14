// lib/screens/records_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../models/scanned_record.dart';

/// Экран со списком всех отсканированных записей
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  bool _groupByDocument = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Список записей'),
        centerTitle: true,
        actions: [
          // Переключение режима отображения
          IconButton(
            icon: Icon(_groupByDocument ? Icons.list : Icons.folder),
            onPressed: () {
              setState(() {
                _groupByDocument = !_groupByDocument;
              });
            },
            tooltip: _groupByDocument ? 'Список' : 'Группировка',
          ),
          // Меню
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'sync',
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload),
                    SizedBox(width: 8),
                    Text('Синхронизировать'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete_synced',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep),
                    SizedBox(width: 8),
                    Text('Удалить синхронизированные'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Удалить все', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.records.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              // Информационная панель
              _buildInfoPanel(provider),
              
              // Список записей
              Expanded(
                child: _groupByDocument
                    ? _buildGroupedList(provider)
                    : _buildFlatList(provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.qr_code_scanner,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Нет записей',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Отсканируйте QR код чтобы начать',
            style: TextStyle(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(AppProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoItem(
            'Всего',
            provider.totalRecords.toString(),
            Colors.blue,
          ),
          _buildInfoItem(
            'Не синхр.',
            provider.unsyncedRecords.toString(),
            Colors.orange,
          ),
          _buildInfoItem(
            'Синхр.',
            provider.syncedRecords.toString(),
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildGroupedList(AppProvider provider) {
    final documents = provider.getGroupedRecords();

    return ListView.builder(
      itemCount: documents.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final document = documents[index];
        return _buildDocumentCard(document);
      },
    );
  }

  Widget _buildDocumentCard(ScannedDocument document) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: Icon(
          document.isFullySynced ? Icons.check_circle : Icons.pending,
          color: document.isFullySynced ? Colors.green : Colors.orange,
        ),
        title: Text(
          'Документ от ${dateFormat.format(document.transferDate)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${document.recordCount} записей • '
          'Синхр.: ${document.syncedCount}/${document.recordCount} • '
          'Вес: ${document.totalWeight.toStringAsFixed(1)} кг',
        ),
        children: document.records.map((record) {
          return _buildRecordTile(record);
        }).toList(),
      ),
    );
  }

  Widget _buildFlatList(AppProvider provider) {
    return ListView.builder(
      itemCount: provider.records.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final record = provider.records[index];
        return _buildRecordCard(record);
      },
    );
  }

  Widget _buildRecordCard(ScannedRecord record) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: _buildRecordTile(record),
    );
  }

  Widget _buildRecordTile(ScannedRecord record) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: record.isSynced ? Colors.green : Colors.orange,
        child: Text(
          record.orderNumber.toString(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      title: Text(
        '${record.placeNumber} → ${record.orderCode}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Вес: ${record.weight} кг'),
          Text(
            'Дата: ${dateFormat.format(record.transferDate)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => _handleRecordAction(value, record),
        itemBuilder: (context) => [
          if (!record.isSynced)
            const PopupMenuItem(
              value: 'sync',
              child: Row(
                children: [
                  Icon(Icons.cloud_upload, size: 20),
                  SizedBox(width: 8),
                  Text('Синхронизировать'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, size: 20, color: Colors.red),
                SizedBox(width: 8),
                Text('Удалить', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }

  void _handleMenuAction(String action) async {
    final provider = Provider.of<AppProvider>(context, listen: false);

    switch (action) {
      case 'sync':
        provider.syncWithGoogleSheets();
        break;
        
      case 'delete_synced':
        final confirm = await _showConfirmDialog(
          'Удалить синхронизированные записи?',
          'Это действие нельзя отменить.',
        );
        if (confirm == true) {
          provider.deleteSyncedRecords();
        }
        break;
        
      case 'delete_all':
        final confirm = await _showConfirmDialog(
          'Удалить все записи?',
          'Это действие нельзя отменить. Все данные будут потеряны.',
        );
        if (confirm == true) {
          provider.deleteAllRecords();
        }
        break;
    }
  }

  void _handleRecordAction(String action, ScannedRecord record) async {
    final provider = Provider.of<AppProvider>(context, listen: false);

    switch (action) {
      case 'sync':
        // TODO: Синхронизировать одну запись
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Функция в разработке')),
        );
        break;
        
      case 'delete':
        final confirm = await _showConfirmDialog(
          'Удалить запись?',
          '${record.placeNumber} → ${record.orderCode}',
        );
        if (confirm == true) {
          provider.deleteRecord(record.id);
        }
        break;
    }
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}