# Porting NTop to Nim — Plan

Status: **draft plan** · Target: NTop 0.3.x feature parity · License: GPL-3.0 (unchanged)

## 1. Executive summary

NTop is a ~2,700-line Windows-only C program (Win32 console + Toolhelp/PSAPI/registry)
that renders an htop-like process monitor with Vi-style commands. It is a good porting
candidate: one platform, no third-party runtime dependencies, a small number of Win32
APIs, and a naturally modular structure hidden inside three `.c` files.

The port should:

1. Keep the **same user-visible behavior** (CLI flags, keys, Vi commands, layout, config
   file, exit codes) so it can be validated side-by-side against the C binary.
2. Replace manual memory management, `TCHAR` macros, `qsort` callbacks, and raw
   `CRITICAL_SECTION` usage with idiomatic Nim (`seq`, `string`, `algorithm.sort`,
   `std/locks`).
3. Split `ntop.c` into focused modules and introduce a **screen-buffer abstraction** so
   rendering can be tested headlessly.
4. Fix the latent memory/UB bugs listed in §9 while porting, behind a parity test suite.
5. Ship a single self-contained `NTop.exe` built by Nimble, with the same packaging
   (Chocolatey/Scoop/Winget payload) and Windows CI.

Estimated effort: **7–9 engineering days** for one developer familiar with Nim and Win32,
plus 1–2 days of manual parity testing on real Windows terminals.

## 2. What exists today

| File | LOC | Responsibility |
|:--|--:|:--|
| `ntop.c` | 2001 | Win32 console setup, process polling, system info, sorting, search, rendering, input loop, CLI parsing, help |
| `vi.c` | 455 | Vi command tokenizer, command table, history, input-line editing |
| `util.c` | 71 | `Die`, allocation wrappers (the wrappers disappear in Nim) |
| `ntop.h` | 54 | Sort-type enum, shared prototypes, Vi message types |
| `vi.h` | 35 | Vi input API |
| `util.h` | 53 | `TCHAR` helpers, `NORETURN` |
| `ntop.conf` | 16 | Colors + redraw interval |
| `CMakeLists.txt`, `build.bat` | — | Build (MSVC 2017; optional Unicode) |
| `ntop.nuspec`, `.github/workflows/*` | — | Chocolatey package + Windows CI |

### Runtime architecture (C)

- **Main thread**: initializes a second console screen buffer, then loops:
  draw whole frame → poll input for up to `RedrawInterval` ms → redraw only the
  cursor row on scroll → exit the inner loop on resize/redraw/timeout.
- **Polling thread**: infinite `PollProcessList(1000)` — snapshots processes with
  Toolhelp, enriches them (memory, user, CPU deltas, I/O deltas, uptime), filters,
  copies into the global list under a critical section, sorts, readjusts cursor.
- **Global mutable state**: ~40 file-scope variables (process list, selection, filters,
  config, colors, dimensions, search state, vi state). The port should keep the state
  explicit in a `App` object where practical, while keeping hot paths simple.

### Key behaviors to preserve

- Options: `-C`, `-h`, `-p PID[,PID...]`, `-n NamePart[,...]`, `-s COLUMN`, `-u USER`,
  `-d` (non-interactive), `-v`. Unknown options exit non-zero.
- Interactive: arrows/PgUp/PgDn/j/k, Ctrl+Left/Right, `g`, `G`, `Space`, `U`, `K`, `I`,
  `F`, `n`, `N`, `M`, `P`, `q`, `F10`, `:`, `/`.
- Vi: `:exec`, `:kill`, `:q`/`:quit`, `:sort`, `:tree`, `/PATTERN`, `:search`.
- Config keys: `FGColor`, `BGColor`, `FGHighlightColor`, `BGHighlightColor`,
  `MenuBarColor`, `ProcessListHeaderColor`, `ErrorColor`, `CPUBarColor`,
  `MemoryBarColor`, `PageMemoryBarColor`, `RedrawInterval`; `ntop.conf` next to the exe;
  values parsed like C `strtol(..., 0)` (decimal or `0x` hex).
- Layout: menu bar, blank, CPU bar + name/cores + tasks, memory bar + size, page bar +
  uptime, blank, column header, process rows, status/input line at `height-2`.
- Non-interactive mode prints the header once, all rows, and exits 0.

## 3. Goals and non-goals

**Goals**

- Byte-for-byte-compatible CLI/config/command behavior (modulo fixed bugs).
- Identical visual layout and color semantics on Windows 10/11 (conhost and Windows
  Terminal), including resize handling.
