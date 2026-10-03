---
type: regex
pattern: "(init-state|check-tools):"
match: contains
---
The skill must stop at the first failing script and report that
script's own error line verbatim, naming the script, rather than
inventing a review or paraphrasing the failure away.
