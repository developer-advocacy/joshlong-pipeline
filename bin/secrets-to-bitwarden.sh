#!/usr/bin/env bash
# copies the api's production secrets, joshlong-api-secrets on the GKE cluster joshlong, into the
# bitwarden secure note joshlong-production-secrets (folder developer-advocacy), one hidden field
# per variable bin/deploy.sh reads, then reads the note back and checks it. creates the note, or
# replaces its fields. prints nothing secret. only works while the GKE deployment exists: it's the
# copy before it goes.
#
#   bw-unlock && bin/secrets-to-bitwarden.sh

set -euo pipefail

ITEM=joshlong-production-secrets
FOLDER=developer-advocacy

bw unlock --check >/dev/null 2>&1 </dev/null || { echo "bitwarden is locked: run bw-unlock first" >&2; exit 1; }
bw sync >/dev/null

kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
KUBECONFIG="$kubeconfig" gcloud container clusters get-credentials joshlong \
  --region us-east4 --project joshlong >/dev/null 2>&1 || { echo "could not reach the GKE cluster" >&2; exit 1; }
# {name: value}, decoded, in bin/deploy.sh's names: the jdbc url splits into host and schema, the
# way the organization secrets JOSHLONG_DB_HOST and JOSHLONG_DB_SCHEMA hold it.
secrets="$(KUBECONFIG="$kubeconfig" kubectl -n developer-advocacy get secret joshlong-api-secrets -o json |
  jq -ce '.data | map_values(@base64d)
    | (.SPRING_DATASOURCE_URL | ltrimstr("jdbc:postgresql://") | split("/")) as $u
    | if ($u | length) != 2 then error("unexpected SPRING_DATASOURCE_URL") else . end
    | {JOSHLONG_DB_HOST: $u[0], JOSHLONG_DB_SCHEMA: $u[1],
       JOSHLONG_DB_USERNAME: .SPRING_DATASOURCE_USERNAME, JOSHLONG_DB_PASSWORD: .SPRING_DATASOURCE_PASSWORD,
       BOOTIFUL_YOUTUBE_API_KEY, BOOTIFUL_PROMOTION_PLAYLIST_IDS, BLOG_INDEX_REBUILD_KEY}
    | if any(.[]; . == null or . == "") then error("an empty secret") else . end')"
fields="$(jq -c 'to_entries | sort_by(.key) | map({name: .key, value: .value, type: 1})' <<<"$secrets")"

folder="$(bw list folders | jq -r --arg n "$FOLDER" '[.[] | select(.name == $n)] | if length == 1 then .[0].id else empty end')"
[ -n "$folder" ] || { echo "bitwarden: expected exactly one folder named $FOLDER" >&2; exit 1; }
id="$(bw list items --folderid "$folder" | jq -r --arg n "$ITEM" '[.[] | select(.name == $n)] |
  if length > 1 then error("more than one item named " + $n) else .[0].id // empty end')"

if [ -n "$id" ]; then
  bw get item "$id" | jq --argjson f "$fields" '.fields = $f' | bw encode | bw edit item "$id" >/dev/null
  echo "updated $ITEM"
else
  jq -n --arg name "$ITEM" --arg folder "$folder" --argjson f "$fields" \
    '{type: 2, secureNote: {type: 0}, name: $name, folderId: $folder,
      notes: "joshlong-api production secrets, one field per variable. source bin/env-from-bitwarden.sh in developer-advocacy/joshlong-pipeline.",
      fields: $f}' | bw encode | bw create item >/dev/null
  echo "created $ITEM"
fi

# read it back rather than trusting the write.
bw sync >/dev/null
stored="$(bw list items --folderid "$folder" | jq -c --arg n "$ITEM" \
  'first(.[] | select(.name == $n)) | [.fields[] | {(.name): .value}] | add')"
[ "$(jq -cS . <<<"$stored")" = "$(jq -cS . <<<"$secrets")" ] || { echo "MISMATCH: $ITEM differs from joshlong-api-secrets" >&2; exit 1; }
echo "$ITEM: all $(jq length <<<"$secrets") variables read back and match joshlong-api-secrets"
