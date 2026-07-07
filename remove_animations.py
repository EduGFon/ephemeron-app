import os
import re

files_with_animations = [
    "lib/features/calendar/presentation/calendar_screen.dart",
    "lib/features/countdown/presentation/countdown_screen.dart",
    "lib/features/habits/presentation/habits_screen.dart",
    "lib/features/tasks/presentation/tasks_screen.dart",
    "lib/features/focus/presentation/focus_screen.dart",
    "lib/presentation/shell/app_shell.dart",
    "lib/presentation/notes/notes_screen.dart"
]

for path in files_with_animations:
    full_path = os.path.join("/home/edu/p/ephemeron", path)
    with open(full_path, "r") as f:
        content = f.read()
    
    # We want to remove .animate().fadeIn(...) and .animate().scale(...) etc
    # This regex matches .animate() followed by any number of chained method calls like .fadeIn() up to the end of the statement or before the next token
    # A safer approach is to just remove .animate().fadeIn(duration: 400.ms) 
    content = re.sub(r'\.animate\(\)\.fadeIn\([^)]*\)', '', content)
    content = re.sub(r'\.animate\(\)\.scale\([^)]*\)', '', content)
    content = re.sub(r'\.animate\(\)\.fade\([^)]*\)', '', content)
    content = re.sub(r'\.animate\(\)\.slide\([^)]*\)', '', content)
    content = re.sub(r'\.animate\(\)\.fadeIn\(\)', '', content)
    content = re.sub(r'\.animate\(\)\.fade\(\)', '', content)
    content = re.sub(r'\.animate\(\)', '', content)
    
    with open(full_path, "w") as f:
        f.write(content)
        print(f"Updated {path}")
