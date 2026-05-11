import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../models/ssh_connection.dart';
import 'terminal_screen.dart';
import 'dialogs/connection_dialog.dart';

class ConnectionListScreen extends StatelessWidget {
  const ConnectionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connections = context.watch<ConnectionProvider>().connections;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🔐 SSH Подключения'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: () => context.read<ConnectionProvider>().loadConnections(),
          ),
        ],
      ),
      body: connections.isEmpty ? _buildEmptyState(context) : _buildConnectionList(context, connections),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openConnectionDialog(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Добавить сервер'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 64, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text('Нет подключений', style: TextStyle(fontSize: 18, color: Colors.grey[400])),
          const SizedBox(height: 8),
          Text('Нажмите + чтобы добавить первый сервер', style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _openConnectionDialog(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Добавить подключение'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionList(BuildContext context, List<SSHConnection> connections) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: connections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final conn = connections[index];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(conn.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('${conn.username}@${conn.host}:${conn.port}', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                if (conn.keyLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(Icons.key, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text('Ключ: ${conn.keyLabel}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ]),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _openConnectionDialog(context, conn)),
                IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => _confirmDelete(context, conn)),
              ],
            ),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TerminalScreen(connection: conn))),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, SSHConnection conn) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Удалить подключение?'),
      content: Text('Вы уверены, что хотите удалить "${conn.label}"?\n\nКлюч будет безвозвратно удалён.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () async {
            await context.read<ConnectionProvider>().removeConnection(conn.id);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Удалить'),
        ),
      ],
    ));
  }

  void _openConnectionDialog(BuildContext context, SSHConnection? existing) {
    showDialog(context: context, builder: (ctx) => ConnectionDialog(connection: existing));
  }
}