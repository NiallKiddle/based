<p align="center"><img src="Resources/icon-1024.png" width="128"></p>

<h1 align="center">Based</h1>
<p align="center">Turn your screen red. Lives in the menu bar. That's it.</p>

## Modes

| | |
|---|---|
| ☀️ **Day** | Yellow tint. Blue cut, still usable. |
| 🌙 **Night** | Fully red. |
| ⊘ **Off** | Normal colours. |

Plus an **Open at login** switch.

## Install

1. Grab **Based.dmg** from [Releases](../../releases/latest).
2. Open it, drag **Based** into **Applications**.
3. First launch only: right-click Based → **Open**. If macOS still blocks it: System Settings → Privacy & Security → **Open Anyway**.

## If the colour doesn't change

macOS 26 blocks screen colour changes while **Automatically adjust brightness** is on. Turn it off in System Settings → Displays. Turn off Night Shift and True Tone too.

## Build it yourself

```sh
./scripts/build.sh
open dist/Based.app
```

Every push to `main` builds a new release automatically via GitHub Actions.
