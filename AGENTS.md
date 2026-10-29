# AGENTS.md

HarmonyOS / ArkTS third-party Mi Home controller. No backend: the app talks directly to reverse-engineered Xiaomi cloud endpoints. The main app and the desktop card run in different processes.

## Commands

- `devecocli build` — debug build + debug signing. Output: `entry/build/default/outputs/default/entry-default-signed.hap`.
- `devecocli build --product release --build-mode release` — unsigned release HAP (`entry/build/release/outputs/default/entry-default-unsigned.hap`). The `release` product intentionally has no `signingConfig`; do not fill it in.
- `devecocli run --skip-build` — deploy/launch the existing debug HAP on the connected device.
- `devecocli check arkts <files...>` — fast ArkTS pre-filter. It is not a substitute for a build: always run `devecocli build` afterwards.
- `devecocli check lint` — project CodeLinter. It reports 2 expected `@security/no-unsafe-hash` errors in `entry/src/main/ets/mi/CryptoUtil.ets` (MD5/SHA1 are required by Xiaomi's login signature) plus 1 Date warning. Do not "fix" the hash algorithms.
- `devecocli docs search <kw>` / `devecocli docs read <id>` — local HarmonyOS docs; check before answering ArkUI/ArkTS API questions.
- No `npm test` and no checked-in `hvigorw`. Tests are Hypium: local pure-logic tests in `entry/src/test/`, device tests in `entry/src/ohosTest/`; run them from DevEco Studio's test runner.

Constraints: compile/target SDK 6.1.1(24), compatible 6.1.0(23). The checkout path must be pure ASCII; non-ASCII paths break hvigor. Version lives in `AppScope/app.json5` — `versionCode` currently tracks `1.0.N` as `100000N`; bump it together with `versionName` and `buildVersion`. `*.hap`, `*.app`, `*.log`, `.deveco/`, `.opencode/`, `sign/`, and `MYpythonSourceCode/` are gitignored.

## Process layout

Three entrypoints, two processes:

- `EntryAbility` → `pages/Index` (main app).
- `WidgetEditAbility` → `pages/WidgetEditPage` (card binding, launched by the form's router action).
- `ElevatorFormAbility` (`FormExtensionAbility`) → `widget/pages/ElevatorWidget` (desktop card, separate process).

`PreferencesUtil` caches the preferences handle. `EntryAbility` calls `setForceReload(false)`; `ElevatorFormAbility.ensureContext()` calls `setForceReload(true)` before every operation so the card process re-reads main-app writes. Keep this asymmetry.

All widget updates must go through `ElevatorFormAbility.enqueueFormUpdate()` (per-form promise chain + `latestFormSeq`). `formProvider.updateForm()` is async and unordered; without the queue an older "on" can land after the final "off". `onUpdateForm`, `pushStateToAllForms`, `pushStatusText`, and `pushNoDevice` already use it — do not add direct `formProvider.updateForm()` calls.

## Auth / token

`MiAuthService` (singleton) → `MiAccount` (login/refresh) + `MiIOService` (signed miio calls). `AssetTokenStore` is the active `MiTokenStore` (Asset Store, Preferences fallback, legacy plaintext migration); `PreferencesTokenStore` is currently unused.

- All authenticated Xiaomi calls must go through `MiIOService.miioRequest()`: it signs with `ssecurity` and handles 401 refresh + retry. Do not call `MiHttpTransport` directly for device APIs.
- Auth failures are `MiAuthError` (`mi/MiErrors.ets`). Service code must rethrow them via `isAuthError` instead of returning `undefined`/`false`/`[]`; the UI then shows "登录已过期" and stops polling.
- `MiAccount.invalidateToken()` is async and must clear memory *and* the persisted token. Memory-only clearing recreates a fake logged-in loop because `checkLoginStatus()` reloads from storage on every page show.
- Refresh: proactive when `expireTime` (6 h soft TTL) passes; reactive on 401/403 → refresh once → retry. Single-flight, max one attempt per 60 s. Xiaomi `70022` feeds `LoginCooldown` (5 failures → 2 h). Do not add parallel refreshes; it risks account lockout.
- `MiHttpTransport` must populate `MiHttpResp.statusCode`; `MiIOService` treats HTTP 401/403 (even non-JSON) as auth errors. Keep `protectBigNumbers()` on JSON parses of API/token payloads — Xiaomi IDs exceed JS safe integers.

## Device state

- `MiDeviceService.refreshDeviceStates()` batches all devices into one `/miotspec/prop/get`; the app polls every 5 s.
- Momentary ("点动"): `pulseSwitchByDid()` writes true, polls up to 5 s for false, force-writes false, then `getSettledSwitchState()` samples 5 times. The settled read is the UI truth — never leave the card on an assumed value. `Index` keeps a per-device `stateVersion` so a 5 s refresh started before a click cannot overwrite the click result.
- Unknown/offline is `undefined`, rendered through `StatusTexts` / `app.string.status_*`. Do not add a third boolean state.

## ArkTS notes

- ArkTS 1.1 / V1 state only (`@State`, `@LocalStorageProp`, `@Builder`). The project uses `as` casts and `Record<string, ...>` heavily; no `any`.
- `throw` must be an `Error` instance: `throw e` fails `arkts-limited-throw`; wrap as `throw new MiAuthError(String(e))`. Catch variables are untyped; normalize with `String(e)`.
- Pages must be registered in `entry/src/main/resources/base/profile/main_pages.json` (`pages/Index`, `pages/SettingsPage`, `pages/WidgetEditPage`).
- Logging is `hilog` with domain `0x0200`. `MiDebug` file logging is off (`DEBUG_MODE=false`).

## Docs and local files

`README.md` (zh) is user-facing; `README_EN.md` mirrors it. `IMPROVEMENTS.md` is a historical report — its line numbers are a snapshot and it claims everything is fixed; verify against code. `MYpythonSourceCode/` is a local, gitignored Python scratch area that may contain live `.mi.token` credentials — do not read, copy, or commit its contents. `.opencode/opencode.json` pins an absolute `PROJECT_PATH` for the deveco MCP; if the checkout moved, update it (or use `switch_cwd`) or the MCP will operate on the wrong project.
