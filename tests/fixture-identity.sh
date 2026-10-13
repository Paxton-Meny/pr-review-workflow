#!/bin/sh
# Usage: . "$REPO_ROOT/tests/fixture-identity.sh" (sets fixture_owner and fixture_login)
fixture_name=$(git -C "$REPO_ROOT" config user.name || true)
fixture_email=$(git -C "$REPO_ROOT" config user.email || true)
[ -n "$fixture_name" ] && [ -n "$fixture_email" ] || {
	echo "fixture identity: set git config user.name and user.email for this clone first" >&2
	exit 1
}
fixture_owner=$(printf '%s' "$fixture_name" | tr -c 'A-Za-z0-9-' '-')
fixture_login=$fixture_owner
