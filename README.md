# ArmouryDaemon Packs

[![Licence: MIT](https://img.shields.io/badge/Licence-MIT-yellow.svg)](LICENSE)

The official **pack catalogue** for [ArmouryDaemon](https://github.com/PixelAsh6/ArmouryDaemon) —
a resident Windows daemon that switches the rest of your machine around the apps you track, then
puts everything back.

This repository holds **data only**: one `pack.json` per pack, plus the manifest the daemon
fetches. Nothing here is executable. The daemon validates every pack, verifies the hash of the
ones it downloads, and interprets it — a pack never runs anything by itself.

## What is in here

```text
catalog/index.json          the manifest the daemon reads
packs/<id>/pack.json        the packs themselves (one JSON file each)
README.md                   this file
.gitattributes              keeps the JSON files LF, so the hashes stay honest
LICENSE                     MIT
```

## The packs in this repo

| Pack | Version | What it does |
|---|---|---|
| `wallpaper-engine` | 1.4.0 | Stops, pauses or kills the animated wallpaper while a tracked app runs, and plays it again afterwards. Two dropdowns: the action, and which binary to call (auto, 64-bit, 32-bit). |
| `g-helper` | 1.3.1 | Switches G-Helper's performance mode (Turbo / Balanced / Silent) through G-Helper's own hotkeys while a tracked app runs, and restores the captured mode afterwards. |
| `rainmeter` | 1.5.0 | Loads another Rainmeter layout while a tracked app runs and reloads the `@Backup` snapshot afterwards. A spec 2 pack: the bang and the window class are pack data, and the pack sends them itself. |

## Installing a pack

From the daemon's Settings window: **Install packs** opens the catalogue window, **Check for
updates** fetches the manifest, and **Download** pulls the pack down, checks it against the
manifest and hands it to the daemon, which validates it and installs it into its own `packs`
folder.

From the command line:

```console
ArmouryDaemon.exe --catalog-list
ArmouryDaemon.exe --catalog-install rainmeter
```

`--catalog-install` fetches the manifest, downloads the file, verifies its **size and SHA-256**,
and only then writes it through the normal install path. Nothing that cannot be verified is ever
installed.

## The pack format

A pack is one JSON file. The schema is enforced by the daemon (`crates/armoury-core/src/pack.rs`
in the daemon repository), and a pack that does not validate is refused at install time.

```jsonc
{
  "spec": 2,                       // 1 = data only, 2 = data + a script
  "id": "rainmeter",               // unique, non-empty
  "name": "Rainmeter",             // shown in the UI
  "version": "1.5.0",              // shown in the UI, compared against the catalogue
  "min_engine": "1.0.0",           // the oldest daemon that may run it (default: no minimum)
  "kind": "pack",                  // "pack" (default) or "mode"
  "triggers": [ { "kind": "tracked_app" } ],  // what starts it (default shown)
  "order": 30,                     // packs apply ascending, revert descending (default 100)
  "targets": { "process": ["Rainmeter.exe"] },   // exe file names, matched case-insensitively
  "settings": [                    // at most 4 dropdowns
    {
      "key": "layout",             // unique within the pack
      "label": "Layout while a tracked app runs",
      "type": "enum",              // "enum" is the only type
      "values": ["Empty", "Default", "illustro default", "kill"],
      "default": "Empty"           // must be one of the values
    }
  ],
  "capture": [                     // what to remember before acting
    { "key": "was_running", "mechanism": "process_running" },
    { "key": "target_path", "mechanism": "target_path" }
  ],
  "capabilities": ["context", "ipc", "process", "time"],  // what it may call (default: everything)
  "script": {                      // spec 2 only
    "apply":  "…Rhai source…",
    "revert": "…Rhai source…"
  },
  "apply":  { "guard": { … }, "steps": [ … ] },
  "revert": { "guard": { … }, "steps": [ … ] }
}
```

**`kind`** says what the pack is. `"pack"` (the default) applies while a tracked app runs.
`"mode"` marks a global on/off pack with a trigger of its own. A mode's work runs on its own
worker thread, separate from the packs, so a slow mode cannot delay a pack. That is newer than
1.1.6: there, a mode still runs on the pack worker. Anything else is refused when the pack is
parsed: `unknown kind 'widget' (expected 'pack' or 'mode')`.

**`triggers`** says what starts the pack. The default is the tracked app, and `hotkey` is the
other kind:

```json
"triggers": [ { "kind": "hotkey", "key": "end" } ]
```

A `hotkey` trigger needs a key; a `tracked_app` trigger takes none. Either mistake is refused
when the pack is parsed. The key is resolved by the daemon's own hotkey table, not by the schema,
so a name the daemon does not know is a trigger that never fires. A mode with an explicitly empty
list is refused, because nothing would ever start it. An absent list is not empty: it defaults to
the tracked app.

In 1.1.6 nothing dispatches a trigger yet: a pack still applies and reverts on the tracked app,
mode or not, and a hotkey trigger does not fire.

**`min_engine`** is the oldest daemon that may run the pack, for a pack that needs a host function
an older one does not have. No value means every daemon. A pack that asks for a newer daemon is
refused at install, with the version it needs and the version of the daemon that refused it.

**`capabilities`** is what the pack may call. It gates the steps and the script alike, and
omitting it grants everything, which is what keeps the shipped packs working. The section
"What a pack may do", below, lists the names and what each one opens.

`capabilities` arrived in 1.1.5; `kind` and `triggers` in 1.1.6. All three are additive: a pack
that omits them loads and behaves exactly as it did before they existed.

**Guards** decide whether a block runs at all:

| Guard | Default | Meaning |
|---|---|---|
| `targetRunning` | `true` | Skip the whole block when the target process is not running. |
| `capturedRunning` | `false` | Skip the block unless the target was running when the pack was applied (the `was_running` capture was `"1"`). |

**Steps** are the actions, in order. The fields that are not part of the mechanism in use are
ignored.

| Field | Meaning |
|---|---|
| `mechanism` | One of the five mechanisms below. |
| `exe` | The program to act on. |
| `exe_from_setting` + `exe_map` | Take the program from a dropdown value (`dropdown value → exe template`). |
| `args` | The command line arguments. |
| `map` | For `hotkey`: `value → key chord`. |
| `keys_from_mode` | For `hotkey`: take the map key from this dropdown's value. |
| `keys_from_captured` | For `hotkey`: take the map key from this captured value. |
| `expect_exit` | For `cli`: the exit code that counts as success. |
| `when` | Run the step only when a condition holds (see below). |
| `sleep_ms` | Wait this long before running the step. |
| `registry` | For `registry_set`: `{ "path", "name", "dword" }`. |

A `when` clause is a plain equality test on a dropdown value or a captured value:

```json
{ "when": { "source": "setting", "equals": "kill" } }
{ "when": { "source": "captured", "key": "prev_mode", "not_equals": "0" } }
```

**Templates.** Anywhere a string is allowed, these are substituted:

`{{target.exe}}` · `{{target.name}}` · `{{target.dir}}` · `{{settings.<key>}}` ·
`{{captured.<key>}}`

An unknown placeholder is left untouched and reported, so a typo never turns into a silent empty
string.

## What a pack may do

A pack declares the capabilities it needs. They gate the steps and the script alike. A script call
to a function of a capability the pack was not granted fails as an **unknown function**, because
the function is not on that pack's engine at all. A step whose mechanism needs a capability the
pack was not granted is refused when the pack is validated, so the pack never installs.

**Omitting `capabilities` grants every capability.** That is the default, and it is why the three
shipped packs, written before the field existed, still work. `"capabilities": []` is the other end
of the range: a pack that asks for nothing, not even `context`.

| Capability | What it opens | Host functions |
|---|---|---|
| `context` | The app the pack drives, and the pack's own settings and captures. | `target_name`, `target_exe`, `target_dir`, `setting`, `captured` |
| `journal` | The pack's own log and captures. | `log`, `capture` |
| `files` | Reading a file anywhere. | `read_file`, `read_json`, `read_ini` |
| `files-write` | Writing a file inside the four file roots. | `write_file` |
| `registry` | Writing a value under HKCU or HKLM, outside the four file roots. | none; the `registry_set` step only |
| `process` | Looking at, killing and starting processes. | `process_running`, `process_kill`, `process_start` |
| `exec` | Running a program. | `run_cli` |
| `input` | Sending keystrokes. | `hotkey` |
| `ipc` | Sending a message to another app's window. | `window_message` |
| `windows` | Hiding and showing other apps' windows. | `windows_of`, `window_hide`, `window_show` |
| `audio` | Muting and unmuting audio. | `audio_sessions`, `audio_mute`, `audio_mute_all` |
| `overlay` | Asking the daemon for the idle overlay. | `overlay_show`, `overlay_hide` |
| `time` | Waiting. | `sleep` |

A name the daemon does not know is refused when the pack is parsed:
`unknown capability 'teleport'`.

A step is gated by the same table: `cli` needs `exec`, `process_start` and `process_kill` need
`process`, `hotkey` needs `input`, and `registry_set` needs `registry`. A pack that asks for
`files` and carries a `cli` step is refused when it is validated, with the reason in the message:

```
apply step 0: 'cli' needs the 'exec' capability, which this pack was not granted (the pack asked for: files)
```

A denied script call fails as an unknown function, and the log names the missing capability in the
same sentence.

- `exec` runs a program and waits for it (`run_cli`); `process` is how a pack looks at, kills or
  starts one. Starting an app with a `process_start` step asks for `process`, not `exec`.
- `files-write` stops at `%APPDATA%`, `%LOCALAPPDATA%`, `%PROGRAMDATA%` and the target's folder.
  `registry` is the capability that reaches past them: it writes under HKCU or HKLM, which is
  where Windows looks a start-up entry up.
- `overlay_show` and `overlay_hide` ask the daemon to enter or leave idle mode. The overlay
  windows belong to the daemon's main loop, so a pack requests the overlay instead of painting
  one.
- `time` covers the script's `sleep`. A step's `sleep_ms` needs no capability.

The list is the grant: 1.1.6 has no separate permission window, so a pack that declares
`["exec"]` can run programs and nothing else. A pack that declares `[]` gets an engine with no
host function on it at all.

## The mechanism vocabulary

A pack can only use what the daemon implements, and only with the capability it was granted.
Anything else is rejected at install time.

**Step mechanisms** (`cli`, `hotkey`, `process_kill`, `process_start`, `registry_set`):

| Mechanism | What it does |
|---|---|
| `cli` | Runs a program with arguments. `expect_exit` pins the exit code that counts as success. |
| `hotkey` | Sends a key chord (for example `ctrl+shift+alt+f18`) to the focused window. The chord comes from `map`, selected by `keys_from_mode` or `keys_from_captured`. |
| `process_kill` | Terminates the running process with that exe file name. |
| `process_start` | Starts a program — but never a second copy of one that is already running. |
| `registry_set` | Writes a `REG_DWORD` value. |

**Capture mechanisms** (`process_running`, `json_file`, `target_path`):

| Mechanism | What it captures |
|---|---|
| `process_running` | `"1"` if the target is running, `"0"` if not. |
| `target_path` | The full image path of the running target. |
| `json_file` | A JSON pointer out of a JSON file (`path` plus `pointer`, default `/`). `%APPDATA%` and friends are expanded. |

**The script host API** (spec 2). A spec-2 pack's `script.apply` and `script.revert` are Rhai
source. The daemon compiles and runs them in a sandboxed interpreter with a whitelisted host API
and nothing else — no `eval`, no imports, no ambient file or process access. The whitelist is the
capabilities the pack was granted: a function of a capability it did not ask for is not on the
engine at all.

`ctx.target_name()` · `ctx.target_exe()` · `ctx.target_dir()` · `ctx.setting(key)` ·
`ctx.captured(key)` · `ctx.capture(key, value)` · `ctx.log(msg)` · `ctx.run_cli(exe, args)` ·
`ctx.hotkey(chord)` · `ctx.window_message(class, title, payload)` · `ctx.sleep(ms)` ·
`ctx.process_running(name)` · `ctx.process_kill(name)` · `ctx.process_start(path)` ·
`ctx.read_file(path)` · `ctx.write_file(path, text)` · `ctx.read_json(path, pointer)` ·
`ctx.read_ini(path, section, key)` · `ctx.windows_of(pid)` · `ctx.window_hide(hwnd)` ·
`ctx.window_show(hwnd)` · `ctx.audio_sessions()` · `ctx.audio_mute(pid, muted)` ·
`ctx.audio_mute_all(muted)` · `ctx.overlay_show()` · `ctx.overlay_hide()`

`ctx.window_message` is the generic one: it finds a window of another application by class and/or
title (an empty field matches any) and sends it the payload as a `WM_COPYDATA` message, with a
2 s timeout so a hung application cannot block the daemon.

`ctx.audio_mute` returns the previous state of every session of the process, so a revert can put
it back, and an unmute leaves a session the user had muted alone. `ctx.overlay_show` and
`ctx.overlay_hide` ask the daemon to enter or leave idle mode: the overlay windows belong to the
daemon's main loop, so the pack is not painting anything itself.

Every script gets a hard budget — 500 000 operations, a 64 KiB string limit, no modules and a
10 s wall clock — and every host call is written to the pack's log. Writes and program launches
are restricted to `%APPDATA%`, `%LOCALAPPDATA%`, `%PROGRAMDATA%` and the target app's own folder.

## Writing a pack

The Rainmeter pack is the shortest complete example, and it is a **spec 2** pack: it is the one
that drives Rainmeter itself, sending Rainmeter's own bang over `WM_COPYDATA`. Here it is in
full, from `packs/rainmeter/pack.json`:

```json
{
  "spec": 2,
  "id": "rainmeter",
  "name": "Rainmeter",
  "version": "1.5.0",
  "min_engine": "1.0.0",
  "order": 30,
  "targets": { "process": ["Rainmeter.exe"] },
  "settings": [
    {
      "key": "layout",
      "label": "Layout while a tracked app runs",
      "type": "enum",
      "values": ["Empty", "Default", "illustro default", "kill"],
      "default": "Empty"
    }
  ],
  "capture": [
    { "key": "was_running", "mechanism": "process_running" },
    { "key": "target_path", "mechanism": "target_path" }
  ],
  "script": {
    "apply": "let layout = ctx.setting(\"layout\"); if layout != \"kill\" { ctx.window_message(\"DummyRainWClass\", \"\", \"!LoadLayout \\\"\" + layout + \"\\\"\"); }",
    "revert": "let layout = ctx.setting(\"layout\"); if layout == \"kill\" { ctx.sleep(3000); } ctx.window_message(\"DummyRainWClass\", \"\", \"!LoadLayout \\\"@Backup\\\"\");"
  },
  "apply": {
    "guard": { "targetRunning": true },
    "steps": [
      { "mechanism": "process_kill", "exe": "{{captured.target_path}}",
        "when": { "source": "setting", "equals": "kill" } }
    ]
  },
  "revert": {
    "guard": { "targetRunning": false, "capturedRunning": true },
    "steps": [
      { "mechanism": "process_start", "exe": "{{captured.target_path}}",
        "when": { "source": "setting", "equals": "kill" } }
    ]
  }
}
```

Line by line:

- **`"spec": 2`** — this pack carries a script. A data-only pack says `"spec": 1` and has no
  `script` block at all. The daemon refuses a script on a spec-1 pack, and refuses a spec-2 pack
  without one.
- **`"id"`, `"name"`, `"version"`** — the identity. The id is the folder name and the key the
  daemon stores the user's choice under; the version is what the catalogue compares.
- **`"min_engine": "1.0.0"`** — the oldest daemon that may run it. This pack needs nothing newer
  than 1.0.0; a pack that uses a host function an older daemon lacks names a later version, and
  the install is refused instead of failing at apply.
- **`"order": 30`** — packs apply in ascending order and revert in descending order, so
  Wallpaper Engine (10) applies before G-Helper (20) before Rainmeter (30).
- **`"targets": { "process": ["Rainmeter.exe"] }`** — the pack reacts to `Rainmeter.exe`. The
  match is on the exe file name, case-insensitively, wherever the file lives.
- **`"settings"`** — one dropdown, `layout`, with four values. `default` must be one of the
  values. The daemon also fills in the values of a dropdown a pack has gained since the config
  was written, so an old config keeps working. The Rainmeter pack is the one the daemon
  rewrites at load time: it replaces this list with the layouts actually found on the machine
  and makes sure a genuinely *Empty* one exists, so the values published here are a fallback and
  each user sees their own layouts.
- **`"capture"`** — `was_running` records whether Rainmeter was up before the pack acted (the
  `capturedRunning` guard needs it), and `target_path` remembers where `Rainmeter.exe` lives, so
  the pack can start it again later.
- **`"script.apply"`** — Rhai source. It reads the chosen layout from the dropdown and, unless
  the user picked `kill`, sends Rainmeter the bang `!LoadLayout "<layout>"` to the window of
  class `DummyRainWClass`. The window class and the bang are **pack data**; the daemon only knows
  how to send a `WM_COPYDATA` message to a window.
- **`"script.revert"`** — when the layout was `kill`, Rainmeter was quit by the step below, so
  the script waits 3 s for it to come back up, then loads the `@Backup` layout. Otherwise it
  goes straight back to `@Backup`, which is Rainmeter's own snapshot of the previous layout.
- **`"apply"`** — the guard `targetRunning: true` means the block only runs while Rainmeter is
  actually up. The single step kills Rainmeter, but only `when` the dropdown equals `kill`.
- **`"revert"`** — the guard `targetRunning: false, capturedRunning: true` is the one every
  revert needs: the block runs after the target has gone, but only if it had been running when
  the pack applied. The step starts Rainmeter again, again only for the `kill` option.
- **No `kind`, no `triggers`, no `capabilities`** — the three fields are absent, so the defaults
  apply: this is a pack, it follows the tracked app, and it is granted every capability. Its
  script calls `setting` and `window_message`, and its steps use `process_kill` and
  `process_start`, so `["context", "ipc", "process", "time"]` is what it would declare if it
  declared anything. Declaring nothing is what lets this pack, and the other two, run unchanged
  on a daemon that has the field.

Two things are worth spelling out. First, **a block's steps run first, then its script** — that
is what makes the 3 s wait in the revert correct, because Rainmeter is already running again when
the script waits. Second, a pack never executes anything itself: the daemon interprets the
script against the whitelisted host API above, under a budget, and logs every call.

The other two packs are spec 1 and simpler: `g-helper` uses a `hotkey` step with a
`keys_from_mode` map, and `wallpaper-engine` uses `cli` steps with an `exe_from_setting` map for
choosing between the 64-bit and the 32-bit binary.

## The catalogue format

`catalog/index.json` is the manifest the daemon fetches. By default it reads the raw file on
GitHub: `https://raw.githubusercontent.com/PixelAsh6/ArmouryDaemon_Packs/main/catalog/index.json`.
That is a plain fetch of a public file, so listing and installing a pack needs no API key — the
daemon's SteamGridDB key is for cover art only.

```json
{
  "schema": 1,
  "updated": "2026-10-20",
  "packs": [
    {
      "id": "rainmeter",
      "name": "Rainmeter",
      "version": "1.5.0",
      "description": "…one line, shown in the catalogue window…",
      "file": "packs/rainmeter/pack.json",
      "sha256": "579fd1aeac384a832f29f2162f4af2ad0cb24931239c1926a787a39af8f4dc6b",
      "size": 1342,
      "min_engine": "1.0.0",
      "updated": "2026-10-20"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `schema` | The manifest schema. The daemon understands `1` and refuses anything else. |
| `updated` | The date the manifest was last changed. |
| `packs[].id` | The pack id. The daemon matches it against the installed packs. |
| `packs[].name` | The display name. |
| `packs[].version` | The version. A higher version than the installed one is an update. |
| `packs[].min_engine` | The smallest daemon that may install this pack; a daemon older than that is not offered the pack at all. No value means every daemon. |
| `packs[].description` | One line for the catalogue window. |
| `packs[].file` | The path of the pack file, relative to the **repository root** — not to the manifest's own folder. |
| `packs[].sha256` | The SHA-256 of the exact published bytes, in lowercase hex. |
| `packs[].size` | The size of the published file in bytes. |
| `packs[].updated` | The date this pack was last changed. Informational. |

The daemon downloads the file, checks the **size** first and then the **SHA-256**, and refuses
anything that does not match — with an error that says what did not happen and why it happened.

## Publishing a pack

Every change to a pack updates, in the same commit:

- the pack file under `packs/<id>/pack.json`, with its `version` bumped — patch for a fix, minor
  for new dropdown values or steps, major for a schema change;
- its `version`, `sha256`, `size` and `updated` in `catalog/index.json`, plus its `min_engine`
  when the pack declares one — a manifest without it would offer a pack the daemon then refuses;
- the top-level `updated` in `catalog/index.json`;
- the changelog below.

Two rules are easy to get wrong.

**1. Hash the published bytes, never a Windows working-tree copy.**
With `core.autocrlf=true` and no rule in the repository, a checkout rewrites LF to CRLF. The
file on disk is then a different file from the one GitHub serves, and the hash and size taken
from it will not match the download — the install fails on the size check before it ever reaches
the hash. Hash the blob Git actually holds:

```powershell
cmd /c "git cat-file blob HEAD:packs/rainmeter/pack.json > blob.json"
(Get-FileHash -Algorithm SHA256 blob.json).Hash.ToLower()
(Get-Item blob.json).Length
```

Do **not** pipe `git cat-file` into `Out-File`, `Set-Content` or `>` from PowerShell: the
pipeline splits the output into lines and writes it back with CRLF, so the file you hash is one
byte larger per line than the blob and the hash never matches. `cmd /c` writes the bytes as
they are.

This repository carries a `.gitattributes` with `*.json text eol=lf`, so the tree stays LF and
the working-tree copy and the published blob agree.

**2. A fresh publish is not visible for up to five minutes.**
`raw.githubusercontent.com` caches the `main` branch for up to five minutes (`X-Cache: HIT`,
`Cache-Control: max-age=300`). *Check for updates* can therefore still show the previous version
for a little while, and a pack file fetched from that stale view does not match the manifest's
hash — so the install is refused. That refusal is correct: the daemon never installs a file it
cannot verify, and the error says exactly this.

The **repository itself is never stale** — the commit is there at once; only the CDN's view of
`main` lags. A commit-pinned URL is correct immediately:

```text
https://raw.githubusercontent.com/PixelAsh6/ArmouryDaemon_Packs/<commit-sha>/catalog/index.json
```

## Changelog

| Date | Change |
|---|---|
| 2026-10-18 | Initial catalogue: `wallpaper-engine` 1.4.0, `g-helper` 1.3.1, `rainmeter` 1.3.0. |
| 2026-10-18 | The daemon's catalogue client landed: `--catalog-list` and `--catalog-install <id>` fetch this manifest, verify each file's sha256/size and install it (verified live against this repo). No pack content changed. |
| 2026-10-20 | `rainmeter` 1.4.0 (spec 2): the pack sends Rainmeter's own bang over `WM_COPYDATA`; the daemon no longer knows Rainmeter's protocol. |
| 2026-10-20 | `rainmeter` 1.5.0: the pack declares `min_engine` 1.0.0, the daemon it needs. The bytes changed, so the hash and the size moved with the version. |
| 2026-10-20 | The README now documents the pack format, the mechanism vocabulary and the publishing rules. The licence holder is the author. |
| 2026-10-24 | The README documents `capabilities` (1.1.5), `kind` and `triggers` (1.1.6) and `min_engine`, and lists the host functions of all thirteen capabilities. The Rainmeter example and its manifest entry now match the published 1.5.0 pack. |
| 2026-10-26 | The `kind` section's worker sentence is qualified: the separate mode worker is newer than 1.1.6, and on 1.1.6 a mode still runs on the pack worker. No pack content changed. |

## Licence

MIT — see [LICENSE](LICENSE).

## Credits

The packs drive third-party software, which is **not** part of this project:

- [G-Helper](https://github.com/seerge/g-helper) — the performance mode is switched through
  G-Helper's own documented hotkeys.
- [Rainmeter](https://www.rainmeter.net) — the layout is changed with Rainmeter's own `!LoadLayout`
  bang.
- [Wallpaper Engine](https://www.wallpaperengine.io) — the wallpaper is controlled through its
  own `-control stop|pause|play` command line.

The daemon that reads these packs is [ArmouryDaemon](https://github.com/PixelAsh6/ArmouryDaemon).
The pack format, the mechanism vocabulary and the script host API are documented there: the
schema, the allowed mechanisms and the allowed captures live in the daemon's own source,
`crates/armoury-core/src/pack.rs`; the script host in its `README.md`; and the host calls a spec-2
pack may make in `deploy/README.md`.
