# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Lucas Chess R6 is a desktop chess GUI built on PySide6 (Qt 6). It covers training, play against UCI engines, and engine tournaments.

- All code lives under `bin/`. The Python package `bin/Code/` is about 160k lines.
- Bundled data lives in `Resources/`: opening books, tablebases, piece sets, translations and training sets.
- Upstream has one author, and every commit is a whole-release snapshot ("Version R6.x.y"). As a result, `git log` and `git blame` rarely explain why a single change was made.

## Commands

There is no test suite. There is no linter or formatter config. There is no build CI; the only workflow closes stale issues.

```bash
pip install -r requirements.txt     # PySide6 is pinned (==6.8.3)
python3 bin/LucasR.py               # run from source; works from any cwd (importing Code chdirs to bin/)
python3 -O bin/LucasR.py            # same, with __debug__ off

# Cheapest sanity check available. The prefix keeps __pycache__ out of the tree (it isn't gitignored).
PYTHONPYCACHEPREFIX=/tmp/lc-pyc python3 -m compileall -q bin/Code
```

### Python version

Use Python 3.12. The committed `FasterCode` extension loads only on CPython 3.12:

- `bin/OS/linux/FasterCode.cpython-312-x86_64-linux-gnu.so`
- `bin/OS/win32/FasterCode.cp312-win_amd64.pyd`

Any other interpreter needs a FasterCode rebuild.

### Rebuilding FasterCode

FasterCode is the C core of the author's Irina engine plus Cython bindings. Building it needs gcc and Cython.

```bash
cd bin/_fastercode && bash fastercode_linux.sh
cp src/FasterCode.cpython-*.so ../OS/linux/
```

- The Linux script doesn't install its output; the `cp` step does that.
- The script leaves `FasterCode.pyx`, `FasterCode.c`, `libirina.a` and `build/` in `src/`. Don't commit them.
- Edit `src/Faster_Irina.pyx` and `src/Faster_Polyglot.pyx`; the build concatenates them into `FasterCode.pyx`. The C sources are in `src/irina/`.
- The Windows `.bat` scripts copy into `OS\windows`, but the app loads from `OS\win32`.

### Regenerating icons

This needs Pillow.

1. Add a line `Name <iconset_dir> <file.png>` to `bin/_genicons/Formatos.tema`.
2. Run `cd bin/_genicons && python3 gen_all.py`.

- The script rewrites `bin/Code/QT/Iconos.py` and `Resources/IntFiles/Iconos{,_sepia,_dark}.{bin,dic}`. Never hand-edit `Iconos.py`.
- The generator puts single blank lines between functions, but the committed file uses PEP 8 spacing. Reformat the output to keep the diff small.

### Docker

The `Dockerfile` is stale:

- It calls `linux64.sh` and `RunEngines`, which no longer exist.
- It installs Qt5 libraries.

## Architecture

### Process model

`bin/LucasR.py` dispatches on `argv`.

These arguments start the full GUI through `Code.Main.Init.init()`:

- no argument
- a file argument: `.pgn`, `.lcdb`, `.lcsb`, `.bmt` or `.shortcut`
- `-play` and `-playagainst`. The GUI spawns these itself to open a second instance that plays from a position or a game.

These arguments start helper processes, each with its own `QApplication`:

- `-kibitzer`, `-analysis`, `-tournament`, `-league`, `-swiss` and `-translate`.
- Each helper logs stderr to its own `bin/bug.<name>` file, for example `bug.kibitzers`, `bug.tournaments` or `bug.analysis`.

How the processes connect:

- The GUI spawns all of them through `Code.Z.XRun.run_lucas(...)`. It re-executes `LucasR.py`, or the frozen `LucasR` binary in a release build.
- Parent and child talk through `UtilSQL.IPC`, a temporary SQLite file used as a FIFO of pickled dicts.
- A tournament, league or Swiss run can launch several worker processes.
- All workers share the engine-vs-engine loop in `Code/Workers/` and coordinate through the competition's SQLite files (for example `UtilSQL.DictSQLMultiProcess`).

### Global state (`bin/Code/__init__.py`)

Importing `Code` has side effects:

