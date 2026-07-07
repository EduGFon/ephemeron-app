import os

files_with_backdrop = [
    "lib/features/calendar/presentation/calendar_screen.dart",
    "lib/features/calendar/presentation/event_form_sheet.dart",
    "lib/features/countdown/presentation/countdown_form_sheet.dart",
    "lib/features/countdown/presentation/countdown_screen.dart",
    "lib/features/countdown/presentation/countdown_template_picker.dart",
    "lib/features/focus/presentation/focus_screen.dart",
    "lib/features/habits/presentation/habit_form_sheet.dart",
    "lib/features/habits/presentation/habits_screen.dart",
    "lib/features/matrix/presentation/matrix_screen.dart",
    "lib/features/tasks/presentation/task_form_sheet.dart",
    "lib/features/tasks/presentation/tasks_screen.dart",
    "lib/presentation/notes/note_form_sheet.dart",
    "lib/presentation/shell/app_shell.dart"
]

import_statement = "import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';\n"

for path in files_with_backdrop:
    full_path = os.path.join("/home/edu/p/ephemeron", path)
    with open(full_path, "r") as f:
        content = f.read()
    
    if "BackdropFilter" in content:
        content = content.replace("BackdropFilter(", "GlassmorphicWrapper(")
        
        if import_statement.strip() not in content:
            lines = content.split('\n')
            last_import_idx = -1
            for i, line in enumerate(lines):
                if line.startswith("import "):
                    last_import_idx = i
            
            if last_import_idx != -1:
                lines.insert(last_import_idx + 1, import_statement.strip())
                content = '\n'.join(lines)
        
        with open(full_path, "w") as f:
            f.write(content)
            print(f"Updated {path}")
