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
  `antipatterns`, `content-leakage`, or `outdated-docs`.
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

Evidence and the expected resolution, in plain prose. A body may end with a
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
title: One line naming the defect
---
Body of the finding.
```
