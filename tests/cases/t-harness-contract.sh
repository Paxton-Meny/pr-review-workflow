#!/bin/sh
# Prove the harness contract: REPO_ROOT and SCRATCH are set, SCRATCH is writable.
set -eu

[ -n "${REPO_ROOT:?REPO_ROOT unset}" ]
[ -n "${SCRATCH:?SCRATCH unset}" ]
[ -d "$REPO_ROOT/scripts" ]
printf 'probe\n' >"$SCRATCH/probe"
[ "$(cat "$SCRATCH/probe")" = "probe" ]
