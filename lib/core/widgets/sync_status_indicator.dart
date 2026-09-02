import 'package:flutter/material.dart';
import '../cloud/cloud_sync_service.dart';
import '../cloud/cloud_sync_models.dart';

/// Widget that displays the current sync status
class SyncStatusIndicator extends StatefulWidget {
  const SyncStatusIndicator({
    super.key,
    this.compact = false,
    this.onTapSync,
  });

  final bool compact;
  final VoidCallback? onTapSync;

  @override
  State<SyncStatusIndicator> createState() => _SyncStatusIndicatorState();
}

class _SyncStatusIndicatorState extends State<SyncStatusIndicator> {
  late final CloudSyncService _syncService;

  @override
  void initState() {
    super.initState();
    _syncService = CloudSyncService.instance;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: _syncService.syncStatusStream,
      initialData: _syncService.syncStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? _syncService.syncStatus;
        return _buildStatusWidget(status);
      },
    );
  }

  Widget _buildStatusWidget(SyncStatus status) {
    if (widget.compact) {
      return _buildCompactStatus(status);
    }
    return _buildFullStatus(status);
  }

  Widget _buildCompactStatus(SyncStatus status) {
    final (icon, color, label) = _getStatusInfo(status);

    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: status == SyncStatus.pending ? widget.onTapSync : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullStatus(SyncStatus status) {
    final (icon, color, label) = _getStatusInfo(status);
    final stats = _syncService.getSyncStats();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (stats['authenticated'] == true)
                      Text(
                        'Pending: ${stats['pending']}, Synced: ${stats['synced']}, Failed: ${stats['failed']}',
                        style: const TextStyle(
                          color: Color(0xFF6A7283),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (status == SyncStatus.pending)
                ElevatedButton(
                  onPressed: widget.onTapSync,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    backgroundColor: color,
                  ),
                  child: const Text(
                    'Sync Now',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _getStatusInfo(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return (
          Icons.check_circle_outline,
          const Color(0xFF2E7D32),
          'Synced',
        );
      case SyncStatus.syncing:
        return (
          Icons.sync,
          const Color(0xFF1976D2),
          'Syncing...',
        );
      case SyncStatus.offline:
        return (
          Icons.cloud_off_outlined,
          const Color(0xFF6A7283),
          'Offline',
        );
      case SyncStatus.pending:
        return (
          Icons.schedule,
          const Color(0xFFF57C00),
          'Changes Pending',
        );
      case SyncStatus.error:
        return (
          Icons.error_outline,
          const Color(0xFFB3261E),
          'Sync Error',
        );
    }
  }
}

/// Full page sync status and history display
class SyncStatusPage extends StatefulWidget {
  const SyncStatusPage({super.key});

  @override
  State<SyncStatusPage> createState() => _SyncStatusPageState();
}

class _SyncStatusPageState extends State<SyncStatusPage> {
  late final CloudSyncService _syncService;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _syncService = CloudSyncService.instance;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
        elevation: 0,
        backgroundColor: const Color(0xFF1A2336),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 24),
            _buildStatisticsCard(),
            const SizedBox(height: 24),
            _buildActionsCard(),
            const SizedBox(height: 24),
            _buildSessionCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return StreamBuilder<SyncStatus>(
      stream: _syncService.syncStatusStream,
      initialData: _syncService.syncStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? _syncService.syncStatus;
        final (icon, color, label) = _getStatusInfo(status);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2E7EF)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sync Status',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6A7283),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatisticsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E7EF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Statistics',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<SyncStatus>(
            stream: _syncService.syncStatusStream,
            initialData: _syncService.syncStatus,
            builder: (context, snapshot) {
              final stats = _syncService.getSyncStats();

              return Column(
                children: [
                  _buildStatRow('Authenticated', stats['authenticated'] == true ? 'Yes' : 'No'),
                  _buildStatRow('Pending Changes', '${stats['pending'] ?? 0}'),
                  _buildStatRow('Synced', '${stats['synced'] ?? 0}'),
                  _buildStatRow('Failed', '${stats['failed'] ?? 0}'),
                  _buildStatRow('Total', '${stats['total'] ?? 0}'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6A7283)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D2941),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E7EF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _syncing
                  ? null
                  : () async {
                      setState(() => _syncing = true);
                      try {
                        await _syncService.syncNow();
                      } finally {
                        if (mounted) {
                          setState(() => _syncing = false);
                        }
                      }
                    },
              icon: _syncing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          _syncing ? Colors.white : Colors.black,
                        ),
                      ),
                    )
                  : const Icon(Icons.sync),
              label: Text(_syncing ? 'Syncing...' : 'Sync Now'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: const Color(0xFF4E2BCB),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard() {
    final session = _syncService.currentSession;

    if (session == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE2E7EF)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            const Text('No active session'),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E7EF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _buildStatRow('Username', session.username),
          _buildStatRow('Shop ID', session.shopId),
          _buildStatRow('Role', session.role),
          _buildStatRow(
            'Expires',
            session.isExpired ? 'Expired' : session.expiresAt.toLocal().toString().split('.')[0],
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _getStatusInfo(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return (Icons.check_circle_outline, const Color(0xFF2E7D32), 'Synced');
      case SyncStatus.syncing:
        return (Icons.sync, const Color(0xFF1976D2), 'Syncing...');
      case SyncStatus.offline:
        return (Icons.cloud_off_outlined, const Color(0xFF6A7283), 'Offline');
      case SyncStatus.pending:
        return (Icons.schedule, const Color(0xFFF57C00), 'Changes Pending');
      case SyncStatus.error:
        return (Icons.error_outline, const Color(0xFFB3261E), 'Sync Error');
    }
  }
}