- It `chdir`s to `bin/`.
- It puts `bin/OS/<platform>/` on `sys.path`, which makes `import FasterCode` and `import OSEngines` top-level imports. Only `linux` and `win32` folders exist.
- It defines `VERSION` and `Code.path_resource(...)`, which resolves paths into `Resources/`.
- It declares runtime singletons such as `Code.configuration`, `Code.procesador`, `Code.main_window`, `Code.runSound`, `Code.list_engine_managers` and `Code.dic_colors`. Startup fills them in, and every module reads them directly.

### Procesador and Managers (core control flow)

`Code/Procesador.py` is the top-level controller. It owns:

- the main window
- the home toolbar (`TB_PLAY`, `TB_TRAIN`, …)
- the shared tutor and analyzer engines

Every interactive activity is a subclass of `Code.ManagerBase.Manager.Manager`: playing an engine, tactics, GM games, leagues, Leitner, and so on. There are about 35 subclasses spread across the feature packages. `Code/Leitner/ManagerLeitner.py` is a compact example.

Manager lifecycle:

- Constructing a manager registers it as `procesador.manager` and as the main window's active handler.
- Toolbar clicks call `manager.run_action(TB_*)`. Keys a manager doesn't handle should fall through to `self.routine_default(key)`.
- Board moves arrive at the callback registered with `self.set_dispatcher(fn)`.
- The window's close button becomes a `run_action()` call for whichever of `TB_CLOSE`, `TB_CANCEL`, `TB_STOP`, … is on the toolbar (`MainWindow.closeEvent`). Put cleanup in that handler.
- Leaving an activity calls `procesador.start()`. That calls the manager's `end_manager()`, restores the home screen and closes every engine.

`ProcesadorVariations` is a lightweight clone with its own `MainWindow`. It edits a game or its variations in a separate window (`procesador.manager_game(...)`).

Menus (`Code/Menus/`):

- `XxxMenu(BaseMenu.RootMenu)` builds an option tree with string keys.
- `XxxMenuRun` dispatches on the selected key.
- User-defined shortcuts (`Code/Shortcuts/`) store those keys. Don't rename existing ones.

### Chess core

- `Code/Base/` holds `Game`, `Move`, `Position` and `Constantes`.
- `FasterCode` handles move generation, SAN/PGN parsing, FEN handling, the PGN file reader and Polyglot books.
- FasterCode is stateful: `set_fen()`, `get_exmoves()` and `make_move()` all act on one global board.
- A move is a string such as `e2e4` or `a7a8q`.
- A "pv" is a space-separated list of moves.
- An "xpv" is the compact form used in databases. Convert with `FasterCode.pv_xpv` / `xpv_pv`.
- python-chess is used only in `Code/Endings/LibChess.py`.

### Engines (`Code/Engines/`)

Bundled engines:

- Each engine lives in `bin/OS/<platform>/Engines/<name>/`.
- Engines are registered in `bin/OS/<platform>/OSEngines.py::read_engines()`. There is one registry per platform, and the two platforms bundle different engine sets.
- Binaries are committed without the exec bit. `read_engines()` chmods them at startup.
- `*.nnue` files go through Git LFS.

Running engines:

- `EngineRun` drives the UCI process, a `QProcess` with Qt signals.
- Three managers wrap it:
  - `EngineManagerPlay` for playing
  - `EngineManagerAnalysis` for analysis, with a cache
  - `EngineManagerRefresh`
- Managers are usually built with `Procesador.create_manager_engine(...)` or `create_manager_analyzer_var(...)`.
- Each started engine registers in `Code.list_engine_managers`. `procesador.close_engines()` kills them all, and it runs every time the home screen is restored.

To trace UCI traffic, set `DEBUG_ENGINES` and `DEBUG_ENGINES_SEND` in `Code/Z/Debug.py`.

### Persistence

User data:

- User data lives in `<repo>/UserData/`, which is gitignored.
- A `<repo>/lc.folder` file can point it elsewhere.
- Extra users get `UserData/users/<n>/`.
- All paths come from `Code/Config/ConfigPaths.py`.

Storage format:

- Nearly everything is stored as SQLite tables of pickled Python objects (`Code/SQL/UtilSQL.py`: `DictSQL`, `ListSQL`, `ListObjSQL`, …).
- Renaming or moving a class or module whose instances get pickled breaks loading of existing user files.
- `DictSQL.wrong_pickle(b"old.path", b"new.path")` is the byte-replacement shim for that case.

