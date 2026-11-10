# doom-wasm

Classic Doom ([doom-ascii](https://github.com/wojciech-graj/doom-ascii) 0.3.2) compiled to WebAssembly (`wasm32-wasip1`) with Binaryen Asyncify and [wasi-termios-brsh](https://github.com/eliotstocker/wasi-termios-brsh), built for [brsh](https://github.com/eliotstocker/Brsh-JS) and browser WASI environments.

## Features

- **Truecolor ANSI Text Rendering**: Renders full 24-bit RGB ANSI frames directly to `stdout` at ~70 FPS.
- **Binaryen Asyncify Event Loop**: Non-blocking real-time game loop instrumenting `clock_nanosleep`, `poll_oneoff`, and `fd_read` — runs smoothly without locking up browser or Node.js JavaScript threads.
- **Dynamic Terminal Sizing**: Integrates with [wasi-termios-brsh](https://github.com/eliotstocker/wasi-termios-brsh) to adapt rendering to current terminal dimensions (`TIOCGWINSZ` and `set_terminal_size`).
- **Standard `wasi_snapshot_preview1` ABI**: Zero non-standard host imports; works in `brsh` or any standard WASI runtime supporting Asyncify.
- **Standalone Binary**: `1.1 MB` (`dist/doom.wasm`).

## Getting Started

Doom requires an IWAD data file to run (such as the original shareware `doom1.wad`, or commercial `doom.wad` / `doom2.wad`).

### Via `wbt` in `brsh`

Inside a `brsh` shell:

```sh
# Download shareware IWAD
curl -o doom1.wad https://raw.githubusercontent.com/wasm3/pywasm3-doom-demo/main/doom1.wad

# Install doom binary
wbt install https://cdn.jsdelivr.net/gh/eliotstocker/doom-wasm@main/dist/doom.wasm --name doom

# Launch Doom
doom -nosound
```

### Running the Timedemo Benchmark

```sh
doom -timedemo demo1 -nosound
```

To run at maximum speed without rendering ANSI frames:

```sh
doom -timedemo demo1 -nosound -nodraw
```

### Mounting Directly in `brsh` JavaScript Virtual Filesystem

```js
import Shell, { BinaryFile } from 'brsh';

const doomRes = await fetch('https://cdn.jsdelivr.net/gh/eliotstocker/doom-wasm@main/dist/doom.wasm');
const doomBytes = new Uint8Array(await doomRes.arrayBuffer());

const wadRes = await fetch('https://raw.githubusercontent.com/wasm3/pywasm3-doom-demo/main/doom1.wad');
const wadBytes = new Uint8Array(await wadRes.arrayBuffer());

const shell = new Shell({
  filesystem: {
    bin: {
      doom: new BinaryFile(doomBytes.buffer, 'application/wasm')
    },
    game: {
      'doom1.wad': new BinaryFile(wadBytes.buffer, 'application/octet-stream')
    }
  },
  permissions: {
    '/bin/doom': 0o755
  },
  cwd: '/game'
});

await shell.onCommand('doom -nosound');
```

## Building from Source

This repository does **not** vendor the `doom-ascii` C source code. Instead, `scripts/build.sh` automatically fetches upstream sources, applies minimal portability patches from `patches/`, links with `wasi-termios-brsh`, and applies Asyncify:

```sh
npm run build
# or directly:
bash scripts/build.sh
```

### Prerequisites

- `git`, `curl`, `tar`, `patch`
- `wasi-sdk` (v25.0 recommended; automatically downloaded to `build/` if not found in `WASI_SDK_PATH` or `/opt/wasi-sdk`)
- `wasm-opt` (Binaryen v119+; automatically downloaded to `build/` if not found on `PATH` or in `WASM_OPT_PATH`)

## Controls

| Key | Action |
| --- | --- |
| `Arrow Keys` / `W, A, S, D` | Move / Turn |
| `Ctrl` / `Space` | Fire / Use (open doors, flip switches) |
| `Enter` | Select / Activate |
| `Escape` | Menu / Pause |
| `1` - `7` | Change Weapon |
| `Tab` | Toggle Map |

## License

- Port glue, patches, and build scripts: [GPL-2.0-or-later](LICENSE)
- Doom source code: Copyright (C) 1993-1996 id Software, Inc.
- `doom-ascii`: Copyright (C) Wojciech Graj.
