# secure-vault-helmchart

Umbrella Helm chart for the secure-vault platform. One chart renders all
six services (auth, account, transaction, bill-payment, card, ui) — the
shape of each comes from per-environment values files under `envs/<env>/`.

## Layout

```
secure-vault-helmchart/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── secret.yaml
│   ├── _helpers.tpl
│   └── NOTES.txt
└── envs/
    ├── dev-a/   _namespace_values.yaml + per-service values
    ├── dev-b/
    ├── test/
    ├── stage/
    └── prod/
```

Image tags are NOT pinned in the env values — they live in
`../image-versions/<env>_image.yaml` and are loaded as the *last* `-f`
argument so they win.

## Render locally

```bash
helm template secure-vault ./secure-vault-helmchart \
  -f ./secure-vault-helmchart/envs/dev-a/_namespace_values.yaml \
  -f ./secure-vault-helmchart/envs/dev-a/auth-service_values.yaml \
  -f ./secure-vault-helmchart/envs/dev-a/account-service_values.yaml \
  -f ./secure-vault-helmchart/envs/dev-a/transaction-service_values.yaml \
  -f ./secure-vault-helmchart/envs/dev-a/bill-payment-service_values.yaml \
  -f ./secure-vault-helmchart/envs/dev-a/card-service_values.yaml \
  -f ./secure-vault-helmchart/envs/dev-a/ui_values.yaml \
  -f ./image-versions/dev-a_image.yaml
```
