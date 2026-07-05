import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../application/matrix_providers.dart';
import '../domain/matrix_quadrant.dart';

class MatrixScreen extends ConsumerWidget {
  const MatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final isLoaded = ref.watch(allPendingTasksProvider).hasValue;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Eisenhower Matrix', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: !isLoaded
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _QuadrantWidget(quadrant: MatrixQuadrant.doFirst, palette: palette)),
                        const SizedBox(width: 16),
                        Expanded(child: _QuadrantWidget(quadrant: MatrixQuadrant.schedule, palette: palette)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _QuadrantWidget(quadrant: MatrixQuadrant.delegate, palette: palette)),
                        const SizedBox(width: 16),
                        Expanded(child: _QuadrantWidget(quadrant: MatrixQuadrant.eliminate, palette: palette)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _QuadrantWidget extends ConsumerStatefulWidget {
  const _QuadrantWidget({required this.quadrant, required this.palette});

  final MatrixQuadrant quadrant;
  final AppPalette palette;

  @override
  ConsumerState<_QuadrantWidget> createState() => _QuadrantWidgetState();
}

class _QuadrantWidgetState extends ConsumerState<_QuadrantWidget> {
  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(matrixTasksProvider(widget.quadrant));
    final color = widget.quadrant.color;

    return Container(
        decoration: BoxDecoration(
          color: widget.palette.surface.withValues(alpha: widget.palette.isAmoled ? 1.0 : 0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.quadrant.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${tasks.length}',
                          style: TextStyle(color: color, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.quadrant.description,
                    style: TextStyle(color: widget.palette.text.withValues(alpha: 0.6), fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: tasks.isEmpty
                        ? Center(
                            child: Icon(
                              Icons.task_alt,
                              color: color.withValues(alpha: 0.2),
                              size: 48,
                            ),
                          )
                        : ListView.builder(
                            itemCount: tasks.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        ref.read(taskRepositoryProvider).completeTask(task.id);
                                      },
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        margin: const EdgeInsets.only(top: 1, right: 8),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
                                          color: Colors.transparent,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => showTaskFormSheet(
                                          context,
                                          listId: task.listId,
                                          existingTask: task,
                                        ),
                                        child: Text(
                                          task.title,
                                          style: TextStyle(
                                            color: widget.palette.text,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
