# GitHub App and 1Password Setup

This guide walks through a full `garth` GitHub App setup:

- create the GitHub App with the right permissions
- install it on the repos or owners you need
- store credentials in 1Password
- configure `~/.config/garth/config.toml`
- validate by minting a token

## Prerequisites

- `op` installed and signed in (`op whoami` succeeds)
- admin access to create/install a GitHub App for your target repos
- `garth` installed (`garth setup` should complete)

## 1. Create the GitHub App

Open:

- `https://github.com/settings/apps`

Recommended app metadata:

- App name: `<org-or-user>-garth` (example: `acme-garth`)
- Description:
  - `GitHub App for garth agent workspaces and short-lived installation tokens`
- Homepage URL:
  - your repo URL (for example, `https://github.com/ealt/garth`)

Create a new app with at least:

- Repository permissions:
  - `Contents`: Read and write
  - `Pull requests`: Read and write
  - `Issues`: Read and write
  - `Checks`: Read and write
  - `Metadata`: Read-only (default)
- User authorization:
  - `Expire user authorization tokens`: keep enabled
    (checked by default in GitHub UI)
- Webhooks:
  - disable unless you explicitly need webhook events

No account or organization permissions are required for basic `garth` token
minting.

### Where can this GitHub App be installed?

For `garth`, choose based on where your target repositories live:

- Personal repos only:
  - `Only this account` is fine.
- Personal + organization repos (or multiple orgs):
  - choose `Any account`.

If a personal-account-owned app is set to `Only this account`, it cannot be
installed on organization accounts.

Security note for `Any account`:

- `Any account` does not grant automatic repo access.
- Access still requires explicit installation and approval by the target account
  or organization owner.
- The main risk increase is blast radius if your app private key is compromised,
  because more installations could be affected.

Mitigations:

- keep permissions minimal
- keep `Expire user authorization tokens` enabled
- store app secrets in 1Password and rotate private keys regularly
- install only on accounts/repos you actually need

After creating the app:

1. Generate a private key and download the `.pem`.
2. Record the numeric **App ID** from the app settings page.
3. Optional but recommended: also record the **Client ID**.

## JWT details (`garth` handles this for you)

You do not need to hand-roll JWTs when using `garth`; it generates app JWTs and
installation tokens internally.

For troubleshooting and security review, `garth` follows GitHub's JWT guidance:

- `alg`: `RS256`
- `iat`: set slightly in the past to handle clock drift
- `exp`: set to no more than 10 minutes in the future
- `Authorization` header uses `Bearer` for JWT requests
- `iss` can be App ID or Client ID
  - current `garth` config key is `app_id_ref`
  - GitHub recommends using Client ID, but App ID is also supported

Official GitHub reference:

- <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app>

## 2. Install the App

Install the app on the owner/repositories that `garth` will access.

If you use `installation_strategy = "by_owner"` (the default), you usually do
not need to configure installation IDs manually.

If you use `single` or `static_map`, record the installation ID too.
You can read it from the installation URL, for example:

- `https://github.com/settings/installations/<INSTALLATION_ID>`
- `https://github.com/organizations/<ORG>/settings/installations/<INSTALLATION_ID>`

## 3. Store Credentials in 1Password

Create a 1Password item (for example, `GitHub App`) in your chosen vault.

Recommended field labels:

- `app-id` (text)
- `client-id` (text, optional)
- `private-key` (text or file/document)
- `installation-id` (text/number, optional for `by_owner`)

Useful discovery commands:

```bash
op vault list
op item list --vault "<VAULT>"
op item get "GitHub App" --vault "<VAULT>" --format json \
  | jq -r '.fields[] | [.label, .id, .type] | @tsv'
```

## 4. Configure `garth`

Edit `~/.config/garth/config.toml`.

### Recommended: `by_owner`

```toml
[github_app]
app_id_ref = "op://<VAULT>/GitHub App/app-id"
private_key_ref = "op://<VAULT>/GitHub App/private-key"
installation_strategy = "by_owner"
installation_id_ref = ""
installation_id_map = {}
```

### Single installation ID

Use this when all repos should use one known installation.

```toml
[github_app]
app_id_ref = "op://<VAULT>/GitHub App/app-id"
private_key_ref = "op://<VAULT>/GitHub App/private-key"
installation_strategy = "single"
installation_id_ref = "op://<VAULT>/GitHub App/installation-id"
installation_id_map = {}
```

### Static owner-to-installation map

Use this when different owners require different installation IDs.

```toml
[github_app]
app_id_ref = "op://<VAULT>/GitHub App/app-id"
private_key_ref = "op://<VAULT>/GitHub App/private-key"
installation_strategy = "static_map"
installation_id_ref = ""
installation_id_map = { "my-org" = "12345678", "my-user" = "87654321" }
```

Also set real API key refs under `[agents.*]` in the same config file.

## 5. Validate

From a repo that has a GitHub `origin` remote:

```bash
op whoami
garth token .
```

If token minting succeeds, your GitHub App and 1Password wiring is correct.

## Troubleshooting

- `"isn't a vault in this account"`:
  - The vault name in `op://...` does not exist in your account.
- `Cannot read app_id_ref/private_key_ref/...` during setup:
  - Vault, item, or field names in refs are wrong.
- `GitHub API request failed ... 404` for `/repos/<owner>/<repo>/installation`:
  - App is not installed for that repo/owner.
- `GitHub API request failed ... 403`:
  - App permissions are too narrow, or installation scope is wrong.
- Token minting fails after private key changes:
  - Generate a new private key in GitHub App settings and update
    `private_key_ref`.
