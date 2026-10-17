# Lang Switcher

Small macOS menu-bar app that detects whether you are typing **English**, **Swedish**, or **Russian** and switches the keyboard layout for you. If the wrong layout was active, it fixes the word and selects the right language.

No cloud, no account - everything runs locally on your Mac.

## Install (for family / GitHub users)

**Requirements:** macOS 11 or later, Apple Silicon or Intel (build per architecture, see below).

### Option A - Download a release (easiest)

1. Open the [Releases](../../releases) page on GitHub.
2. Download `LangSwitcher-arm64.app.zip` (Apple Silicon **arm64**).
3. Unzip and drag **LangSwitcher.app** into **Applications**.
4. Open it once from Applications.
5. Allow **Device Control and Data Access** and **Input Monitoring** when macOS asks (use **Open System Settings**, not Deny).
6. Optional: **System Settings → General → Login Items** → add Lang Switcher so it starts after login.

### Option B - Build from source

```bash
git clone https://github.com/irookanji/lang-switcher.git
cd lang-switcher
chmod +x scripts/install-to-applications.sh
./scripts/install-to-applications.sh
```

You need Xcode Command Line Tools (`xcode-select --install`).

After each rebuild, run `./scripts/reset-privacy.sh` once and allow permissions again.

## Size and performance

Typical install is about **1–2 MB** (app + bundled word lists). One small background process; no GPU, no network. RAM use is usually a few megabytes.

## Menu bar

- **EN / SV / RU** - current keyboard language the app tracks.
- **⏸** - switching is **paused** (app still running; keys are not rewritten).
- Menu → **Pause switching** (or **⌥⌘P**) to pause or resume without quitting.

## Permissions

Both are required:

| App menu | System Settings (macOS 26+) |
|----------|-----------------------------|
| Accessibility | **Privacy & Security → Device Control and Data Access** |
| Input Monitoring | **Privacy & Security → Input Monitoring** |

The menu shows **Accessibility: granted** and **Input Monitoring: granted**, and **Status: listening to the keyboard**.

If toggles look ON but the menu says **missing**, run `./scripts/reset-privacy.sh`, reopen the app, and allow again.

Run **only one copy** (usually `/Applications/LangSwitcher.app`).

## How switching feels

- Russian: type `ghbdtn` with English layout → becomes `привет` while you type (from the 3rd letter).
- Swedish / English: correction at **word end** (space or punctuation), e.g. `f;r` + space → `för`.
- Shared Latin words (`super`, `och`, `the`): layout switches at the end of the word.
- **⌃⌥L** - cycle the current word through EN → SV → RU.

## Custom words

`~/Library/Application Support/LangSwitcher/words.txt`:

```
* ok
en wifi
sv hej
ru привет
```

Lines starting with `*` count in every language. Restart the app after editing.

## Word lists

Bundled lists are derived from [Hermit Dave FrequencyWords](https://github.com/hermitdave/FrequencyWords) (see `wordlists/NOTICE`).

## Develop

```bash
./scripts/check.sh      # logic tests
./scripts/build-app.sh
```

`swift build` may fail without full Xcode (no XCTest in Command Line Tools only).

## License

MIT - see [LICENSE](LICENSE).
