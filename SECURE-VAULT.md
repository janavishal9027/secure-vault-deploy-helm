# secure-vault — operations

Centralized deploy for the secure-vault platform across 5 envs:
`dev-a`, `dev-b`, `test`, `stage`, `prod`. Each env runs k3s inside its
own LXD container on a shared VPS.

## Services in scope

| Repo                                      | What it builds                          |
|-------------------------------------------|-----------------------------------------|
| `Digital_Notes_Backend/Authentication`    | Spring Boot JAR → Docker image          |
| `Digital_Notes_Backend/roles`             | Spring Boot JAR → Docker image          |
| `Digital_Notes_Backend/notes`             | Spring Boot JAR → Docker image          |
| `Digital_Notes_Backend/ai-core-service`   | FastAPI → Docker image                  |
| `Digital_Notes_Backend/ai-worker`         | FastAPI → Docker image                  |
| `Digital_Notes_Frontend/secure-vault`     | Vite SPA → nginx Docker image           |
| `secure-vault-deploy-helm` (this repo)    | Chart + per-env values + deploy scripts |

## Cluster topology

| Env    | LXD container         | Bridge IP        |
|--------|-----------------------|------------------|
| dev-a  | secure-vault-dev-a    | 10.86.216.71     |
| dev-b  | secure-vault-dev-b    | 10.86.216.190    |
| test   | secure-vault-test     | 10.86.216.57     |
| stage  | secure-vault-stage    | 10.86.216.217    |
| prod   | secure-vault-prod     | 10.86.216.180    |

The bridge IP is the LXD container's address on `lxdbr0`. It's both the
proxy_pass target of the host nginx server block AND the host the
in-cluster pods use to reach the host-network Postgres / Kafka (since
those run on the LXD host itself, not in k3s).

## Cluster bootstrap (one time per env)

### 1. Install Helm inside each container

```bash
for env in dev-a dev-b test stage prod; do
  lxc exec secure-vault-$env -- bash -c \
    'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
done
```

### 2. Fill in the secrets

Every env's `_namespace_values.yaml` ships with `REPLACE_WITH_*`
placeholders under `secrets:`. Replace them before the first deploy.

```yaml
# secure-vault-helmchart/envs/dev-a/_namespace_values.yaml
secrets:
  secure-vault-db:
    password: <env-specific postgres password>
  secure-vault-jwt:
    secret: <base64 HMAC, identical across all 4 JWT-validating services>
  secure-vault-internal:
    roleServiceKey: <shared secret: auth ↔ roles>
    delegateBootstrapKey: <first-admin bootstrap key>
  secure-vault-oauth:
    githubClientId / githubClientSecret
    googleClientId / googleClientSecret
  secure-vault-mail:
    username / password   # Gmail SMTP app-password
  secure-vault-ai:
    geminiApiKey
    openaiApiKey
```

Critical: the JWT secret MUST match across `authentication-service`,
`notes-service`, `roles-service`, and `ai-core-service` — they all
validate user tokens against the same key. Each env still gets its own
distinct JWT secret; only the *services within one env* share it.

> **WARNING — plaintext in git.** Interim only. Migrate to External
> Secrets Operator + Vault before opening the repo or before any
> compliance review.

## Per-deploy flow

Each app repo's pipeline builds an image, pushes to Docker Hub, then
updates `image-versions/<env>_image.yaml` here, commits, and triggers
the matching custom pipeline. See each app repo's
`bitbucket-pipelines.yml` (they all consume `ci/deploy.sh` here).

## Routing

Traefik routes by longest-prefix match:

- `/authentication/*` → authentication-service (Spring context-path)
- `/roles/*` → roles-service (Spring context-path)
- `/notes/*` → notes-service (Spring context-path)
- `/ai-core/*` → ai-core-service (StripPrefix middleware removes `/ai-core`)
- `/ai-worker/*` → ai-worker-service (StripPrefix middleware removes `/ai-worker`)
- `/*` → secure-vault-ui (catch-all)

The two FastAPI services need `stripPrefix: true` in their values
because their routers are mounted at the root (e.g. `/embed`,
`/summarize`) and don't know about the prefix.

## Limits / open items

- The deploy script assumes `helm` is installed inside the LXD container.
  Bootstrap once per env (see step 1).
- Postgres + Kafka run on the LXD host (not in k3s). Pods reach them via
  the container's bridge IP (`lxd.bridgeIp` in each env's namespace
  values).
- For prod, consider removing the `/roles` ingress path so roles-service
  is reachable only internally via cluster DNS. Comment out the
  `ingress` block in `prod/roles-service_values.yaml`.
