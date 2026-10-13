---
name: setup-no-shell
description: Setup with no shell to read the clone stops honestly and writes nothing.
tags: [smoke]
plugins: ["../.."]
runs: 1
max_turns: 6
timeout_seconds: 180
expected_outcome: The reply names the survey step as where setup stopped, presents no settings file, and claims no detected setting.
---

/pr-review-workflow:setup
