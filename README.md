# DartStream Sample App

An end-to-end sample that proves **real users can sign up, sign in, and use the
live DartStream backend** across its auth, platform, experience, reactive, and
persistence services. It exists to exercise DartStream the way an actual client
does — not with mocks — so regressions in the deployed contracts show up
immediately.

> **Which environment is this?** Identity is the **`dartstream-prod` Firebase
> project** (the only issuer the backend trusts — see
> [below](#firebase-project-it-must-be-dartstream-prod)), but the DartStream
> services themselves are the SaaS **dev environment**:
> `DartStreamConfig.dev()` in the Flutter client and the
> `dev-api*.dartstream.io` defaults in `.env`. "Live" throughout this README
> means the deployed dev backend, not DartStream production.

It ships four artifacts:

1. **`bin/smoke.dart`** — a headless Dart CLI that hits all 10 endpoints and
   prints `PASS/FAIL`. Run this first to confirm the environment is healthy.
2. **`bin/auth_deepdive.dart`** — a headless Dart CLI that goes deep on the
   `ds-auth` service alone, exercising **every** auth endpoint (auth, users
   CRUD, sessions, avatar, status transitions, federated routes, providers) and
   printing a `PASS/FAIL/SKIP` table. Use it to verify the full auth surface,
   not just the happy path.
3. **`bin/platform_deepdive.dart`** — the same idea for `ds-platform-services`:
   feature-flags, projects (+ environments, integrations, orchestration),
   api-keys, settings, team, and the middleware/discovery sub-services. CRUD
   paths run as create → read → update → delete so they self-clean; outward ops
   (invitation emails, member-role changes) are gated behind
   `DEEPDIVE_DESTRUCTIVE=1`.
4. **`flutter_client/`** — a Flutter **web** app: a real Create-Account /
   Sign-In flow, a screen per DartStream service, and **DartStream Dash**, a
   [Flame](https://flame-engine.org) arcade game whose rules are driven by live
   DartStream services (feature flags, inventory, cloud-save, reactive events).

> **Which artifact is the customer reference?** The **Flutter client** — it
> consumes the first-party
> [`dartstream_client`](https://pub.dev/packages/dartstream_client) SDK exactly
> as a customer would. The `bin/` CLIs are **low-level contract probes**, not
> SDK examples: they deliberately hand-write the Firebase REST calls, raw
> `Authorization`/tenant headers, and service URLs with `package:http` so they
> can verify the deployed HTTP contracts independently of the SDK. Don't copy
> them into an app.

---

## Table of contents

- [How auth works (and why)](#how-auth-works-and-why)
- [Firebase project: it must be `dartstream-prod`](#firebase-project-it-must-be-dartstream-prod)
- [Project layout](#project-layout)
- [Prerequisites](#prerequisites)
- [Configuration & secrets](#configuration--secrets)
- [Running the smoke CLI](#running-the-smoke-cli)
- [Running the auth deep-dive](#running-the-auth-deep-dive)
- [Running the platform deep-dive](#running-the-platform-deep-dive)
- [Running the experience / reactive / persistence deep-dives](#running-the-experience--reactive--persistence-deep-dives)
- [Running the Flutter + Flame client](#running-the-flutter--flame-client)
- [Smoke CLI coverage](#smoke-cli-coverage)
- [Verified end-to-end](#verified-end-to-end-live-dev-environment-2026-06-10)
- [Known backend gaps & filed bugs](#known-backend-gaps--filed-bugs)
- [License](#license)

---

## How auth works (and why)

Both artifacts follow the same flow a real DartStream client uses:

```
            ┌─────────────────────────┐        idToken         ┌──────────────────────┐
 email +    │  Firebase Identity      │ ─────────────────────▶ │  DartStream backend  │
 password ─▶│  Toolkit (REST)         │   Bearer <idToken>     │  /api/v1/auth/...    │
            │  signUp / signInWith…   │                        │  verifies token,     │
            └─────────────────────────┘                        │  onboards tenant     │
              client / "user" role                             └──────────────────────┘
              (this sample, web SDK)                             server / "admin" role
                                                                 (firebase_dart_admin_auth_sdk)
```

1. The client authenticates against **Firebase Identity Toolkit** with the
   project's public **web API key** and gets a real Firebase **ID token**.
2. It sends that token (`Authorization: Bearer <idToken>`) to the DartStream
   backend, which **verifies** it and bootstraps the user + tenant.

### Why REST and not `firebase_dart_admin_auth_sdk`?

DartStream's backend uses
[`firebase_dart_admin_auth_sdk`](https://pub.dev/packages/firebase_dart_admin_auth_sdk)
to **verify** ID tokens server-side (in `ds-auth`). That package is a
*server/admin* SDK and is the wrong tool for a browser client because it:

- imports `dart:io`, so it **cannot compile for Flutter web**;
- does **not** list Web as a supported platform; and
- is initialized with privileged **workload-identity / service-account**
  credentials that must never ship inside a browser.

This sample plays the **user/client** role, so it authenticates the way a real
user does — hitting the same Identity Toolkit endpoints the official Firebase
web SDK (FlutterFire) calls under the hood. The resulting ID token is identical
and equally backend-trusted. That browser-safe auth (and every service call) is
handled by the first-party **[`dartstream_client`](https://pub.dev/packages/dartstream_client)**
SDK — the app no longer hand-writes a client; it consumes the SDK exactly as a
customer would (`DartStreamClient.signIn(...)` → typed `auth`/`platform`/
`experience`/`reactive`/`persistence` clients).

---

## Firebase project: it must be `dartstream-prod`

The backend only trusts ID tokens issued by the Firebase project it was
configured against: **`dartstream-prod`**.

Note the split: `dartstream-prod` names the **Firebase identity project only**,
not the DartStream environment this sample targets. The service calls go to the
SaaS **dev** hosts (`DartStreamConfig.dev()` /
`dev-api*.dartstream.io`) — swap `.dev()` for `.prod()` in
[`flutter_client/lib/config.dart`](flutter_client/lib/config.dart) (and the
`API_*` URLs in `.env`) to point the same app at production.

| Field | Value |
| --- | --- |
| Project ID | `dartstream-prod` |
| Auth domain | `dartstream-prod.firebaseapp.com` |
| Web app | `Sample-App-Brian-Chebon` |
| Web API key | injected at runtime (see below) |

> ⚠️ **Tokens from any other project are rejected.** A token minted by a
> different Firebase project (e.g. `intellitoggle-prod`) will authenticate fine
> *with Firebase* but the DartStream backend returns **HTTP 500** at
> `/api/v1/auth/signup` because it can't verify a foreign issuer. If signup
> starts 500-ing, check that your `FIREBASE_API_KEY` belongs to
> `dartstream-prod`.

---

## Project layout

```
.
├── bin/smoke.dart                 # headless E2E CLI across all 5 services
├── bin/auth_deepdive.dart         # deep-dive: full ds-auth surface
├── bin/platform_deepdive.dart     # deep-dive: ds-platform-services
├── bin/experience_deepdive.dart   # deep-dive: ds-experience-orchestration
├── bin/reactive_deepdive.dart     # deep-dive: ds-reactive-dataflow
├── bin/persistence_deepdive.dart  # deep-dive: ds-persistence
├── bin/oauth2_deepdive.dart       # deep-dive: OAuth2 client_credentials (machine-to-machine, no Firebase user)
├── .env.example                   # config template (placeholders only)
├── flutter_client/
│   └── lib/
│       ├── config.dart         # DartStreamConfig.dev(); API key from --dart-define
│       ├── state/session.dart       # holds the SDK's DartStreamConnection (auth state)
│       ├── screens/                 # each screen calls the SDK's typed clients
│       │   ├── login_screen.dart    # Create Account / Sign In toggle
│       │   └── home_screen.dart     # live service panels + game host
│       └── (auth + per-service clients come from the `dartstream_client` package)
│       └── game/dartstream_dash.dart # Flame arcade game (flags/inventory/cloud-save driven)
└── README.md
```

---

## Prerequisites

**Tracks the latest stable Flutter/Dart; minimum Dart `3.12.0`.** CI builds on the
`stable` channel (currently Flutter `3.44.1` / Dart `3.12.1` — last verified pair), so the
app follows stable as it moves. The constraint floor is Dart `>=3.12.0` (what the web
`flutter_client` needs): on an older toolchain `pub get` fails fast with a version-solve
message (e.g. Dart `3.11.4` → "requires SDK version `^3.12.0`") — a toolchain mismatch,
**not** a code defect, so upgrade Flutter rather than editing constraints.

- Flutter `3.44.0+` — use the latest stable (CI does); newer is fine
- Dart SDK `3.12.0+` (only needed standalone for the `bin/` CLIs; the Flutter-bundled one suffices)
- A Google Chrome install (the client runs on `-d chrome` / web-server)

---

## Configuration & secrets

Copy the template and fill in your local, gitignored `.env`:

```sh
cp .env.example .env
# set FIREBASE_API_KEY (Firebase console > Project settings > dartstream-prod web app)
# plus a test email/password.
set -a && source .env && set +a
```

`.env`:

| Variable | Purpose |
| --- | --- |
| `FIREBASE_API_KEY` | `dartstream-prod` **web** API key |
| `TEST_EMAIL` / `TEST_PASSWORD` | credentials the smoke CLI signs up / in with |
| `API_AUTH`, `API_PLATFORM`, `API_EXPERIENCE`, `API_REACTIVE`, `API_PERSISTENCE` | per-service base URLs (default to the `dev-api*.dartstream.io` hosts) |

### The API key is injected at runtime, never committed

- **Smoke CLI** reads `FIREBASE_API_KEY` from the environment.
- **Flutter client** reads it via `--dart-define=FIREBASE_API_KEY=…`
  (`String.fromEnvironment` in `config.dart`). If it's missing, the login
  screen shows a banner and disables sign-in instead of throwing an opaque
  Firebase error.

> **Note on the web API key:** A Firebase *web* API key is a public project
> identifier, not a secret — it ships inside every web app and is visible in the
> browser's network tab. You cannot hide it in a web client. Real protection
> comes from **API key restrictions** (HTTP-referrer allowlist + allowed APIs)
> in the Google Cloud console and **Firebase App Check**, not from hiding the
> value. We keep it out of the repo as hygiene; the deployed app still exposes
> it by nature. Tracked files (`config.dart`, `.env.example`) carry only
> placeholders — the real value lives solely in your gitignored `.env`.

---

## Running the smoke CLI

```sh
dart pub get
set -a && source .env && set +a
dart run bin/smoke.dart
```

It signs in with `TEST_EMAIL` (auto-signs-up on first run), then walks the 10
contracts below, printing `PASS/FAIL` with HTTP status and a body excerpt so you
can see exactly which contract behaves.

---

## Running the auth deep-dive

Where `smoke.dart` proves the happy path across all five services,
`auth_deepdive.dart` fans out across the **entire `ds-auth` surface** so you can
see exactly which auth features work:

```sh
dart pub get
set -a && source .env && set +a
dart run bin/auth_deepdive.dart
```

It signs in, onboards via `signup`, then exercises:

- **auth** — `login`, `logout`, `me`, `user-status`
- **federated** — `signin/google`, `signin/github`, `signin/microsoft`
- **users** — list, get, update, sessions, avatar (upload/get/delete), and the
  reversible `suspend` / `activate` / `deactivate` transitions
- **providers** — `GET /api/v1/providers`

…and prints a `PASS/FAIL/SKIP` summary table grouped by area.

**Destructive ops are skipped by default.** `DELETE /users/<id>` and
revoke-all-sessions are gated behind `DEEPDIVE_DESTRUCTIVE=1` so a normal run
never bricks the shared test account:

```sh
DEEPDIVE_DESTRUCTIVE=1 dart run bin/auth_deepdive.dart
```

> **Note on auth providers:** DartStream's `AuthProviderType` enumerates 10
> provider SDKs, but only **Firebase** is implemented today; the other nine
> (Auth0, Cognito, Entra ID, Okta, Magic, Fingerprint, Transmit, Stytch, Ping)
> are stubs. This deep-dive therefore proves the Firebase provider end-to-end;
> the federated `signin/*` routes are Firebase-backed.

---

## Running the platform deep-dive

```sh
dart pub get
set -a && source .env && set +a
dart run bin/platform_deepdive.dart
```

It bootstraps a tenant, then exercises `ds-platform-services` end to end:

- **feature-flags** — list, create, get, update, delete
- **projects** — list/create/get/update/archive, plus environments,
  integrations, and orchestration provider resolution
- **api-keys** — list, create, delete
- **settings** — profile + notifications (get/patch)
- **team** — members + invitations (reads); invite/role-change gated behind
  `DEEPDIVE_DESTRUCTIVE=1` (they send email / mutate a real member)
- **middleware** and **discovery** sub-services — full CRUD

CRUD groups create-then-delete so a normal run leaves no clutter in the tenant.

---

## Running the experience / reactive / persistence deep-dives

Same pattern, one per remaining service:

```sh
set -a && source .env && set +a
dart run bin/experience_deepdive.dart    # profiles, cloud-save, inventory, sessions, connectors
dart run bin/reactive_deepdive.dart      # events, streaming, notifications, lifecycle hooks
dart run bin/persistence_deepdive.dart   # database connections, storage configs, logging
```

### OAuth2 / machine-to-machine (`bin/oauth2_deepdive.dart`)

Every deep-dive above signs in a **human** (Firebase ID token). DartStream also
ships the **server-to-server** path (GitLab #96): pay → create an *Application* in
the dashboard → mint a `clientId` + `clientSecret` → exchange them for a
DartStream-signed Bearer JWT and call any service **with no logged-in user**. This
is how a backend, CLI, or CI job connects a real project.

**Step 1 — Create an Application and copy its credentials.**
In the dashboard go to **Settings → Applications → Create OAuth2 Client**. Give it a
name, pick the scopes you need, and leave the **Expiry Date BLANK** (a same-day or
past date mints an already-expired client). On save you get a `clientId` and a
`clientSecret` — **the secret is shown once**, so copy both now.

**Step 2 — Put the credentials in your local `.env`.**
The `.env` file is gitignored; never commit the secret.

```sh
# .env
OAUTH2_CLIENT_ID=client_...
OAUTH2_CLIENT_SECRET=secret_...
API_BILLING=https://dev-apibilling.dartstream.io   # token endpoint host (default)
# OAUTH2_SCOPE=platform:read flags:read projects:read   # optional: subset of the client's scopes
```

**Step 3 — Load the env and run the harness.**

```sh
set -a && source .env && set +a
dart run bin/oauth2_deepdive.dart
```

**What it does:** POSTs `grant_type=client_credentials` to `/api/v1/oauth2/token`
(credentials over HTTP Basic), decodes the returned JWT's tenant + scope claims,
then calls platform / experience / reactive / persistence with **only** that Bearer
token — no Firebase ID token, no `X-Tenant-ID` header — and prints a `PASS/FAIL/SKIP`
table.

> ⚠️ The `clientSecret` is confidential: backends / CLIs / CI only, **never** a
> browser or Flutter bundle. Public web/Flutter apps keep using the Firebase
> end-user login above.

Each Firebase deep-dive bootstraps a tenant, exercises every endpoint in its
service, and prints a `PASS/FAIL/SKIP` table. CRUD groups self-clean. As of
2026-06-03: experience 11/11 and reactive 29/29 are fully green; persistence has
one known backend bug (logging-config save returns a non-persistent id on the upsert
update path — filed as a SaaS ticket).

---

## Running the Flutter + Flame client

The web API key is HTTP-referrer-restricted and `http://localhost:3000` is on
the allowlist, so **the dev server must run on port 3000**.

```sh
set -a && source .env && set +a   # from the repo root, to load FIREBASE_API_KEY
cd flutter_client
flutter pub get
flutter run -d chrome --web-port=3000 \
  --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY
```

Tips:

- It must be a **fresh `flutter run`**, not a hot reload — `--dart-define`
  values are baked in at compile time.
- Run it in an **interactive terminal**; `flutter run` needs a TTY for
  hot-reload and exits immediately otherwise.
- If you prefer, inline the key:
  `--dart-define=FIREBASE_API_KEY=<your-dartstream-prod-web-key>`.

### The login flow

The login screen has a **Create Account / Sign In** toggle taking real
credentials:

- **Create Account** — email, password, and confirm-password, with inline
  validation (valid email, password ≥ 6 chars, passwords match) and friendly
  Firebase error messages (`EMAIL_EXISTS`, weak password, bad credentials, …).
- **Sign In** — email + password for a returning user.

Both paths get a Firebase ID token, then call the backend's onboarding. The
backend's `/api/v1/auth/signup` is **idempotent** — it returns the existing
user for a returning login (with a `/api/v1/auth/login` fallback on 409) — so
the same onboarding call covers both create-account and sign-in.

### What the client does

After login the app is a **navigation shell with one screen per DartStream
service** (NavigationRail on wide screens, a Drawer on narrow):

| Screen | Surface | What you can do |
| --- | --- | --- |
| **Overview** | all | **DartStream Dash** — a Flame arcade game (catch coins, dodge bombs) whose rules come from DartStream: feature flags `double_score`/`hard_mode`/`extra_life` change play, inventory `starter-sword` grants the bomb-clear ability, cloud-save persists & resumes high score / lifetime coins, and every beat (start, level-up, hit, game-over) posts a `reactive/events/log` event |
| **Profile** | auth | the user record + editable display name, the avatar lifecycle (set / view / remove), and session management (revoke one / all) |
| **Feature flags** | platform | list / create / toggle / delete feature flags |
| **Experience** | experience | profile, inventory, active sessions, connector catalog |
| **Reactive** | reactive | log an event + the event log, and CRUD for subscriptions, streaming channels, notification configs, lifecycle hooks |
| **Persistence** | persistence | CRUD for database connections, storage configs, logging configs + a logging-entries panel |

Every screen surfaces backend errors in a SnackBar (it does not hide failures),
and the CRUD screens share one reusable widget
([`resource_crud_section.dart`](flutter_client/lib/widgets/resource_crud_section.dart)).

> Browsers strip `X-User-ID` from the CORS preflight allowlist, so experience
> calls pass `userId`/`tenantId` as query params. The `dartstream_client` SDK
> handles this for you (it derives them from the `DartStreamSession`).

### DartStream Dash (the Overview game)

A small Flame arcade game ([`game/dartstream_dash.dart`](flutter_client/lib/game/dartstream_dash.dart))
that exists to prove the experience/platform services drive real behaviour, not
just panels. **Controls:** drag (or `←`/`→`) to move the ship, catch coins,
dodge bombs; **tap or `Space`** uses the sword; on game over, tap / `R` to
replay. Each service maps to a mechanic:

| DartStream service | In-game effect |
| --- | --- |
| `platform/feature-flags` | a flag keyed **`double_score`** (enabled) → coins score 2×; **`hard_mode`** → faster spawns + more bombs; **`extra_life`** → start with 4 lives |
| `experience/inventory` | owning **`starter-sword`** grants the bomb-clear ability (charges = item quantity) |
| `experience/cloud-save` | the full game state is debounce-saved each coin/level/game-over and **resumed** (high score + lifetime coins) on next load |
| `reactive/events/log` | every beat logs an event: `game.start`, `game.level.up`, `game.bomb.hit`, `game.sword.used`, `game.over` |
| `experience/profiles/me` | player name shown in the HUD |

**Try it:** in the **Feature flags** screen create a flag with key `double_score`
(enabled), then hot-restart / re-enter the Overview — coins now score 20 instead
of 10, and the HUD shows the active modifier. Flag config is read at game start,
so apply a flag then restart the game to see it take effect.

---

## Smoke CLI coverage

`smoke.dart` walks one representative contract per service (the deep-dive CLIs
go far broader — see their sections above):

| # | Method & path | Service | Notes |
| --- | --- | --- | --- |
| 1 | Firebase `signInWithPassword` / `signUp` | Identity Toolkit | yields the ID token |
| 2 | `POST /api/v1/auth/signup` | auth | onboards user + tenant; idempotent |
| 3 | `GET  /api/v1/auth/me` | auth | current user record |
| 4 | `GET  /api/v1/platform/feature-flags` | platform | `{ "flags": [] }` for a new tenant |
| 5 | `GET  /api/v1/experience/profiles/me` | experience | `dartstream-managed` profile |
| 6 | `POST /api/v1/experience/cloud-save/snapshot` | experience | write score (201) |
| 7 | `GET  /api/v1/experience/cloud-save/snapshot` | experience | read back |
| 8 | `GET  /api/v1/experience/inventory/items` | experience | seeded items |
| 9 | `POST /api/v1/reactive/events/log` | reactive | `{ "status": "logged" }` |
| 10 | `GET  /api/v1/reactive/streaming/channels` | reactive | REST channel list (`[]`) |
| 11 | `GET  /api/v1/persistence/database` | persistence | tenant DB connections |

---

## Verified end-to-end (live dev environment, 2026-06-10)

- **Smoke CLI:** 11 / 11 PASS across all five services.
- **Per-service deep-dives:** auth full surface PASS; platform 36 / 36 (2 skips
  are destructive email/role ops); experience 11 / 11; reactive 29 / 29;
  persistence 19 / 19. All green — the two previously-filed backend bugs are now
  fixed and deployed (see below).
- **Flutter client:** a real human account signed up, signed in, scored in the
  game, managed flags, browsed experience/reactive/persistence, and edited the
  profile/avatar — with live data in every screen.

---

## Known backend gaps & filed bugs

### Resolved (fixed by the backend QA agent, verified live 2026-06-10)

- ✅ **Feature-flag PATCH/DELETE → 500** (`ds-platform-services`): a single bind
  param was compared against the `uuid` id and the `varchar` flag_key in the same
  WHERE clause, so flags could be created/read but not updated or deleted. Fixed
  (`id::text = @flagId OR flag_key = @flagId`); PATCH/DELETE now return 200.
- ✅ **Logging-config save returns a phantom id** (`ds-persistence`): the
  `ON CONFLICT DO UPDATE` upsert returned the freshly-generated id instead of the
  persisted row's id (no `RETURNING`), so a second save for the same provider
  handed back an id that 404'd. Fixed with `RETURNING *`; the upsert now returns
  the persisted row's id.

Other notes:

- Of the 10 `AuthProviderType` SDKs, only **Firebase** is implemented today; the
  other nine are stubs. The federated `signin/*` routes are Firebase-backed.
- Inventory exposes only `GET /items`; `streaming/channels` is REST-only.

---

## License

[MIT](LICENSE) © 2026 Brian Chebon
