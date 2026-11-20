# Nimtop

Nimtop is a cross-platform htop-like process monitor for Windows, macOS, and Linux, implemented in [Nim](https://nim-lang.org) as a fast and native executable. It also optionally supports advanced Vi-style commands.

## Installation

Once `nimtop` is listed in the Nimble package index, install it with:

```sh
nimble install nimtop
```

## Usage

### Options

| Option | Meaning |
|:---|:---|
| `-C` | Use monochrome color scheme. |
| `-h` | Display help info. |
| `-p` PID, PID... | Show only the given PIDs. |
| `-n` NamePart, NamePart... | Show processes whose executable name contains any supplied substring (case-sensitive). |
| `-s` COLUMN | Sort by this column. |
| `-u` USERNAME | Only display processes belonging to this user. |
| `-d` | Print the process table and exit instead of opening the interactive monitor. |
| `-v` | Print version. |

### Interactive commands

| Key(s) | Purpose |
|:---|:---|
| Up and Down Arrows, <kbd>PgUp</kbd> and <kbd>PgDown</kbd>, <kbd>j</kbd> and <kbd>k</kbd> | Scroll the process list. |
| <kbd>CTRL</kbd> + Left and Right Arrows | Change the process sort column. |
| <kbd>g</kbd> | Go to the top of the process list. |
| <kbd>G</kbd> | Go to the bottom of the process list. |
| <kbd>Space</kbd> | Tag a selected process. |
| <kbd>U</kbd> | Untag all tagged processes. |
| <kbd>K</kbd> | Kill all tagged processes. |
| <kbd>I</kbd> | Invert the sort order. |
| <kbd>F</kbd> | Follow process: if the sort order causes the currently selected process to move in the list, make the selection bar follow it. Moving the cursor manually automatically disables this feature. |
| <kbd>/</kbd> | Search process names; lowercase patterns match case-insensitively. |
| <kbd>n</kbd>, <kbd>N</kbd> | Next and previous search matches, wrapping at the ends. |

### Vi commands

| Command(s) | Purpose |
|:---|:---|
| `:exec` CMD | Starts the given system command. |
| `:kill` PID(s) | Kill all given processes. |
| `:q`, `:quit` | Quit nimtop. |
| `/PATTERN`, `:search` PATTERN | Do a search. |
| `:sort` COLUMN | Sort the process list after the given column. |
| `:tree` | View process tree. |

Command and search lines support Up/Down history. `:kill` accepts one or more
process IDs; `:exec` starts a command using the platform's command launcher.

## Configuration

The color scheme can be customized through the [nimtop.conf](nimtop.conf) file.
Existing `ntop.conf` files are still read as a compatibility fallback.

## Building

### Nim

The Nim application lives in [`src/`](src) and is built with Nim 2.x.
The Windows backend uses [`winim`](https://github.com/khchen/winim), installed
automatically as a Windows-only dependency:

```sh
$ nimble install -y --depsOnly
$ nimble release
$ nimble test
```

The release task embeds the package version and produces `nimtop.exe` on
Windows or `nimtop` on Linux and macOS. macOS uses the system `libproc`, Mach,
and POSIX APIs; it requires no additional Nimble dependency.

The original C sources remain as a parity reference; Nimble is the supported
build system.

The Nim build includes process/system information, the interactive monitor,
process-name search, and Vi commands. The port also fixes issues in the original
implementation, including sort overflow, tree flattening, invalid PID handling,
and unsafe input/history buffers. See [`PORT_TO_NIM.md`](PORT_TO_NIM.md) for
implementation and compatibility details.

## TODO

* ~~Figure out buggy resizing.~~
* ~~View process tree.~~
* ~~Searching.~~
* Interactive filtering.
* All of htop's command line options.
* At least the most important interactive commands (e.g. ~~following processes~~).
