class Stats {
  int zones = 0,
      battles = 0,
      warriors = 0,
      warriorPerks = 0,
      complexRules = 0,
      equipItems = 0,
      rulePerks = 0,
      currencies = 0,
      conditions = 0,
      quests = 0,
      dojos = 0,
      includes = 0;
}

class DiagnosticsResult {
  final List<String> errors;
  final List<String> warnings;
  final Stats stats;

  DiagnosticsResult(this.errors, this.warnings, this.stats);
}
