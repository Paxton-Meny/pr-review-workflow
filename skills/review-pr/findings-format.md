# Finding records

One file per finding under the state directory's `findings/`, named by id
(`F001`, `F002`, ...). A record is a header, a `---` line, and a body. The
header is machine-parsed; keep it exact. The body is free text shown on the
pull request.

## Header

Every key appears on its own line, in this order, even when its value is
empty:

```
id: F001
status: open
category: correctness
severity: major
path: src/thing.py
line: 42
end_line:
side: RIGHT
placement:
comment_id:
commit:
round: 1
reopens: 0
title: One line naming the defect
```

- `status`: `open`, `addressed`, `verified`, or `wont-fix`. Legal transitions:
  open to addressed, open to wont-fix, addressed to verified, addressed back
  to open (a reopen). Nothing leaves `verified` or `wont-fix`.
- `category`: `correctness`, `security`, `performance`, `best-practices`,
  `antipatterns`, `content-leakage`, `outdated-docs`, or `other` for a
  defect worth raising that fits no defined category.
- `severity`: `blocker`, `major`, `minor`, or `nit`.
- `path`, `line`, `side`: where the finding anchors, using the `R`/`L`
  numbers from the annotated diff. `side` is `RIGHT` for added and context
  lines, `LEFT` for deleted lines.
- `end_line`: set only for a multi-line finding; must be on the same side and
  greater than `line`, which then names the first line of the range.
- `placement`, `comment_id`, `commit`: filled by the posting and editing
  steps; empty when the reviewer writes the record.
- `round`: the review round that raised the finding.
- `reopens`: how many times verification has sent the finding back.

## Body

A body carries, in this order:

1. Evidence: what was observed, quoting only lines the diff shows.
2. One line starting `Fix: ` stating the recommended repair with its
   reasoning and the repair context the editor needs, so the fix requires
   no re-reading of the project's structure: name the paths, lines,
   existing helpers, callers, test locations, and conventions the fix
   touches ("Fix: return low on the underflow branch, mirroring the guard
   idiom at src/calc.py:12; the only callers are report() and cli(), and
   the test belongs in tests/test_calc.py beside test_total"). Required
   unless the body ends with a suggestion fence, where the fence is the
   fix; never more than one.
3. Exactly one line starting `Resolution: ` stating the checkable criterion
   the fix must satisfy. That line is the contract of the whole loop: the
   editor edits until it holds, and verification judges it and nothing
   else, so write it as a testable statement about the code ("Resolution:
   the loop sums each item once, and a test covers duplicate SKUs"), never
   as advice ("consider simplifying").
4. Optionally, one line starting `Criteria note: ` when the defect plainly
   belongs to its category but no listed criteria item names it, stating
   the missing item. These lines are collected per run so the criteria
   grow deliberately instead of by accident.

A finding you cannot write a Resolution line for is not a finding. The line
`=== finding` is reserved as the record separator: never write it inside a
body, including when quoting diff content that contains it (paraphrase
instead).

Later steps may append notes below the body: a reopen note stating what
still fails, or a wont-fix justification. Notes accumulate; nothing in a
body is ever rewritten. A body may end with a
```suggestion fence only when the replacement is small, mechanical, covers
exactly the commented lines, and has been proven; a finding without a patch
beats a patch that starts a review cycle.

## Reviewer output

The reviewer emits records with only `category`, `severity`, `path`, `line`,
optional `end_line`, `side`, and `title` in the header; ids, status, round,
and the bookkeeping fields are assigned when the records are saved. Records
are separated by a line reading `=== finding`:

```
=== finding
category: correctness
severity: major
path: src/thing.py
line: 42
side: RIGHT
title: Retry loop drops the final attempt's error
---
The `except` on the last attempt assigns `err` but the loop exits before
raising it, so callers see `None` instead of the failure.
Fix: raise `err` after the loop instead of falling through; the retry tests
live in tests/test_client.py, and test_retry_exhausted is the one to extend.
Resolution: the last attempt's exception propagates to the caller, and the
retry test asserts it.
```
