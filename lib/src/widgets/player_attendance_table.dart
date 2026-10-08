import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/team_membership.dart';
import '../models/team_session.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../utils/attendance_csv.dart';
import '../utils/file_download.dart';
import '../utils/search_text.dart';
import 'app_widgets.dart';

class PlayerAttendanceOverview extends ConsumerWidget {
  const PlayerAttendanceOverview({
    required this.teamId,
    required this.completedSessions,
    super.key,
  });

  final String teamId;
  final List<TeamSession> completedSessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (completedSessions.isEmpty) {
      return const EmptyState(
        icon: Icons.query_stats_outlined,
        title: 'Todavía no hay estadísticas',
        message: 'Los datos aparecerán cuando termine la primera sesión.',
      );
    }

    final membersState = ref.watch(teamMembersProvider(teamId));
    final attendanceState = ref.watch(teamAttendanceIndexProvider(teamId));

    if (membersState.hasError || attendanceState.hasError) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar las estadísticas',
        message: 'Comprueba tu conexión e inténtalo de nuevo.',
      );
    }
    final members = membersState.value;
    final attendance = attendanceState.value;
    if (members == null || attendance == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final players = members
        .where((member) => member.role == UserRole.player)
        .toList();
    if (players.isEmpty) {
      return const EmptyState(
        icon: Icons.group_off_outlined,
        title: 'No hay jugadores',
        message: 'Añade jugadores al equipo para ver sus estadísticas.',
      );
    }

    final rows = [
      for (final player in players)
        PlayerAttendanceTableRow(
          player: player,
          stats: buildPlayerAttendanceStats(
            player: player,
            sessions: completedSessions,
            attendanceBySession: attendance,
          ),
        ),
    ];
    return PlayerAttendanceTable(
      rows: rows,
      completedSessions: completedSessions,
      attendanceBySession: attendance,
    );
  }
}

class PlayerAttendanceTableRow {
  const PlayerAttendanceTableRow({required this.player, required this.stats});

  final TeamRosterMember player;
  final PlayerAttendanceStats stats;
}

class PlayerAttendanceTable extends StatefulWidget {
  const PlayerAttendanceTable({
    required this.rows,
    this.completedSessions = const [],
    this.attendanceBySession = const {},
    this.downloadFile = downloadTextFile,
    super.key,
  });

  final List<PlayerAttendanceTableRow> rows;
  final List<TeamSession> completedSessions;
  final Map<String, Map<String, AttendanceRecord>> attendanceBySession;
  final void Function({required String fileName, required String content})
  downloadFile;

  @override
  State<PlayerAttendanceTable> createState() => _PlayerAttendanceTableState();
}

class _PlayerAttendanceTableState extends State<PlayerAttendanceTable> {
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _showSearch => widget.rows.length > playerSearchThreshold;

