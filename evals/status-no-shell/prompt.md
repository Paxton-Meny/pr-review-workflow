---
name: status-no-shell
description: Status with no shell to read the ledger stops honestly and reports no runs.
tags: [smoke]
plugins: ["../.."]
runs: 1
max_turns: 6
timeout_seconds: 180
expected_outcome: The reply names the run listing as where status stopped and reports no run, statistic, or setting as if read.
---

/pr-review-workflow:status
