# Bar widgets

Two indicators end-4's `ii` panel family doesn't ship. Both live under
`~/.config/quickshell/ii/`, which `./setup install` overwrites — steps 9 and 16
of [`end4-post-install.sh`](../scripts/end4-post-install.sh) put them back.

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

## AI agent usage

Rate-limit and prompt counts for Claude Code and Codex, on hover.

```
~/.local/bin/agent-usage-claude  ─┐
~/.local/bin/agent-usage-codex   ─┤→  services/AgentUsage.qml → AgentUsageIndicator.qml
        (another agent = another file)                        └→ AgentUsagePopup.qml
```

Each collector prints **one JSON object** and knows nothing about the widget, so
adding an agent means dropping in another `agent-usage-*` script. That plug-in
shape is Omarchy's design and it is worth keeping.

### Collectors

Vendored from [Omarchy](https://github.com/basecamp/omarchy) (MIT),
`bin/omarchy-agent-usage-{claude,codex}`. The only change is the cache directory
(`~/.cache/agent-usage` instead of `~/.cache/omarchy/agent-usage`) so they don't
pretend to be an Omarchy install. Transcript scanning, the stats-cache
fallbacks and the OAuth usage probe are upstream's work.

They read local transcripts (`~/.claude/projects`, `~/.codex`) and query the
provider for quota:

```bash
~/.local/bin/agent-usage-claude | python3 -m json.tool
```

Useful keys: `todayPrompts`, `todayTotalTokens`, `totalPrompts`, `tierLabel`,
and `limits[] -> {label, percent, resetsAt}`.

### Two traps in the QML

Both were silent — no error, just wrong or missing output:

**`percent` is a 0..1 fraction, not a percentage.** The collector's
`normalize_utilization` divides by 100, so 70% arrives as `0.70`. Rendering it
directly gives a plausible-looking "0.7 %", which is the worst kind of bug —
nothing looks broken. Multiply by 100.

**The key is `resetsAt`, not `resets_at`.** The API returns `resets_at`; the
collector renames it. Reading the wrong one yields `undefined`, the row hides,
and it looks like the API just doesn't send a reset time.

Verify against the raw API when a number looks off:

```bash
python3 - <<'PY'
import json, os, urllib.request
c = json.load(open(os.path.expanduser("~/.claude/.credentials.json")))["claudeAiOauth"]
r = urllib.request.Request("https://api.anthropic.com/api/oauth/usage",
    headers={"Authorization": "Bearer " + c["accessToken"],
             "anthropic-beta": "oauth-2025-04-20"})
print(json.dumps(json.load(urllib.request.urlopen(r)), indent=2))
PY
```

### Quota shows "not available right now"

The access token in `~/.claude/.credentials.json` lasts about 12 hours and is
minted by the Claude Code CLI. It lapses on its own and is refreshed by normal
use — nothing needs doing. Upstream words this as *"Sign-in expired"*, which
misleads: you are still signed in.

There is a `refreshToken` in the file, but the collector does not use it on
purpose. Refresh tokens are typically rotating, so minting one without storing
the replacement could invalidate the credential the CLI depends on.

### StyledPopup needs `containsMouse`

```qml
active: hoverTarget && hoverTarget.containsMouse
```

The `hoverTarget` root must therefore be a **`MouseArea` with `hoverEnabled`**,
not a plain `Item` — an `Item` has no such property and the popup silently never
opens. Copy `modules/ii/bar/Resources.qml`.

> And `StyledToolTip` has **no `content` property**. Passing one crashes the
> shell outright. Use `StyledPopup` for anything richer than a text tooltip.
