# Nook

A free, open-source **notch planner for macOS**. Hover the notch (or press ⌥⌘N) and get tasks, a daily notepad, a focus timer, today's agenda and insights, without leaving what you are doing.

*Nook é um planner gratuito e open source que vive no notch do Mac: tarefas, bloco de notas diário, timer de foco, agenda e métricas. Sem conta, sem telemetria, dados em um JSON local.*

<p align="center"><img src="docs/media/open.png" width="820" alt="Nook open under the notch"></p>

<p align="center">
  <img src="docs/media/live.png" width="400" alt="Focus countdown beside the notch">
  <img src="docs/media/peek.png" width="400" alt="Focus done alert sliding out of the notch">
</p>

## Install

Requires macOS 14 or later (Apple silicon or Intel).

<p><a href="https://github.com/octavio1199/nook/releases/latest/download/Nook.dmg"><img src="https://img.shields.io/badge/Download_Nook.dmg-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download Nook.dmg"></a></p>

**One line** (downloads the latest release into `/Applications` and opens it):

```bash
curl -fsSL https://raw.githubusercontent.com/octavio1199/nook/main/scripts/install.sh | bash
```

**Manually**

1. Download [`Nook.dmg`](https://github.com/octavio1199/nook/releases/latest/download/Nook.dmg) and open it.
2. Drag `Nook` to Applications.
3. Nook is ad-hoc signed, not notarized by Apple, so macOS blocks the first launch. Either run
   `xattr -dr com.apple.quarantine /Applications/Nook.app`, or open it once and go to
   **System Settings → Privacy & Security → Open Anyway**.
4. Hover the notch, or press **⌥⌘N** from any app. On Macs without a notch, hover the top center of the screen.

To uninstall, quit Nook from its menu bar icon and delete `/Applications/Nook.app` (your data stays in `~/Library/Application Support/Nook/`).

### Português

1. Baixe o [`Nook.dmg`](https://github.com/octavio1199/nook/releases/latest/download/Nook.dmg), abra e arraste o `Nook` para Aplicativos.
2. Como o app não é notarizado pela Apple, libere a primeira abertura com
   `xattr -dr com.apple.quarantine /Applications/Nook.app` (ou em Ajustes → Privacidade e Segurança → Abrir Mesmo Assim).
3. Passe o mouse no notch ou use **⌥⌘N**.

Ou, em uma linha: `curl -fsSL https://raw.githubusercontent.com/octavio1199/nook/main/scripts/install.sh | bash`

## Features

- **Fast capture** with a local parser (no cloud AI): `call Ana tomorrow 3pm !high #work` becomes a task with date, time, priority and tag. Separate items with `;` or line breaks to brain-dump several at once.
- **Tasks**: Today / Upcoming / Done, priorities, tags, due chips.
- **Notepad**: daily autosaving notes; ⌘↩ on a line turns it into a task.
- **Focus timer**: Pomodoro presets (25/5, 50/10, 15/3), countdown, stopwatch.
- **Live activity**: the notch grows wings with a ring and countdown during focus, and warns before events.
- **Agenda**: today's and tomorrow's events from Calendar (read-only, permission asked lazily).
- **Insights**: tasks done, focus minutes, streak, 7-day chart, best day, most focused hour.
- Liquid Glass (macOS 26+) or solid panel. Universal binary, macOS 14+.

## Comparison

| | **Nook** | NotchOwl | Notchable |
|---|---|---|---|
| Price | Free | $9 one-time | $9.99 / $19.99 one-time (3-day trial) |
| Open source | Yes (MIT) | No | No |
| Universal (Apple silicon + Intel) | Yes | Apple silicon only | Yes |
| Quick capture / brain dump | Yes (local parser) | No | Yes (AI, cloud or on-device) |
| Live activity in notch | Yes | Timer pill only | Yes (v2.1) |
| Insights | Yes | Yes | Yes |
| Calendar agenda | Yes (read-only) | Yes (read-only) | Yes |
| Account / telemetry | None | License activation | License + analytics |

## Build from source

Requires macOS 14+ and Swift 6.2 (Command Line Tools are enough, no Xcode needed).

```bash
swift build          # debug build
swift test           # run tests
scripts/bundle.sh    # build/Nook.app (universal, ad-hoc signed)
scripts/make-dmg.sh  # build/Nook.dmg with a drag-to-Applications window
scripts/run.sh       # bundle and open
open build/Nook.app --args --demo open   # sample data, nothing saved
```

Data lives in `~/Library/Application Support/Nook/planner.json`. Settings has Export JSON.

## Privacy

Nook makes no network requests. Calendar access is read-only and only requested when you press **Connect Calendar**.

## Contributing

Issues and pull requests are welcome. Keep `swift build` and `swift test` green. Note that with Command Line Tools only, SwiftUI's `@State` macro is unavailable; the code uses `@LocalState` / `@StateObject` instead.

## Credits and license

MIT, see [LICENSE](LICENSE). The notch shell (panel, hover and peek interaction, geometry) is adapted from **Pullo** by Gabriel Jordan (MIT); see [NOTICE](NOTICE).
