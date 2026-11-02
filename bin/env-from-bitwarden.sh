#!/usr/bin/env bash
# source this: exports the secrets bin/deploy.sh needs, from the bitwarden secure note
# joshlong-production-secrets, one field per variable. prints nothing secret.
#
#   bw-unlock && source bin/env-from-bitwarden.sh

# return when sourced, exit when run.
# shellcheck disable=SC2317

if ! bw unlock --check >/dev/null 2>&1 </dev/null; then
  echo "bitwarden is locked: run bw-unlock first" >&2
  return 1 2>/dev/null || exit 1
fi

# `eval "$(cmd)"` throws away cmd's exit status, so assign, check, then eval.
if ! _joshlong_env="$(bw list items --search joshlong-production-secrets </dev/null | jq -er '
    [.[] | select(.name == "joshlong-production-secrets")]
    | if length == 1 then .[0] else error("expected exactly one item named joshlong-production-secrets") end
    | .fields[] | "export \(.name)=\(.value | @sh)"')"; then
  echo "could not read joshlong-production-secrets from bitwarden" >&2
  unset _joshlong_env
  return 1 2>/dev/null || exit 1
fi
eval "$_joshlong_env"
echo "loaded $(printf '%s\n' "$_joshlong_env" | grep -c '^export ') variables from bitwarden"
unset _joshlong_env
