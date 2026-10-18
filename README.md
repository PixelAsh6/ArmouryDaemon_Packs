# ArmouryDaemon Packs

The official **pack catalog** for [ArmouryDaemon](https://github.com/PixelAsh6/ArmouryDaemon) — a
resident Windows daemon that automates other programs while a tracked app (a game) runs, then puts
everything back.

A **pack** is data, not code: a JSON file that tells the daemon what to change when your tracked app
starts and how to restore the previous state afterwards. Installing a pack from this catalog means
downloading one JSON file, checking its sha256, and dropping it in the daemon's `packs` folder — the
daemon interprets the steps, the pack never executes anything.

## What is in here

```
catalog/index.json          the manifest the daemon reads
packs/<id>/pack.json        the packs themselves (one JSON file each)
LICENSE                     MIT
```

| Pack | What it does | Default action |
|---|---|---|
| `g-helper` | Switches G-Helper's performance mode through its own hotkeys, restores the captured mode afterwards | Turbo |
| `wallpaper-engine` | Stops the animated wallpaper, plays it again afterwards | Stop |
| `rainmeter` | Swaps to an empty layout, reloads `@Backup` afterwards | Empty layout |

## How the daemon installs a pack

1. Read `catalog/index.json` (schema 1).
2. Pick a pack entry; download its `file` and verify `sha256` and `size`.
3. Install it (the daemon validates the pack before writing anything).
4. Updates use the same path: a higher `version` in the catalog is an update.

The catalog only names files inside this repository. Nothing here is executable; see the daemon
repository for the pack specification (`PACK-SPEC-PROPOSAL.md`, `SPEC3-SCRIPTING.md`).

## Keeping the catalog current

Every change to a pack updates, in the same commit:

- the pack file under `packs/<id>/pack.json` (its `version` is bumped: patch for fixes, minor for new
  dropdown values or steps, major for a schema change),
- its `version`, `sha256`, `size` and `updated` fields in `catalog/index.json`,
- the top-level `updated` field in `catalog/index.json`,
- the changelog below.

The hashes are computed over the exact committed bytes of each pack file.

## Changelog

| Date | Change |
|---|---|
| 2026-10-18 | Initial catalog: `wallpaper-engine` 1.4.0, `g-helper` 1.3.1, `rainmeter` 1.3.0. |
| 2026-10-18 | The daemon's catalog client landed: `--catalog-list` and `--catalog-install <id>` fetch this manifest, verify each file's sha256/size and install it (verified live against this repo). No pack content changed. |

## License

MIT — see [LICENSE](LICENSE).
