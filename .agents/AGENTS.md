# Project Rules

- **Save Tokens**: Keep all conversations, prompts, and context extremely
  concise and token-efficient.
- **Test Code**: Run `flutter analyze` and fix any issue before finishing the
  interaction.
- **No Planning/Walkthroughs**: Do not write implementation plans
  (`implementation_plan.md`) or walkthroughs (`walkthrough.md`), just say what
  you gonna do and what questions you got.
- **Avoid Verbosity**: Do not state what you are going to do before doing it;
  only describe what you did after finishing the task. Do not output useless or
  unnecessary phrases (e.g., "I will wait until this task ends" or verbose
  transitional talk). Keep responses direct.
- **Conventional Commit Suggestion**: After making any code changes, output a
  conventional commit message. Write the message _only_; do not run `git add` or
  `git commit` commands.
- **Cross-Platform**: Every code wrote must be thought and reasoned to work
  across all supported devices. Supported devices: Android (Max priority),
  Linux and Web (Medium priority), Windows (Low priority).
- **Efficiency**: Every solution built must be highly efficient on battery (use
  as less battery as possible) and the app must be as much smoother and
  lightweight as possible.
