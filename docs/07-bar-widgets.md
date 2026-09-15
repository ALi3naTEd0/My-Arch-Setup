# Bar widgets

One indicator end-4's `ii` panel family doesn't ship. It lives under
`~/.config/quickshell/ii/`, which `./setup install` overwrites — step 9
of [`end4-post-install.sh`](../scripts/end4-post-install.sh) puts it back.

Source files are kept in [`quickshell/`](../quickshell) so a fresh machine can
copy them straight in.

---

## Updates indicator

`waffle` has `UpdatesButton.qml`; `ii` has nothing, even though the `Updates`
service runs in both. Only the presentation was missing.

| File | What |
|---|---|
| `modules/ii/bar/UpdatesIndicator.qml` | icon + pending count |
| `modules/ii/bar/BarContent.qml` | insertion into the indicator row |
| `services/Updates.qml` | one-line change so the count includes the AUR |

```qml
readonly property bool shouldShow: Updates.available && Updates.count > 0
```

Deliberately different from `waffle`, which only shows the button past
`adviseUpdateThreshold` (75) — you don't find out until weeks of neglect. The
thresholds still drive the colour.

Left click runs `Config.options.apps.update`, then re-queries every 30 s for ten
minutes so the icon disappears on its own. Right click checks now.

### What it runs

```json
"update": "kitty ~/.local/bin/end4-update"
```

The stock command is `pkexec pacman -Syu` inside fish, which **cannot work**:
pkexec does not pass a terminal, so it can never prompt for a password. It also
ignores the AUR.

[`end4-update`](../scripts/end4-update) prints what is pending grouped by source
before touching anything, then upgrades — roughly what HyDE's `system.update.py`
did, without the HyDE dependency:

```
  repo       3 pending
  AUR        1 pending
  flatpak    up to date

Repo (3)
  kitty                  0.48.2-1 -> 0.49.0-1
```

Two details worth keeping:

- **`checkupdates`, not `pacman -Sy`.** It refreshes a private copy of the
  database, so it never leaves the real one half-synced — which is how you get a
  partial upgrade. It needs `pacman-contrib`; without it the script falls back to
  the AUR helper and says so.
- **Named ansi colours only** (slots 1–6), so the output follows end-4's
  wallpaper palette. If those six look like two, that is `harmony`
  ([here](06-troubleshooting.md#the-terminal-palette-really-is-two-colors)), not
  this script.

`UpdatesIndicator` runs the string through `bash -c`, so `~` expands.

> If the icon isn't there, check there's actually something pending:
> `{ checkupdates; yay -Qua; } | wc -l`. It hides at zero by design.

---

## AI agent usage — removed 2026-09-15

Rate-limit and prompt counts for Claude Code and Codex, ported from
[Omarchy](https://github.com/basecamp/omarchy). **The quota half never worked
here, and it was removed rather than left showing a number nobody could trust.**

The collector probes `https://api.anthropic.com/api/oauth/usage` with the token
in `~/.claude/.credentials.json`. On this setup that file is not maintained:

```
token expired  2026-09-09 22:10
still the same 2026-09-15, after six days of daily use
probe           HTTP 401
```

Upstream's design assumes the Claude Code **CLI** refreshes it on every run, and
that is what I said would happen each time the number looked wrong. It did not.
Without a live token there is no quota, and the widget could only report prompt
counts scraped from local transcripts — which is not what it was added for.

Two things worth keeping from the attempt, because both cost real time:

**A cached limit with no `resetsAt` never expires.** `Session (5-hour) 0.0%` sat
in `~/.cache/agent-usage/claude-limits.json` for five days and was rendered as
the current quota the whole time. Its sibling `Weekly (7-day) 0.79` *did* carry
a reset time and was correctly dropped once it passed — so the panel kept
exactly the entry that should have gone first. Any cache of windowed
measurements needs to age out against its own fetch time, not only against a
timestamp the payload may not contain.

**`percent` was a 0..1 fraction and the key was `resetsAt`, not `resets_at`.**
Both were silent: 70% rendered as a plausible "0.7 %", and the reset row just
never appeared. Neither looked like a bug.

**StyledPopup needs `containsMouse`**, so a `hoverTarget` must be a `MouseArea`
with `hoverEnabled`, not a plain `Item` — the popup silently never opens. And
`StyledToolTip` has no `content` property; passing one crashes the shell.

Step 16 is now a cleanup: it deletes the QML, the collectors and the cache from
any machine that still carries them.
