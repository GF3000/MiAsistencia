import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/team_membership.dart';
import '../models/team_session.dart';
import '../models/player_motivation.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../utils/attendance_csv.dart';
import '../utils/file_download.dart';
import 'app_widgets.dart';
import 'player_attendance_profile_dialog.dart';

class PlayerAttendanceOverview extends ConsumerStatefulWidget {
  const PlayerAttendanceOverview({
    required this.teamId,
    required this.completedSessions,
    super.key,
  });

  final String teamId;
  final List<TeamSession> completedSessions;

  @override
  ConsumerState<PlayerAttendanceOverview> createState() =>
      _PlayerAttendanceOverviewState();
}

class _PlayerAttendanceOverviewState
    extends ConsumerState<PlayerAttendanceOverview> {
  late Stream<List<TeamRosterMember>> _membersStream;
  late Stream<AttendanceHistorySnapshot> _attendanceStream;
  late int _sessionsSignature;

  @override
  void initState() {
    super.initState();
    _configureStreams();
  }

  @override
  void didUpdateWidget(PlayerAttendanceOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = Object.hashAll(
      widget.completedSessions.map((session) => session.id),
    );
    if (oldWidget.teamId != widget.teamId ||
        nextSignature != _sessionsSignature) {
      _configureStreams();
    }
  }

  void _configureStreams() {
    _sessionsSignature = Object.hashAll(
      widget.completedSessions.map((session) => session.id),
    );
    _membersStream = ref
        .read(teamRepositoryProvider)
        .watchTeamMembers(widget.teamId);
    _attendanceStream = ref
        .read(attendanceRepositoryProvider)
        .watchAttendanceForSessions(
          widget.completedSessions.map((session) => session.id),
        );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.completedSessions.isEmpty) {
      return const EmptyState(
        icon: Icons.query_stats_outlined,
        title: 'Todavía no hay estadísticas',
        message: 'Los datos aparecerán cuando termine la primera sesión.',
      );
    }

    return StreamBuilder<List<TeamRosterMember>>(
      stream: _membersStream,
      builder: (context, membersSnapshot) {
        if (membersSnapshot.hasError) {
          return const EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'No se pudo cargar la plantilla',
            message: 'Comprueba tu conexión e inténtalo de nuevo.',
          );
        }
        if (!membersSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final players = membersSnapshot.data!
            .where((member) => member.role == UserRole.player)
            .toList();
        if (players.isEmpty) {
          return const EmptyState(
            icon: Icons.group_off_outlined,
            title: 'No hay jugadores',
            message: 'Añade jugadores al equipo para ver sus estadísticas.',
          );
        }

        return StreamBuilder<AttendanceHistorySnapshot>(
          stream: _attendanceStream,
          builder: (context, attendanceSnapshot) {
            if (attendanceSnapshot.hasError) {
              return const EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'No se pudieron cargar las asistencias',
                message: 'Comprueba tu conexión e inténtalo de nuevo.',
              );
            }
            if (!attendanceSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final history = attendanceSnapshot.data!;
            final attendance = history.attendanceBySession;
            final loadedSessions = widget.completedSessions
                .where(
                  (session) => history.loadedSessionIds.contains(session.id),
                )
                .toList();
            final rows = [
              for (final player in players)
                PlayerAttendanceTableRow(
                  player: player,
                  stats: buildPlayerAttendanceStats(
                    player: player,
                    sessions: loadedSessions,
                    attendanceBySession: attendance,
                  ),
                ),
            ];
            return PlayerAttendanceTable(
              rows: rows,
              completedSessions: loadedSessions,
              attendanceBySession: attendance,
              loadedSessionCount: history.loadedSessionIds.length,
              totalSessionCount: history.totalSessionCount,
            );
          },
        );
      },
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
    required this.loadedSessionCount,
    required this.totalSessionCount,
    this.completedSessions = const [],
    this.attendanceBySession = const {},
    this.downloadFile = downloadTextFile,
    super.key,
  });

  final List<PlayerAttendanceTableRow> rows;
  final int loadedSessionCount;
  final int totalSessionCount;
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

  @override
  Widget build(BuildContext context) {
    final sortedRows = _sortedRows();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final searchWidth = constraints.maxWidth < 220
                    ? constraints.maxWidth
                    : 220.0;

                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Histórico del equipo',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.loadedSessionCount ==
                                      widget.totalSessionCount
                                  ? '${widget.totalSessionCount} sesiones finalizadas'
                                  : 'Cargando historial: ${widget.loadedSessionCount} '
                                        'de ${widget.totalSessionCount} sesiones',
                              style: TextStyle(color: Colors.blueGrey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(
                      width: searchWidth,
                      child: TextField(
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
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                ),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    PopupMenuButton<_AttendanceCsvExport>(
                      key: const ValueKey('attendance-csv-menu'),
                      enabled:
                          widget.rows.isNotEmpty &&
                          widget.loadedSessionCount == widget.totalSessionCount,
                      tooltip:
                          widget.loadedSessionCount == widget.totalSessionCount
                          ? 'Descargar CSV'
                          : 'Espera a que termine de cargar el historial',
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
                    ),
                  ],
                );
              },
            ),
          ),
          if (widget.loadedSessionCount != widget.totalSessionCount)
            LinearProgressIndicator(
              value: widget.totalSessionCount == 0
                  ? null
                  : widget.loadedSessionCount / widget.totalSessionCount,
              minHeight: 3,
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
                    '"$_searchQuery".',
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
                          onSelectChanged: (_) => _showPlayerProfile(row),
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

  void _showPlayerProfile(PlayerAttendanceTableRow row) {
    final kpis = buildPlayerMotivationKpis(
      currentPlayer: row.player,
      members: widget.rows.map((item) => item.player),
      completedSessions: widget.completedSessions,
      attendanceBySession: widget.attendanceBySession,
      referenceDate: DateTime.now(),
    );

    showDialog<void>(
      context: context,
      builder: (context) {
        return PlayerAttendanceProfileDialog(
          player: row.player,
          stats: row.stats,
          kpis: kpis,
          completedSessions: widget.completedSessions,
          attendanceBySession: widget.attendanceBySession,
        );
      },
    );
  }

  void _downloadCsv(_AttendanceCsvExport export) {
    if (widget.loadedSessionCount != widget.totalSessionCount ||
        widget.rows.isEmpty) {
      return;
    }
    final date = _fileDate(DateTime.now());
    switch (export) {
      case _AttendanceCsvExport.players:
        final sortedRows = _sortedRows();
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
    final query = _normalizeSearchText(_searchQuery.trim());

    if (query.isEmpty) {
      return [...widget.rows];
    }

    return widget.rows.where((row) {
      final normalizedName = _normalizeSearchText(row.player.fullName);
      return normalizedName.contains(query);
    }).toList();
  }

  List<PlayerAttendanceTableRow> _sortedRows() {
    final sorted = _filteredRows();
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

String _normalizeSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[áàäâã]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöôõ]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u');
}
