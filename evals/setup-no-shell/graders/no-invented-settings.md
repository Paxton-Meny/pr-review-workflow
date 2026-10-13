---
type: regex
pattern: "(^|\\n)[ \\t#>`-]*(check_command|contract_commands|migration_paths|sensitive_paths|double_review|cost_posture|review_samples)[ \\t]+[^ \\t(]"
match: not_contains
---
Every setting setup writes comes from a script line. With no shell,
none ran, so a composed settings line, live or commented, is a value
invented from nothing: a check command no one confirmed, or migration
paths no evidence backs.