Settings (`Code/Config/Configuration.py`):

- Every attribute named `x_*` is saved and restored automatically by `graba()` / `lee()`.
- To add a setting, add `self.x_name = default` to `__init__`.
- For ad-hoc per-feature state, use `configuration.read_variables(key)` and `write_variables(key, dict)`.

Enums (`Code/Base/Constantes.py`):

- Integer enums are built by tuple-unpacking `range(N)`.
- `GT_*` values are stored in adjournment keys, and `RS_*` values are stored by competitions.
- Add new names at the end and bump `N`. Never reorder.

Games:

- A game serializes with `Game.save()` / `Game.restore()`.
- Game databases (`.lcdb`) are SQLite, handled by `Code/Databases/DBgames.py`.

### Qt layer (`Code/QT/`)

Use the project's Spanish-named wrappers instead of raw PySide6 widgets:

- `Controles`: `ED` line edit, `CB` combo, `PB` button, `LB` label, `CHB` checkbox, `SB` spinbox, `GB` group box, `EM` text edit, `TB` toolbar, `Menu`.
- `Colocacion`: chainable layouts, for example `Colocacion.V().control(w).otro(layout).relleno().margen(5)`. It also has `H` and `G` (grid).
- `LCDialog` is the dialog base class. It saves geometry, grid columns and splitters under its `extparam` key (`save_video()` / `restore_video()`).
- `QTDialogs.LCMenu`: add items with `.opcion(key, label, icon)`. `.lanza()` returns the chosen key.
- `QTMessages` provides message boxes, and `FormLayout` builds quick forms.
- `Grid` with `Columnas.ListaColumnas().nueva(...)` builds a table view. The owner supplies duck-typed callbacks:
  - required: `grid_num_datos(grid)` and `grid_dato(grid, row, obj_column)`
  - optional: `grid_doble_click`, `grid_color_fondo` and others
- Icons: `Iconos.Name()` returns a `QIcon`, and `Iconos.pmName()` returns a `QPixmap`.

Theme colors:

- Prefer `Code.dic_colors[KEY]` / `Code.dic_qcolors[KEY]` over hard-coded hex values, so the Dark, Light and Mid style modes keep working.
- Add a new key to every `Resources/Styles/*.colors` file.
- Also add it to `colors.template`, which supplies its label in the color editor.

### Translations

- `Code/Translations/Translate.py` installs `_`, `_X`, `_F`, `_FO` and `_SP` as builtins, so code uses them without imports.
- UI strings are English msgids.
- For substitutions, use `_X(_("Mate in %1"), str(n))` with `%1` to `%3`. Never put an f-string inside `_()`.
- In `"Text ||context"`, everything after `||` is a hint for translators. It is stripped at runtime.
- Compiled catalogs live in `Resources/Locale/<lang>/LC_MESSAGES/`: `lucaschess.mo`, plus `lcopenings.mo` for opening names.
- The templates are `Resources/Locale/messages.pot` and `openings.pot`.
- Translation happens on Transifex. Only the `.mo` files are committed.

## Conventions and gotchas

Identifiers mix legacy Spanish with newer English snake_case. Common Spanish words:

- Verbs: `graba` = save, `lee` = read, `lanza` = launch/show, `pon` = set, `quita` = remove, `muestra` = show, `reiniciar` = restart
- Nouns: `rutina` = callback, `opcion` = option, `titulo` = title, `valor` = value, `carpeta` = folder, `fichero` = file, `partida` = game, `jugada` = move, `motor` = engine, `tablero` = board, `aplazamiento` = adjournment
- Layout helpers: `relleno` = stretch, `otro` = nested layout
- Prefixes: `si_` = boolean, `li_` = list, `dic_` = dict

Formatting:

- Code follows Black-style formatting with a 120-column limit and double quotes.
- No formatter config is committed.

Debugging and logs:

- The GUI sends stderr to `bin/bug.log`, which is a tracked file. Don't commit traceback noise in it.
- `__debug__` is on unless you run `python -O`.
- In debug mode, stderr is also echoed to stdout.
- In debug mode, `Code/Z/Debug.py` also installs `prln`, `stack` and `stack0` as builtins for quick tracing. They don't exist under `-O`, so remove any calls before committing.

Versioning:

- The version string is `VERSION` in `bin/Code/__init__.py`.
