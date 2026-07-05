import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

enum MatrixQuadrant {
  doFirst,
  schedule,
  delegate,
  eliminate;

  String get label {
    switch (this) {
      case MatrixQuadrant.doFirst:
        return 'Do First';
      case MatrixQuadrant.schedule:
        return 'Schedule';
      case MatrixQuadrant.delegate:
        return 'Delegate';
      case MatrixQuadrant.eliminate:
        return 'Eliminate';
    }
  }

  String get description {
    switch (this) {
      case MatrixQuadrant.doFirst:
        return 'Urgent & Important';
      case MatrixQuadrant.schedule:
        return 'Important, Not Urgent';
      case MatrixQuadrant.delegate:
        return 'Urgent, Not Important';
      case MatrixQuadrant.eliminate:
        return 'Not Urgent, Not Important';
    }
  }

  Color get color {
    switch (this) {
      case MatrixQuadrant.doFirst:
        return AppColors.priorityHigh; // e.g. Red/Orange
      case MatrixQuadrant.schedule:
        return AppColors.priorityMedium; // e.g. Blue
      case MatrixQuadrant.delegate:
        return AppColors.priorityLow; // e.g. Yellow
      case MatrixQuadrant.eliminate:
        return AppColors.priorityNone; // e.g. Grey
    }
  }
}
