# joshlong-pipeline

Deploys joshlong.com's applications to Cloud Foundry from the container images built by their own repositories.
Today that is two apps:

- `joshlong-site` (from [`joshlong-site`](https://github.com/developer-advocacy/joshlong-site)), the Vue site at `https://joshlong.com`.
- `joshlong-api` (from [`joshlong-api`](https://github.com/developer-advocacy/joshlong-api)), the GraphQL API behind it at `https://api.joshlong.com`.

The foundation is the typical one from `~/code/application-concierge/cloudfoundry-platform-installer` (`api.cf.applicationconcierge.com`), and the apps live in the org `developer_advocacy`, space `production`.

## How a change gets deployed

1. A push to an app repository's `main` branch builds its container image and pushes it to `us-docker.pkg.dev/joshlong/developer-advocacy-artifact-registry/<app>:latest`.
2. That workflow then sends an `update-event` repository dispatch to this repository.
3. `.github/workflows/deploy-to-production.yaml` runs `bin/deploy.sh`, which pushes every app in `manifest.yml`.

The deploy workflow also runs on a push to this repository's `main` branch, and by hand.
Concurrent deploys queue, so a later build cannot overlap a deployment already in progress.

## Deploying by hand

```bash
cd ~/code/application-concierge/cloudfoundry-platform-installer && eval "$(./up.sh --env typical.env shell)"
cd ~/code/developer-advocacy/joshlong-pipeline
bw-unlock                          # for the api's secrets and the image pull key
source bin/env-from-bitwarden.sh
bin/deploy.sh                      # every app, or name some: bin/deploy.sh joshlong-api
```

`bin/deploy.sh` pins each app's `:latest` to its current digest, and runs `cf push --strategy rolling` for each app named, into the org and space the vars file names.
`--vars vars/<foundation>.yml` names another foundation.

## Files

| File | Holds |
|---|---|
| `manifest.yml` | every app; every value that differs by foundation, and every secret, is a `((var))` |
| `vars/typical.yml` | org, space, registry, domains and hosts for the typical foundation; no secrets |
| `bin/deploy.sh` | checks the secrets, resolves digests, targets the org and space, pushes |
| `bin/env-from-bitwarden.sh` | sourced, exports the api's secrets from the Bitwarden note `joshlong-production-secrets` |
| `bin/secrets-to-bitwarden.sh` | copied the api's secrets from GKE into that note, while GKE still had them |
| `.github/workflows/deploy-to-production.yaml` | the GitHub Actions deployment |

## Adding an app

1. Give the app's repository a workflow that builds `us-docker.pkg.dev/joshlong/developer-advocacy-artifact-registry/<app>:latest` and then sends the `update-event` dispatch, as `joshlong-site/.github/workflows/build-container.yaml` does.
2. Add the app to `manifest.yml`, with `image: ((registry))/<app>@((<app>-digest))`; `bin/deploy.sh` resolves the digest of every app in the manifest.
3. Add its hosts to `vars/typical.yml`.
   Add any secrets it needs to `SECRETS` in `bin/deploy.sh`, to the workflow's `env`, and to the Bitwarden note.

## Credentials

| Secret | On | Is | Kept in Bitwarden as |
|---|---|---|---|
| `CF_USERNAME`, `CF_PASSWORD` | this repository | the CF user `joshlong-pipeline`, SpaceDeveloper in `developer_advocacy` / `production` and nothing else | `joshlong-cf-pipeline-user` |
| `CF_DOCKER_PASSWORD` | this repository | a JSON key of the service account `joshlong-cf-puller@joshlong.iam.gserviceaccount.com`, which can only read `developer-advocacy-artifact-registry` | `joshlong-cf-image-puller-key` (notes) |
| `JOSHLONG_DB_HOST`, `JOSHLONG_DB_SCHEMA`, `JOSHLONG_DB_USERNAME`, `JOSHLONG_DB_PASSWORD` | the `developer-advocacy` org | the api's PostgreSQL, on Crunchy Bridge | `joshlong-production-secrets` (fields) |
| `BOOTIFUL_YOUTUBE_API_KEY`, `BOOTIFUL_PROMOTION_PLAYLIST_IDS` | the `developer-advocacy` org | the api's YouTube Data API key, and the playlists it promotes | `joshlong-production-secrets` (fields) |
| `BLOG_INDEX_REBUILD_KEY` | the `developer-advocacy` org | the key the content repository's webhook sends to make the api rebuild its index | `joshlong-production-secrets` (fields) |
| `GCLOUD_SA_KEY` | the `developer-advocacy` org | the account that pushes images, used here to read their digests | |
| `JOSHLONG_GITHUB_PERSONAL_ACCESS_TOKEN` | each app repository | a token that can send the dispatch to this repository | `mogul-github-pat` |

The images are private.
`cf push` gives the cell a pull credential: username `_json_key`, password the service account key.
Locally, `bin/deploy.sh` reads the key from Bitwarden, so the vault has to be unlocked; `CF_DOCKER_PASSWORD`, if set, takes precedence.
If the key is ever lost, make a new one (`gcloud iam service-accounts keys create`), save it to the same item and the Actions secret, and delete the old key.

`cf push` prints the manifest it applies, environment and all, so `bin/deploy.sh` filters that part of its output to keep the secrets out of logs.
