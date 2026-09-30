---
name: bad-argument
tags: [smoke]
plugins: ["../.."]
runs: 1
max_turns: 6
timeout_seconds: 180
allowed_tools: ["Bash"]
---

/pr-review-workflow:review-pr %%%