  String get _activeQuery => _showSearch ? _searchQuery.trim() : '';

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    final sortedRows = _sortRows(_filteredRows());
    final isFiltered = _activeQuery.isNotEmpty;
    final subtitle = isFiltered
        ? '${widget.completedSessions.length} sesiones finalizadas · '
              '${sortedRows.length} de ${widget.rows.length} jugadores'
        : '${widget.completedSessions.length} sesiones finalizadas';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final title = Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.analytics_outlined,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Histórico del equipo',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            key: const ValueKey('player-attendance-subtitle'),
                            style: TextStyle(color: Colors.blueGrey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final search = TextField(
                  key: const ValueKey('player-attendance-search'),
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar jugador',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSearch,
                          ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _searchQuery = value),
                );
                final download = _csvMenu();

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: title),
                          download,
                        ],
                      ),
                      if (_showSearch) ...[const SizedBox(height: 12), search],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    if (_showSearch) ...[
                      const SizedBox(width: 16),
                      SizedBox(width: 280, child: search),
                    ],
                    const SizedBox(width: 8),
                    download,
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          if (sortedRows.isEmpty && widget.rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off_outlined,
                    size: 40,
                    color: Colors.blueGrey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No se encontraron jugadores',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'No hay jugadores cuyo nombre coincida con '
                    '"$_activeQuery".',
                    style: TextStyle(color: Colors.blueGrey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  key: const ValueKey('player-attendance-table'),
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStatePropertyAll(
                    AppTheme.primary.withValues(alpha: 0.07),
                  ),
                  horizontalMargin: 20,
                  columnSpacing: 26,
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  columns: [
                    _sortableColumn(0, 'Jugador'),
                    _sortableColumn(1, 'Asistencia %', numeric: true),
                    _sortableColumn(2, 'Sesiones', numeric: true),
                    _sortableColumn(3, 'Asistencias', numeric: true),
                    _sortableColumn(4, 'Retrasos', numeric: true),
                    _sortableColumn(5, 'Físico', numeric: true),
                    _sortableColumn(6, 'Pista', numeric: true),
                    _sortableColumn(7, 'Faltas', numeric: true),
                    _sortableColumn(8, 'Lesiones', numeric: true),
                  ],
                  rows: sortedRows
                      .map(
                        (row) => DataRow(
                          key: ValueKey(
                            'player-attendance-row-${row.player.id}',
                          ),
                          onSelectChanged: (_) =>
                              context.push('/team/players/${row.player.id}'),
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Text(
                                  row.player.fullName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.navy,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            _percentageCell(row),
                            _numberCell(row.stats.sessionCount),
                            _numberCell(
                              row.stats.attendanceCount,
                              color: AppTheme.primary,
                            ),
                            _numberCell(
                              row.stats.lateCount,
                              color: const Color(0xFFB76505),
                            ),
                            _numberCell(
                              row.stats.physicalCount,
                              color: const Color(0xFF7650A8),
                            ),
                            _numberCell(
                              row.stats.courtCount,
                              color: const Color(0xFF2563A5),
                            ),
                            _numberCell(
                              row.stats.absenceCount,
                              color: const Color(0xFF5C6670),
                            ),
                            _numberCell(
                              row.stats.injuryCount,
                              color: const Color(0xFFC2413B),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Text(
              'Físico incluye asistencias, retrasos y solo físico. '
              'Pista incluye asistencias y solo pista. El porcentaje excluye '
              'lesiones, sesiones anteriores al alta del jugador y sesiones '
              'con presunción de no asistencia.',
              style: TextStyle(
                color: Colors.blueGrey.shade600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _csvMenu() {
    return PopupMenuButton<_AttendanceCsvExport>(
      key: const ValueKey('attendance-csv-menu'),
      enabled: widget.rows.isNotEmpty,
      tooltip: 'Descargar CSV',
      icon: const Icon(Icons.download_outlined),
      onSelected: _downloadCsv,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _AttendanceCsvExport.players,
          child: ListTile(
            leading: Icon(Icons.people_outline),
            title: Text('Descargar por jugadores'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _AttendanceCsvExport.sessions,
          child: ListTile(
            leading: Icon(Icons.event_note_outlined),
            title: Text('Descargar por sesión'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  void _downloadCsv(_AttendanceCsvExport export) {
    if (widget.rows.isEmpty) {
      return;
    }
    final date = _fileDate(DateTime.now());
    switch (export) {
      case _AttendanceCsvExport.players:
        // The search only narrows the view; the export always has everyone.
        final sortedRows = _sortRows(widget.rows);
        widget.downloadFile(
          fileName: 'asistencia-por-jugadores-$date.csv',
          content: buildPlayerAttendanceCsv(
            sortedRows.map(
              (row) => (playerName: row.player.fullName, stats: row.stats),
            ),
          ),
        );
      case _AttendanceCsvExport.sessions:
        widget.downloadFile(
          fileName: 'asistencia-por-sesion-$date.csv',
          content: buildSessionAttendanceCsv(
            players: widget.rows.map((row) => row.player),
            sessions: widget.completedSessions,
            attendanceBySession: widget.attendanceBySession,
          ),
        );
    }
  }

  DataColumn _sortableColumn(int index, String label, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(label),
      onSort: (columnIndex, ascending) {
        setState(() {
          _sortColumnIndex = columnIndex;
          _sortAscending = ascending;
        });
      },
    );
  }

  List<PlayerAttendanceTableRow> _filteredRows() {
    final query = _activeQuery;
    return widget.rows
        .where((row) => matchesSearchQuery(row.player.fullName, query))
        .toList();
  }

  List<PlayerAttendanceTableRow> _sortRows(
    Iterable<PlayerAttendanceTableRow> rows,
  ) {
    final sorted = [...rows];
    sorted.sort((left, right) {
      if (_sortColumnIndex == 1) {
        final percentageComparison = _comparePercentages(
          left.stats.attendancePercentage,
          right.stats.attendancePercentage,
        );
        if (percentageComparison != 0) {
          return percentageComparison;
        }
        return left.player.fullName.toLowerCase().compareTo(
          right.player.fullName.toLowerCase(),
        );
      }
      final comparison = switch (_sortColumnIndex) {
        0 => left.player.fullName.toLowerCase().compareTo(
          right.player.fullName.toLowerCase(),
        ),
        2 => left.stats.sessionCount.compareTo(right.stats.sessionCount),
        3 => left.stats.attendanceCount.compareTo(right.stats.attendanceCount),
        4 => left.stats.lateCount.compareTo(right.stats.lateCount),
        5 => left.stats.physicalCount.compareTo(right.stats.physicalCount),
        6 => left.stats.courtCount.compareTo(right.stats.courtCount),
        7 => left.stats.absenceCount.compareTo(right.stats.absenceCount),
        8 => left.stats.injuryCount.compareTo(right.stats.injuryCount),
        _ => 0,
      };
      if (comparison != 0) {
        return _sortAscending ? comparison : -comparison;
      }
      return left.player.fullName.toLowerCase().compareTo(
        right.player.fullName.toLowerCase(),
      );
    });
    return sorted;
  }

  int _comparePercentages(int? left, int? right) {
    if (left == null) {
      return right == null ? 0 : 1;
    }
    if (right == null) {
      return -1;
    }
    return _sortAscending ? left.compareTo(right) : right.compareTo(left);
  }

  DataCell _percentageCell(PlayerAttendanceTableRow row) {
    final percentage = row.stats.attendancePercentage;
    return DataCell(
      Text(
        percentage == null ? '—' : '$percentage%',
        key: ValueKey('attendance-percentage-${row.player.id}'),
        style: const TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  DataCell _numberCell(int value, {Color? color}) {
    return DataCell(
      Text(
        '$value',
        style: TextStyle(
          color: color ?? AppTheme.navy,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _AttendanceCsvExport { players, sessions }

String _fileDate(DateTime value) {
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
}
