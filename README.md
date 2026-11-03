# joshlong-pipeline

Deploys joshlong.com's applications to Cloud Foundry from the container images built by their own repositories.
Today that is two apps:

- `joshlong-site` (from [`joshlong-site`](https://github.com/developer-advocacy/joshlong-site)), the Nuxt site at `https://joshlong.com`, rendered on the server.
- `joshlong-api` (from [`joshlong-api`](https://github.com/developer-advocacy/joshlong-api)), the GraphQL API behind it at `https://api.joshlong.com`.

The foundation is mypaas, from `~/code/application-concierge/bosh-platform-installer` (`mypaas.env`, `api.cf.mypaas.online`), and the apps live in the org `developer-advocacy`, space `production`.

## How a change gets deployed

1. A push to an app repository's `main` branch builds its container image and pushes it to `us-docker.pkg.dev/joshlong/developer-advocacy-artifact-registry/<app>:latest`.
2. That workflow then sends an `update-event` repository dispatch to this repository.
3. `.github/workflows/deploy-to-production.yaml` runs `bin/deploy.sh` with the vars file its `VARS_FILE` names, `vars/mypaas.yml`, which also holds the foundation's API (`cf-api`), and pushes every app in `manifest.yml`.

The deploy workflow also runs on a push to this repository's `main` branch, and by hand.
Concurrent deploys queue, so a later build cannot overlap a deployment already in progress.

## Deploying by hand

```bash
cf login -a https://api.cf.mypaas.online -u josh
cd ~/code/developer-advocacy/joshlong-pipeline
bw-unlock                          # for the api's secrets and the image pull key
source bin/env-from-bitwarden.sh
bin/deploy.sh                      # every app, or name some: bin/deploy.sh joshlong-api
```

`bin/deploy.sh` pins each app's `:latest` to its current digest, and runs `cf push --strategy rolling` for each app named, into the org and space the vars file names.
`vars/mypaas.yml` is the default; `--vars vars/<foundation>.yml` names another.

## Files

| File | Holds |
|---|---|
| `manifest.yml` | every app; every value that differs by foundation, and every secret, is a `((var))` |
| `vars/mypaas.yml` | the foundation's API, and the org, space, registry, domains and hosts, for mypaas; no secrets |
| `bin/deploy.sh` | checks the secrets, resolves digests, targets the org and space, pushes |
| `bin/env-from-bitwarden.sh` | sourced, exports the api's secrets from the Bitwarden note `joshlong-production-secrets` |
| `.github/workflows/deploy-to-production.yaml` | the GitHub Actions deployment |

## Adding an app

1. Give the app's repository a workflow that builds `us-docker.pkg.dev/joshlong/developer-advocacy-artifact-registry/<app>:latest` and then sends the `update-event` dispatch, as `joshlong-site/.github/workflows/build-container.yaml` does.
2. Add the app to `manifest.yml`, with `image: ((registry))/<app>@((<app>-digest))`; `bin/deploy.sh` resolves the digest of every app in the manifest.
3. Add its hosts to `vars/mypaas.yml`.
   Add any secrets it needs to `SECRETS` in `bin/deploy.sh`, to the workflow's `env`, and to the Bitwarden note.

## Credentials

| Secret | On | Is | Kept in Bitwarden as |
|---|---|---|---|
| `CF_USERNAME`, `CF_PASSWORD` | this repository | the CF user `josh` on mypaas, OrgManager of `developer-advocacy` and SpaceDeveloper in `developer-advocacy` / `production` | |
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

## DNS

`joshlong.com` is registered at Gandi, and its DNS is hosted by Gandi LiveDNS.
It is a private domain of the `developer-advocacy` org on mypaas.
Its certificate (Certificate Manager, on the foundation's load balancer) and its `A` records for `joshlong.com`, `www` and `api` were set up with the installer's `app-domain.sh`, once per app:

```bash
cd ~/code/application-concierge/bosh-platform-installer
GANDI_PAT=... ./app-domain.sh --env mypaas.env --org developer-advocacy --space production --app joshlong-site joshlong.com
GANDI_PAT=... ./app-domain.sh --env mypaas.env --org developer-advocacy --space production --app joshlong-api --hostname api joshlong.com
```

Records other than the platform's own `A` records, such as `MX` or `TXT`, go in Gandi LiveDNS.