- Single `NTop.exe`, no DLLs beyond system libraries, no external runtime.
- Windows x64 primary; x86 build optional.
- Unit tests for pure logic; a headless mode test for integration.
- Keep GPL-3.0 headers and attribution.

**Non-goals (initial port)**

- Cross-platform support (Linux/macOS process backends). Keep the design open, but do
  not implement it now.
- New features from the README TODO list (filtering UI, remaining htop options).
- Changing the config format or command syntax.
- Rewriting the UI toolkit (no ncurses/illwill); stay on the Win32 console API.

## 4. Target stack and toolchain

| Concern | Choice |
|:--|:--|
| Language | Nim **2.2.x** (ARC/ORC default, threads on by default) |
| Win32 bindings | [`winim`](https://github.com/khchen/winim) (thin, header-faithful); hand-written `importc` for any gaps |
| Terminal | Direct Win32 console API (`kernel32`), same as C |
| Threads | `std/threads` + `std/locks` (`Lock` → `CRITICAL_SECTION`) |
| Formatting | `std/strformat`, `std/strutils` |
| Tests | `std/unittest`; optional `testament` for matrix runs |
| Build | Nimble (`ntop.nimble`) + `config.nims`; optional CMake wrapper kept for downstream users |
| CI | GitHub Actions `windows-latest` + `jiro4989/setup-nim-action` |
| Cross-compile | `nim c --os:windows --cpu:amd64` with mingw-w64 (dev convenience; CI remains native) |

Rationale for `winim`: it exposes the exact Win32 types/constants used here
(`HANDLE`, `DWORD`, `FILETIME`, `INPUT_RECORD`, `PROCESSENTRY32`, `TOKEN_USER`,
`MEMORYSTATUSEX`, …), so the port is mostly mechanical and auditable against MSDN.
Avoid `winim/lean` only if a needed header is missing; otherwise lean keeps compile
times down.

## 5. Proposed module layout

```
ntop.nimble
config.nims
src/
  ntop.nim              # entry point, main loop, wiring
  ntop/types.nim        # Process, Config, SortType, enums, App state
  ntop/consts.nim       # layout, color masks, version, limits
  ntop/util.nim         # die, time/memory formatting, FILETIME math, conversions
  ntop/console.nim      # Win32 console wrapper: buffers, colors, cursor, WriteConsoleW
  ntop/config.nim       # ntop.conf discovery + parsing
  ntop/sysinfo.nim      # CPU name/freq/cores, memory, uptime, computer name
  ntop/processes.nim    # snapshot + enrichment + filters
  ntop/sorting.nim      # comparators, tree construction/flattening
  ntop/search.nim       # pattern state, next/previous
  ntop/render.nim       # frame layout, screen buffer, draw helpers
  ntop/input.nim        # key dispatch, scroll state machine
  ntop/vi.nim           # command table, tokenizer, history, input line
  ntop/cli.nim          # argument parsing, help/version
tests/
  test_util.nim
  test_config.nim
  test_sorting.nim
  test_vi.nim
  test_search.nim
  test_cli.nim
  test_headless.nim     # runs the exe with -d and checks output
```

`ntop.c` maps roughly 1:1 to `ntop.nim` + `render` + `input` + `processes` + `sorting`
+ `sysinfo`; `vi.c` → `vi.nim`; `util.c` → `util.nim`; headers → `types`/`consts`.

## 6. Data model

```nim
type
  SortType* = enum
    stId, stUserName, stPriority, stProcessorTime, stUsedMemory,
    stThreadCount, stDiskUsage, stUpTime, stProcess, stTree

  Config* = object
    fgColor, bgColor, fgHighlightColor, bgHighlightColor: WORD
    menuBarColor, processListHeaderColor, errorColor: WORD
    cpuBarColor, memoryBarColor, pageMemoryBarColor: WORD
    redrawInterval: uint64

  Process* = object
    handle: HANDLE            # closed at end of each snapshot
    id: DWORD
    userName: string          # UTF-8 internally
    basePriority: DWORD
    percentProcessorTime: float
    usedMemory: uint64
    threadCount: DWORD
    upTime: uint64            # ms
    exeName: string
    parentPid: DWORD
    diskOpsPrev, diskOps: uint64
    diskUsage: DWORD
    treeDepth: DWORD

  App* = object
    processList, newProcessList: seq[Process]
    tagged: seq[DWORD]
    processCount, runningCount: DWORD
    processIndex, selectedIndex: DWORD
    sortType: SortType
    sortOrder: SortOrder
    filters: Filters
    search: SearchState
    config: Config
    vi: ViState
    console: Console
    # dimensions, colors, uptime, CPU/memory stats…
```

Design notes:

- Use **indices into `seq[Process]`** for tree relationships (`parentPid` + children
  lists or a parent index), not raw pointers. The C code copies `process` structs that
  contain `Parent`/`Next`/`FirstChild` pointers, which become stale after
  `memcpy`/`qsort`; indices remove that class of bug.
- Keep `userName`/`exeName` as Nim `string` (UTF-8) and convert at the Win32 boundary
  with `WideCString`/`$`. This is simpler than `TCHAR` and fixes the Unicode build.
- `xmalloc`/`xrealloc`/`xcalloc` disappear. For very large snapshots, reserve with
  `newSeqOfCap` to avoid reallocation churn.
- `process.handle` is only valid during polling; close all handles with `defer`/`try`.
  Never publish a `Process` containing an open handle to the render thread.

## 7. Win32 → Nim mapping

### 7.1 Types, constants, helpers

| C | Nim / winim |
|:--|:--|
| `TCHAR`, `_T("…")` | `string` internally; `WideCString` at API boundary |
| `HANDLE`, `DWORD`, `WORD`, `BOOL` | `HANDLE`, `DWORD`, `WORD`, `BOOL` (winim) |
| `ULONGLONG`, `LARGE_INTEGER` | `uint64`, `LARGE_INTEGER` (`li.QuadPart`) |
| `FILETIME` math (`SubtractTimes`) | `uint64(a.dwLowDateTime) or (uint64(a.dwHighDateTime) shl 32)` |
| `CRITICAL_SECTION` | `Lock` (`initLock`, `withLock`, `deinitLock`) |
| `qsort` + comparator | `algorithm.sort(proc(a, b: Process): int)` |
| `min`/`max` | `std/math` |
| `_stprintf_s`, `wsprintf` | `strformat` (`&"{x:8.1f}"`), `strutils.align` |
| `_tcsicmp`, `lstrcmpi` | `cmpIgnoreCase` |
| `_tcsstr`, `strstr` | `contains`/`find` (decide case sensitivity per call site, see §9) |
| `_tstoi`, `_tcstoul` | `parseInt` with explicit error handling |
| `exit`, `atexit` | `quit`, `addQuitProc` |
| `SetConsoleCtrlHandler` | `setControlCHook` or winim handler + callback |
| `CreateThread` | `createThread` (`std/threads`) |
| `Sleep` | `sleep` (`std/os`) |

### 7.2 Console

| C | Nim |
|:--|:--|
| `CreateConsoleScreenBuffer` / `SetConsoleActiveScreenBuffer` | same via winim |
| `SetConsoleTextAttribute` | same |
| `SetConsoleCursorPosition` | same |
| `GetConsoleScreenBufferInfo` | same (`CONSOLE_SCREEN_BUFFER_INFO`) |
| `SetConsoleScreenBufferSize` | same (resize handling) |
| `GetConsoleCursorInfo` / `SetConsoleCursorInfo` | same |
| `WriteFile` on console handle | **`WriteConsoleW`** (correct UTF-16 count; fixes the C byte-count bug) |
| `ReadConsoleInput` | `ReadConsoleInputW` + `INPUT_RECORD`/`KEY_EVENT` |
| `FlushConsoleInputBuffer` | same |
| `SetConsoleMode` | same (`ENABLE_PROCESSED_INPUT`, wrap modes) |

### 7.3 Processes and system info

| C | Nim |
|:--|:--|
| `CreateToolhelp32Snapshot(TH32CS_SNAPALL)` | same |
| `Process32First/Next`, `PROCESSENTRY32` | same; set `dwSize` |
| `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` | same |
| `GetProcessMemoryInfo` (psapi) | same (link `psapi` / use `K32GetProcessMemoryInfo`) |
| `OpenProcessToken` + `GetTokenInformation(TokenUser)` | same, two-call size query |
| `LookupAccountSid` | same |
| `GetSystemTimes`, `GetProcessTimes`, `GetProcessIoCounters` | same |
| `GetSystemTimeAsFileTime` | same |
| `GlobalMemoryStatusEx` | same |
| `GetNativeSystemInfo` | same |
| `GetComputerName` | same |
| `RegOpenKey`/`RegQueryValueEx` (`ProcessorNameString`) | same (HKEY_LOCAL_MACHINE, 64-bit view) |
| `QueryPerformanceFrequency` | same (or `std/monotimes`) |
| `GetTickCount64` | same |
| `OpenProcess(PROCESS_TERMINATE)` + `TerminateProcess` | same |
| `CreateProcess` (`:exec`) | same; build a mutable `WideCString` command line |

### 7.4 Version/help

- `NTOP_VER` is a compile-time define in C (`-DNTOP_VER=…`). In Nim use
  `const NtopVersion {.strdefine.} = "dev"` and `-d:NtopVersion=0.4.0`.
- `__DATE__`/`__TIME__` → `CompileDate`/`CompileTime` (Nim built-ins) or omit.
- Help text: keep the same strings and column widths; snapshot-test it.

## 8. Concurrency model

The C design (poller thread + main thread, global list behind a critical section) is
fine. Port it with two rules:

1. **No GC-managed objects cross threads except through a locked snapshot swap.**
   `Process` contains `string`s, so:
   - poller builds a local `seq[Process]`;
   - under `withLock app.lock:` swap/move it into `app.processList` and update counts;
   - renderer copies/reads only under the same lock.
   With Nim 2 + ORC the heap is shared and refcounts are atomic, so this is safe; do not
   share `ref` graphs across threads.
2. **Only the main thread writes to the console.** The poller never prints. Vi messages
   are set on the main thread.

```nim
proc pollThread(arg: tuple[app: ptr App, interval: int]) {.thread.} =
  while true:
    let snapshot = pollProcessList(interval)   # owns/ closes handles
    withLock arg.app.lock:
      arg.app.processList = snapshot
      arg.app.processCount = DWORD(snapshot.len)
      arg.app.sortAndReadjust()
```

Startup order (as in C): init console buffer → load config → allocate state →
`pollConsoleInfo` → `pollInitialSystemInfo` → `pollSystemInfo` → first
`pollProcessList(50)` → start poller → main loop.

Shutdown: `addQuitProc`/`try-finally` restores the original screen buffer and closes
handles. Use `defer` in the poller for every `OpenProcess` handle.

## 9. Bugs and hazards to fix during the port

These are real defects in the C code; fix them in the Nim version and cover with tests.
If strict bug-for-bug parity is ever required, gate fixes behind a compile flag — but
the default should be correct behavior.

| # | Location | Issue | Fix |
|--:|:--|:--|:--|
| 1 | `ntop.c` `ParseConfigLine` | `FGHighlightColor` is checked twice; `BGHighlightColor` is never applied | check `BGHighlightColor`; test it |
| 2 | `ntop.c` `ToggleTaggedProcess` | realloc uses `PROCLIST_BUF_INCREASE` instead of `TaggedProcessListSize` → buffer shrinks/grows wrong, heap overflow | use `seq[DWORD]` |
| 3 | `ntop.c` `ConPrintf` | `WriteFile` byte count uses character count → Unicode output truncated | `WriteConsoleW` with element count |
| 4 | `ntop.c` `ViHandleInputKey` | typing >1023 chars overflows `CurrentInputStr` | `string` + cap |
| 5 | `vi.c` history | `History[256]` unbounded; `HistoryNext` can read `History[HistoryCount]` when empty | `seq[string]`, clamp index |
| 6 | `vi.c` `ViEnableInput` | `InputIndex = 1` even when `InitialKey` is `\0`; backspace logic can desync | derive length from the string |
| 7 | `ntop.c` `SORT_PROCESS_BY_UINT64` | signed subtraction overflow and `Compare > 1` bug | plain `<`/`>` comparison |
| 8 | `ntop.c` `SORT_PROCESS_BY_INTEGER` | `UpTime` (64-bit) cast to `int` → wrong sort | typed comparators per field |
| 9 | `ntop.c` tree | `TreeDepth` depends on qsort order; O(n²) parent search; pointer fields invalidated by copies | O(n) map `pid → index`, iterative flatten |
| 10 | `ntop.c` `SelectProcess`/`ReadjustCursor` | unsigned underflow when `ProcessCount < VisibleProcessCount` | signed ints + clamp |
| 11 | `ntop.c` filters | `-n` uses case-sensitive `strstr` while `-u` uses `lstrcmpi`; `-p` uses `_tstoi` without validation | `parseInt` + explicit validation; document case rules |
| 12 | `ntop.c` `-n` | fixed `[10][256]` arrays; truncation | `seq[string]`, no limit (or documented cap) |
| 13 | `ntop.c` `-s` | missing value silently ignored; non-option args ignored | explicit usage errors |
| 14 | `ntop.c` `:exec` | returns 1 on success; console apps need a console | return 0; consider `CREATE_NEW_CONSOLE` (document change) |
| 15 | `ntop.c` `PollProcessList` | `Sleep(1000)` inside the polling function couples poll and refresh intervals | parameterize |
| 16 | `ntop.c` `ClearViMessage` | toggles console mode on the output handle; fragile | write a blank line with a proper screen buffer |
| 17 | `ntop.c` | `GetProcessMemoryInfo`/token failures leave defaults; no diagnostics | log to debug output only |
| 18 | `ntop.c` `Main` | `-d` prints header then rows, but `WriteProcessInfo` prepends `\n` — first row spacing differs | match exact bytes in a golden test |

Also note: `pdh.h` is included but PDH is never used — drop it. `conio.h` is unused in
the Nim port.

## 10. Rendering plan

Introduce a tiny screen abstraction so rendering is pure and testable:

```nim
type
  Cell = object
    ch: Rune
    attr: WORD
  Screen = object
    width, height: int
    cells: seq[Cell]

proc put(s: var Screen; x, y: int; text: string; attr: WORD)
proc fill(s: var Screen; x, y, w: int; attr: WORD)
proc flush(s: Screen; con: Console)   # WriteConsoleW row by row
```

- Build a full frame in memory, then flush only changed rows (start with full flush;
  optimize later). This replaces the C mix of absolute cursor positioning and relative
  `\n` writes, which is the source of the off-by-one/blank-line quirks.
- Keep the exact layout constants:
  - `ProcessWindowPosY = 6`
  - `ProcessWindowHeight = height - 6`
  - `VisibleProcessCount = height - 8`
  - columns: `ID 7`, `USER 9`, `PRI 3`, `CPU% 5`, `MEM 11`, `THRD 4`, `DISK 9`,
    `TIME 11`, `PROCESS` rest
  - tree prefix: `"|  "` × (`depth-1`) + ``"`- "``
- Colors: reuse the `WORD` attribute bitmask semantics and the default/monochrome
  configs from `ntop.c`. Keep `FGColor|MenuBarColor` for the menu bar and the
  highlight/tag combinations exactly as in `WriteProcessInfo`.
- Handle resize by re-reading `srWindow`, resizing the screen buffer, reallocating the
  `Screen`, and redrawing. Hide the cursor after every buffer resize.
- Non-interactive mode: render rows without absolute positioning (or reuse `Screen`
  and flush), then exit.
- Vi/status line at `height-2`; input caret `_` at the end of the input string.

## 11. Vi layer plan

Port `vi.c` almost directly, but with Nim strings and `seq`:

```nim
type
  CmdFn = proc(args: seq[string]): int {.closure.}
  Command = object
    name: string
    fn: CmdFn
```

- Commands: `exec`, `kill`, `q`/`quit`, `sort`, `tree`, `search`; `/pattern` is an
  alias handled before tokenization.
- Tokenizer rules (preserve): skip leading spaces; command name is alphanumeric;
  arguments are alphanumeric plus `%`, `/`, `.`; double quotes allow spaces and those
  characters; unterminated quote = parse error; trailing junk = parse error.
- History: `seq[string]`, index clamped to `0 ..< len`; Up/Down; do not push empty
  commands.
- `ViExecInput`: strip leading `:` and whitespace; ignore empty; push to history;
  disable input; clear message.
- Messages: `viMessage: string` + `MessageType {notice, error}`; error uses
  `Config.ErrorColor`.
- Unit-test the tokenizer against a table of inputs/outputs, including the C quirks
  listed in §9.

## 12. CLI, config, and compatibility

- Use a small hand-written parser (not `std/parseopt`) to match C semantics exactly:
  options are single letters, `-p`/`-n` take a comma-separated value, unknown options
  print `Unknown option: 'x'` and exit 1, `-h`/`-v` print and exit 0.
- Keep help text and ordering identical; add the missing `-d` documentation (already in
  help, missing from README).
- Config discovery: `getAppFilename().parentDir / "ntop.conf"`; parse `KEY VALUE` lines,
  ignore comments/blank lines, parse values with `0x` hex support, unknown keys ignored.
- Preserve defaults from `ntop.c` (`Config` and `MonochromeConfig`), including the
  `FGColor`/`BGColor` values. Fix the `BGHighlightColor` bug (§9 #1).
- Exit codes: 0 for help/version/normal quit/non-interactive, 1 for bad options and
  unknown sort columns.

## 13. Phased plan

Estimates assume one developer; parallelizable phases are marked.

### Phase 0 — Bootstrap (0.5 day) — implemented

- [x] Add `ntop.nimble`, `config.nims`, `src/ntop.nim` skeleton.
- [x] Declare `winim` in `ntop.nimble`; verified with Nim 2.4.2 + mingw-w64
  (Windows CI uses the native Windows toolchain).
- [x] Implement `src/ntop/console.nim` (alternative screen buffer, colors,
  cursor, `WriteConsoleW`, resize, key input, idempotent restore) and the
  bootstrap smoke screen in `src/ntop.nim`.
- [x] Add `nimble test` (`tests/test_all.nim`) and Windows CI
  (`.github/workflows/nim.yml`) that builds and uploads `NTop.exe`.
- **Exit criteria:** CI produces `NTop.exe`; console smoke test runs on Windows.
  The smoke screen draws color swatches, Unicode text, and a process-table
  preview, then waits for a key and restores the original buffer.

### Phase 1 — Pure core (1 day)

- `types.nim`, `consts.nim`, `util.nim`: formatters (`formatTimeString`,
  `formatMemoryString`), FILETIME math, color masks.
- `config.nim` + tests (including hex values and the `BGHighlightColor` case).
- `cli.nim` + help/version + tests.
- **Exit criteria:** unit tests pass; `NTop.exe -h`, `-v`, bad option behave like C.

### Phase 2 — Process acquisition (1.5 days)

- `sysinfo.nim`: CPU name/frequency/cores, computer name, memory, uptime.
- `processes.nim`: Toolhelp snapshot, memory, user via token/SID, CPU% via
  `GetSystemTimes`/`GetProcessTimes` deltas, I/O deltas, uptime, filters.
- `sorting.nim`: comparators for every column, asc/desc, O(n) tree build/flatten.
- Tests with synthetic process data for sorting/tree; live smoke test for enrichment.
- **Exit criteria:** `-d` prints a plausible process list; `-p`, `-n`, `-u`, `-s`
  filter/sort correctly; handles are closed (verify with a handle-count tool).

### Phase 3 — Interactive UI (2 days)

- `render.nim`: screen buffer, frame layout, bars, header, rows, tree prefixes,
  highlight/tag colors, resize.
- `input.nim`: key dispatch, scroll state machine (initial delay + repeat), page
  scrolling, tagging, kill tagged, invert sort, follow process, `g`/`G`, `M`/`P`,
  `q`/`F10`, `:`/`/`.
- Main loop with poller thread and redraw interval.
- **Exit criteria:** side-by-side screenshots match the C build on the same machine;
  resize, scroll, tag/kill, follow, sort switching work.

### Phase 4 — Search and Vi (1 day)

- `search.nim`: pattern storage, case-insensitive-if-lowercase rule, next/previous,
  wrap messages.
- `vi.nim`: tokenizer, command table, history, input line, messages.
- `:exec`, `:kill`, `:sort`, `:tree`, `:q`.
- **Exit criteria:** command/history/error behavior matches the C build; parser tests
  pass.

### Phase 5 — Non-interactive, packaging, parity (1–2 days)

- `-d` output parity (byte-level golden test where practical).
- CMake wrapper or documented Nimble-only build; keep `build.bat` equivalent.
- Update `ntop.nuspec`/Scoop/Winget payload paths if the binary name/layout changes.
- README updates: Nim build instructions, note fixed bugs, `-d`/`-n` docs.
- **Exit criteria:** release artifact is a single exe; package installs; README builds
  from a clean Windows VM.

### Phase 6 — Hardening (1 day, can overlap)

- Fuzz the Vi tokenizer; add regression tests for every §9 bug.
- Long-run test (hours) for handle/memory leaks, process churn, terminal resize storms.
- Test elevated/non-elevated, protected processes, users with Unicode names, >1000
  processes, narrow/wide terminals, Windows Terminal vs conhost.
- **Exit criteria:** no leaks/crashes in a 2-hour soak; documented known limitations.

## 14. Testing strategy

**Unit (pure, no Windows APIs)**

- `formatTimeString`: `0`, `999`, `1000`, `59_999`, `3_600_000`, `90_061_001`.
- `formatMemoryString`: KB/MB/GB/TB boundaries and width (`% 8.1f`).
- Config parser: comments, whitespace, decimal/hex, unknown keys, `BGHighlightColor`.
- Vi tokenizer: empty, spaces, quotes, `/pat`, `:kill 1 2`, `:sort CPU%`, bad chars,
  unterminated quotes, unknown command.
- Sorting: every `SortType` × asc/desc; ties; empty list; tree with missing parents,
  cycles, deep chains; ensure stable ordering where it matters.
- Search: case rules, wrap-around, no match, empty pattern.
- CLI: all flags, missing values, unknown flags, help/version text snapshot.

**Integration (Windows CI or local)**

- `NTop.exe -d` against a fixture machine: header present, row count = process count,
  filters reduce rows as expected.
- `-p` with a known PID; `-n` with a substring; `-u` with the current user; `-s` for
  each column (exit 0) and an invalid column (exit 1).
- Console smoke test: start interactive, send keys via a small helper (or manual),
  assert exit on `q`/`F10`, resize handling.

**Parity harness (manual or scripted)**

- Run C `NTop.exe -d` and Nim `NTop.exe -d` on the same machine seconds apart; compare
  header and normalized rows (PID set may differ).
- Screenshot comparison for interactive mode at 80×24, 120×30, 200×50.

**Soak**

- 2-hour run with the poller at 1 s, sorting by CPU (most churn), tag/kill a few
  disposable processes; watch handles and private bytes.

## 15. Build, CI, and release

`ntop.nimble`:

```nim
version       = "0.4.0"
author        = "Gian Sass"
description   = "htop-like system monitor for Windows with Vi keybindings"
license       = "GPL-3.0-only"
srcDir        = "src"
bin           = @["ntop"]

requires "nim >= 2.0.0"
requires "winim >= 3.9.0"

task release, "Build the release binary":
  exec "nim c -d:release --opt:speed --app:console --out:NTop.exe src/ntop.nim"
```

`config.nims`:

```nim
when defined(windows):
  switch("passL", "-lpsapi -ladvapi32 -luser32")
  # winim uses dynlib for most calls; link flags cover static imports.
```

CI (`windows-latest`):

```yaml
- uses: jiro4989/setup-nim-action@v2
  with: { nim-version: "2.2.x" }
- run: nimble build -d:release
- run: nimble test
- uses: actions/upload-artifact@v4
  with: { name: NTop.exe, path: NTop.exe }
```

Cross-compile from macOS/Linux for quick checks:

```sh
nim c -d:release --os:windows --cpu:amd64 --cc:gcc \
  --passC:-static --out:NTop.exe src/ntop.nim
```

(Requires `mingw-w64`; not a substitute for Windows CI.)

Release: keep the same artifact name `NTop.exe` and directory layout so
Chocolatey/Scoop/Winget manifests keep working. Update `ntop.nuspec` only if the
version or file paths change.

## 16. Risks and mitigations

| Risk | Impact | Mitigation |
|:--|:--|:--|
| `winim` missing a struct/constant | Medium | add `importc`/`type` locally; winim is header-generated, gaps are rare |
| Win32 console quirks (`WriteConsoleW`, resize, wrap modes) | High | isolate in `console.nim`; test on conhost + Windows Terminal early (Phase 0/3) |
| Unicode/`TCHAR` drift | Medium | UTF-8 internally, `WideCString` at boundaries; Unicode-only build (drop ANSI mode) |
| Thread/GC misuse | High | snapshot swap under lock; no shared `ref`; `--mm:orc`; soak test |
| Behavior drift in Vi parser/CLI | Medium | table-driven tests derived from the C code; side-by-side runs |
| Process access failures (protected/system processes) | Medium | keep C fallbacks (`SYSTEM` user, zero memory), never crash |
| Windows-only CI cost/flakiness | Low | build + unit tests only; manual UI matrix |
| Cross-compile differences | Low | native Windows CI is the source of truth |
| Scope creep (cross-platform, new features) | Medium | non-goals in §3; keep backend boundary clean but unimplemented |

## 17. Open questions

1. **Unicode**: ship only the UTF-16 (wide) build, or keep a compile-time ANSI mode?
   Recommendation: wide-only; it removes `TCHAR` entirely and fixes §9 #3.
2. **Bug parity**: fix all §9 bugs by default (recommended) or preserve exact behavior
   behind `-d:ntopStrictParity`?
3. **Build system**: Nimble-only, or keep CMake as a thin wrapper for existing
   contributors? Recommendation: Nimble primary, CMake optional.
4. **`:exec` semantics**: keep `CreateProcess` in the same console (current behavior,
   can fail for console apps) or use `CREATE_NEW_CONSOLE`? Recommendation: new console,
   document it.
5. **Version**: continue 0.3.x or bump to 0.4.0 for the port? Recommendation: 0.4.0.
6. **`-n` case sensitivity**: keep case-sensitive substring matching or align with
   `-u` (case-insensitive)? Recommendation: case-insensitive, documented.

## 18. Porting checklist (function level)

Use this as the working checklist; tick items as they land.

**ntop.c → modules**

- [ ] `ConPrintf`, `ConPutc`, `WriteBlankLine` → `console.write`
- [ ] `SetColor`, `GetConsoleColor`, `ColorOverride` → `console`
- [ ] `SetConCursorPos`, `DisableCursor`, `PollConsoleInfo` → `console`
- [ ] `CreateConsoleScreenBuffer`/`SetConsoleActiveScreenBuffer`/`RestoreConsole` → `console.init/restore`
- [ ] `ParseConfigLine`, `ReadConfigFile` → `config`
- [ ] `Config`, `MonochromeConfig` defaults → `consts/config`
- [ ] `SubtractTimes`, `FormatTimeString`, `FormatMemoryString` → `util`
- [ ] `PollInitialSystemInfo`, `PollSystemInfo` → `sysinfo`
- [ ] `process` struct, `ProcessList`, `NewProcessList`, `IncreaseProcListSize` → `types/processes`
- [ ] `PollProcessList` (snapshot, memory, user, CPU, I/O, uptime, filters) → `processes`
- [ ] `PollProcessListThreadProc` → `processes.startPoller`
- [ ] `SORT_PROCESS_BY_*`, `SortProcessList` → `sorting`
- [ ] `AddChildProcess`, `FindParentChildProcesses`, `ProcessTreeToList` → `sorting.tree`
- [ ] `ToggleTaggedProcess`, `IsProcessTagged`, `KillTaggedProcesses` → `processes.tags`
- [ ] `SelectProcess`, `ReadjustCursor` → `input/selection`
- [ ] `StartSearch`, `SearchMatchesProcess`, `SearchNext`, `SearchPrevious` → `search`
- [ ] `DoScroll` + `SCROLL_*` → `input`
- [ ] `ProcessInput` → `input`
- [ ] `DrawProcessListHeader`, `DrawOptions` (unused?), `DrawPercentageBar`, `WriteProcessInfo` → `render`
- [ ] `PrintVersion`, `PrintHelp`, `PrintHelpEntries` → `cli`
- [ ] `GetProcessSortTypeFromName` → `sorting/cli`
- [ ] `FormatTimeString` usage in main frame → `render`
- [ ] `CtrlHandler` → `setControlCHook`
- [ ] `main` arg parsing → `cli.parse`
- [ ] `main` init sequence + main loop → `ntop.nim`
- [ ] `ViMessage`/`SetViMessage`/`ClearViMessage` → `vi`

**vi.c → vi.nim**

- [ ] `PushToHistory`, `HistoryPrevious`, `HistoryNext` → `vi.history`
- [ ] `kill`, `tree`, `exec`, `q`/`quit`, `sort`, `search` commands
- [ ] `PushArg`, `FreeCmdParseResult`, `EatSpaces`, `IsValidCharacter`, `ParseCommand`
- [ ] `TryExec`, `ViInit`, `ViEnableInput`, `ViDisableInput`
- [ ] `ViHandleInputKey`, `ViExecInput`

**util.c → util.nim**

- [ ] `Die` (format + exit)
- [ ] drop `xmalloc`/`xrealloc`/`xcalloc`
- [ ] `TCharFromAscii`/`IntFromTChar` (no longer needed with wide/UTF-8)

## 19. Definition of done

- [ ] All CLI options and Vi commands behave as documented in README/help.
- [ ] Interactive layout matches the C build at common terminal sizes; resize works.
- [ ] Sorting works for every column, both directions, and tree mode.
- [ ] Filters (`-p`, `-n`, `-u`) and search behave correctly, including wrap messages.
- [ ] Tagging, kill-tagged, follow-process, invert-sort work.
- [ ] Config file keys all apply (including `BGHighlightColor`).
- [ ] No handle leaks over a 2-hour soak; no crashes on protected processes.
- [ ] `nimble test` green on Windows CI; release artifact builds and packages.
- [ ] README documents the Nim build and the intentional behavior changes.
