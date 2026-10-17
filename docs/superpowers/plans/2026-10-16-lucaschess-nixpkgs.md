# Lucas Chess nixpkgs Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `lucaschess` 6.2.0 to nixpkgs as `pkgs/by-name/lu/lucaschess/`.
The package must ship no prebuilt binaries and pass nixpkgs review.

**Architecture:**
- **Two upstreamable patches** are written on a branch of the Lucas Chess
  fork, then copied into nixpkgs as `.patch` files:
  - `LUCASCHESS_HOME`, which redirects every write out of the program tree;
  - absolute file arguments.
- **`package.nix`** builds FasterCode and three in-tree engines from
  source. It installs the program tree read-only under
  `$out/share/lucaschess`, with symlinks to nixpkgs `stockfish` and `lc0`.
  A wrapper sets `LUCASCHESS_HOME` and `PYTHONPATH`.
- **A nixpkgs-only patch** narrows the engine registry to the shipped
  engines and hides the features that need engines we don't ship.

**Tech Stack:**
- Nix: `python3Packages.buildPythonApplication`, `stdenv.mkDerivation`,
  `makeWrapper`, `wrapQtAppsHook`, nixfmt.
- Python 3 and PySide6 for the app; Cython for FasterCode; C and C++ for
  the engines.

**Spec:** `docs/superpowers/specs/2026-10-16-nixpkgs-package-design.md` (in
this repo). Read it before starting. This plan argues from it.

**Repos:**
- **`/home/tristan/git/lucaschessR6`** ("the LC fork"). Holds the spec,
  this plan and the upstream-patch branch.
- **`/home/tristan/git/nixpkgs`** ("the nixpkgs fork"). Holds the package.

## Global Constraints

- **Target:**
  - Package path `pkgs/by-name/lu/lucaschess/package.nix`.
  - `pname = "lucaschess"`.
  - `version = "6.2.0"`, written as a literal (no IFD).
  - `src = fetchFromGitHub { owner = "lukasmonk"; repo = "lucaschessR6"; tag = "R${version}"; … }`.
- **Platform:** `meta.platforms = [ "x86_64-linux" ]`. The comment gives
  the reason: FasterCode's `cpu_flags.c` uses `<cpuid.h>`.
- **Provenance:** `meta.sourceProvenance = [ lib.sourceTypes.fromSource ]`.
  Nothing prebuilt from upstream may reach `$out`:
  - no file under `bin/OS/linux/Engines/*` except the data files listed in
    Task 5;
  - nothing from `bin/OS/linux/DigitalBoards`;
  - not `bin/OS/linux/FasterCode.*.so`;
  - nothing from `bin/OS/win32`.
- **Engines shipped:**
  - `stockfish`, from nixpkgs;
  - `maia-1100` … `maia-1900` and `maia-2200`, using nixpkgs `lc0`;
  - `irina`, `eguzki` and `eguzkilore`, built from source.
  - Nothing is registered under `lc0` or any other key.
- **`LUCASCHESS_HOME`:**
  - Unset or empty: behaviour is byte-for-byte upstream's.
  - Set: every write that today lands next to `bin/` goes under that
    directory instead.
  - The wrapper default is `${XDG_DATA_HOME:-$HOME/.local/share}/lucaschess`,
    and a value the user already set wins.
  - User data ends up at `$LUCASCHESS_HOME/UserData`, the same path this
    repo's flake used.
- **Program-tree writes are untouched:** the self-updater and the e-board
  driver downloader still write into `Code.folder_os`. Both are disabled
  in the package.
- **Patch comments:** every `.patch` and `substituteInPlace` gets a
  comment saying *why* it exists. Every vendored patch also says either
  its upstream PR URL or that it is Nix-specific.
- **`meta`:**
  - `description`: `"Chess GUI for training, play against UCI engines and engine tournaments"`;
  - `homepage`: `"https://lucaschess.pythonanywhere.com"`;
  - `mainProgram`: `"lucaschess"`;
  - `maintainers`: `[ lib.maintainers.tristanlirette ]`;
  - `license`: a list matching upstream, as in spec "Platform and
    metadata". Maia weights are `gpl3Only`, from the two GPL-3.0 repos.
  - `meta` is the last attribute; `passthru` comes before it.
- **nixpkgs commits** (final shape after squashing):
  1. `maintainers: add tristanlirette`
  2. `lucaschess: init at 6.2.0`
  - No trailing period on subjects.
  - Every commit, in both repos, ends with
    `Assisted-by: Claude Code (Claude Opus 5.5)`, or the model actually
    used. Never a `Co-authored-by:` line for the LLM.
- **Maintainer entry, verbatim:**
  `tristanlirette = { name = "Tristan Lirette"; email = "dev@tristanl.net"; github = "tristanlirette"; githubId = 31151912; };`
  No `matrix`, no `keys`.
- **Style:**
  - Format with nixfmt.
  - Explicit function arguments (no `...`).
  - Don't override `phases`. Overridden phases call `runHook pre*` and
    `runHook post*`.
  - Build-only tools go in `nativeBuildInputs`.
  - No `overrideAttrs` on `stockfish` or `lc0`.
- **Branches:** the owner approves these by approving this plan.
  - `configurable-data-dir` in the LC fork, off `4bd66bb` (tag `R6.2.0`).
  - `lucaschess-init` in the nixpkgs fork, off `upstream/master`.
- **Not in scope:**
  - opening the nixpkgs PR or the upstream PR (the owner does both);
  - the DigitalBoards add-on;
  - aarch64.

## Review Focus

1. **Flake users' data.** Someone with `~/.local/share/lucaschess/UserData`
   from this repo's flake starts the package and sees their existing
   games and settings. The stale mirror symlinks next to it (`bin/`,
   `Resources`, `.store-path`) are ignored. Pinned by Task 4 Step 6.
2. **`LUCASCHESS_HOME` as given by a user.** A relative path, a trailing
   slash, or a directory that doesn't exist yet must resolve to an
   absolute directory, which is created. Pinned by Task 1 Step 1.
3. **Relative file argument.** `lucaschess games/x.pgn`, run from any
   directory, opens that file. Lucas Chess `chdir`s to `bin/` at import,
   so this fails upstream today. Pinned by Task 1 Step 7 and Task 4
   Step 6.
4. **Helper processes.** Kibitzers, analysis, tournaments, leagues and
   Swiss events are re-executed as `sys.executable LucasR.py -<mode>`
   from `bin/`. They must find their Python dependencies and write their
   `bug.*` logs under `LUCASCHESS_HOME`, not into the store. Pinned by
   Task 4 Step 5 (wrapper environment) and Task 8 (manual kibitzer and
   tournament run).
5. **Menus that name engines we don't ship.** No menu entry may show
   Rodent II or another dropped engine and then silently run Stockfish:
   - the Rodent personalities submenu;
   - the "Indexes - RodentII" kibitzer;
   - a Rodent book entry.

   Pinned by Task 6 Steps 1-4 and Task 8.

---

### Task 1: Upstreamable patches in the LC fork

**Files** (LC fork, branch `configurable-data-dir` off `4bd66bb`):
- Modify: `bin/Code/__init__.py`. Add the home helper after the `os.chdir`
  block (lines 12-14), and absolutize file arguments *before* that block.
- Modify: `bin/Code/Config/ConfigPaths.py:8-9`.
- Modify: `bin/Code/Main/Init.py:15,17`.
- Modify the helper logs:
  - `bin/Code/Kibitzers/RunKibitzer.py:236`
  - `bin/Code/Tournaments/RunTournament.py:82`
  - `bin/Code/Analysis/RunAnalysis.py:306`
  - `bin/Code/Leagues/RunLeague.py:73`
  - `bin/Code/Swiss/RunSwiss.py:72`
- Modify: `bin/Code/Engines/Engines.py:291`.
- Output, copied into nixpkgs by Task 4:
  - `configurable-data-dir.patch` (commit 1);
  - `absolute-file-arguments.patch` (commit 2).

**Interfaces:**
- Produces, in package `Code`:
  - `folder_home: str | None`: `os.path.realpath(os.environ["LUCASCHESS_HOME"])`,
    created with `os.makedirs(..., exist_ok=True)` when the variable is
    set and non-empty. Otherwise `None`.
  - `writable_path(default: str, name: str) -> str`: returns
    `Util.opj(folder_home, name)` when `folder_home` is set, else
    `default` unchanged.
- Call sites:
  - `ConfigPaths.LCFILEFOLDER = os.path.realpath(Code.writable_path("../lc.folder", "lc.folder"))`.
  - `LCBASEFOLDER` likewise, with `"../UserData"` and `"UserData"`.
  - `Init.py`: `Code.writable_path("bug.log", "bug.log")`.
  - Each helper: `Code.writable_path("./bug.<x>", "bug.<x>")`, with the
    same `<x>` it uses today.
  - `Engines.read_uci_options()`, internal-engine branch:
    `Code.writable_path(os.path.join(Code.folder_os, self.uci_options_sqlite), self.uci_options_sqlite)`.

**Test harness:** the repo has no test suite. Run checks from `bin/` with
`PY='nix shell --impure --expr "with import <nixpkgs> {}; python3.withPackages (ps: [ ps.psutil ps.charset-normalizer ])" -c python3'`.
That Python imports `Code` and `ConfigPaths` without the GUI. `import Code`
under `python -c` `chdir`s to the current directory.

- [ ] **Step 1: Write the failing check for `LUCASCHESS_HOME`.** Save it as
  `<scratchpad>/check_home.sh`. Step 11 says where `<scratchpad>` is.
  It runs three cases from `bin/`:
  - Unset: `ConfigPaths.LCBASEFOLDER == os.path.realpath("../UserData")`
    and `Code.folder_home is None`.
  - `LUCASCHESS_HOME=rel/dir/` in a fresh temp cwd copy:
    `Code.folder_home == os.path.realpath("rel/dir")`, that directory now
    exists, and
    `ConfigPaths.LCBASEFOLDER == os.path.join(Code.folder_home, "UserData")`.
  - `LUCASCHESS_HOME=""`: identical to unset.

  Copy `bin/` to a temp dir for the relative case, so the directory is
  created there.
- [ ] **Step 2: Run it and confirm it fails.** Run
  `bash check_home.sh`. Expected: an `AttributeError` on `folder_home`.
- [ ] **Step 3: Implement `folder_home` and `writable_path` in
  `Code/__init__.py`, and update the call sites listed under Interfaces.**
- [ ] **Step 4: Run the check and confirm it passes.** Expected: all three
  cases print OK. Also run
  `grep -rn '"\./bug\.\|"bug\.log"' bin/Code`. Expected: every hit is
  inside a `writable_path(` call.
- [ ] **Step 5: Run the compile check.** Run
  `PYTHONPYCACHEPREFIX=/tmp/lc-pyc python3 -m compileall -q bin/Code`.
  Expected: no output.
- [ ] **Step 6: Commit.** Subject:
  `Add LUCASCHESS_HOME to keep writes out of the program folder`.
  - The body says the default is unchanged and explains why: read-only
    installs, such as Linux distribution packages.
  - Ends with the `Assisted-by:` trailer.
- [ ] **Step 7: Write the failing check for relative file arguments.**
  Create `<scratchpad>/argcheck/x.pgn`. From `<scratchpad>/argcheck`, run:

  ```bash
  $PY -c 'import sys; sys.argv = ["/home/tristan/git/lucaschessR6/bin/LucasR.py", "x.pgn"]; sys.path.insert(0, "/home/tristan/git/lucaschessR6/bin"); import Code; assert sys.argv[1] == "<scratchpad>/argcheck/x.pgn", sys.argv'
  ```

  Expected now: an `AssertionError`, because `sys.argv[1]` is still
  `"x.pgn"`.
- [ ] **Step 8: Implement the argument fix in `Code/__init__.py`.** Before
  the `os.chdir`, replace each `sys.argv[1:]` item that doesn't start
  with `-` and passes `os.path.exists` with its `os.path.abspath`.
- [ ] **Step 9: Run the check and confirm it passes.** Then run Step 4's
  check again. Expected: both pass.
- [ ] **Step 10: Commit.** Subject:
  `Resolve file arguments before changing directory`, with the trailer.
- [ ] **Step 11: Export the patches.**

  ```bash
  git -C /home/tristan/git/lucaschessR6 diff 4bd66bb HEAD~1 > <scratchpad>/configurable-data-dir.patch
  git -C /home/tristan/git/lucaschessR6 diff HEAD~1 HEAD > <scratchpad>/absolute-file-arguments.patch
  ```

  `<scratchpad>` is
  `/tmp/claude-1000/-home-tristan-git-lucaschessR6/469c3dd6-0b0e-4a85-826f-133acfb55d00/scratchpad`.

  Expected: both files are non-empty, and each touches only the files
  listed above.

---

### Task 2: nixpkgs branch and maintainer entry

**Files:**
- Modify: `maintainers/maintainer-list.nix` in the nixpkgs fork, at its
  alphabetical position.

**Interfaces:**
- Produces: `lib.maintainers.tristanlirette`, used by Task 4.

- [ ] **Step 1: Set up the branch.**
  - `git -C /home/tristan/git/nixpkgs remote add upstream https://github.com/NixOS/nixpkgs.git`
    (skip if it already exists).
  - `git fetch upstream master`
  - `git switch --create lucaschess-init upstream/master`
- [ ] **Step 2: Insert the maintainer entry** exactly as given in Global
  Constraints, keeping alphabetical order.
- [ ] **Step 3: Validate.** Run
  `nix-build lib/tests/maintainers.nix` and `nix fmt -- maintainers/maintainer-list.nix`.
  Expected: the build succeeds, and formatting causes no diff.
- [ ] **Step 4: Commit.** Run
  `git commit -m "maintainers: add tristanlirette" -m "Assisted-by: Claude Code (Claude Opus 5.5)"`.

---

### Task 3: FasterCode and the in-tree engines

**Files:**
- Create: `pkgs/by-name/lu/lucaschess/package.nix`, containing `src`,
  `fastercode` and `inTreeEngines` in a `let`. The main derivation can
  stay a stub until Task 4.

**Interfaces:**
- Produces:
  - `passthru.fastercode`: a Python module derivation, ported from
    `flake.nix` `fastercode`. It installs `FasterCode*.so` into
    `$out/${python3.sitePackages}`.
  - `passthru.engines.{irina,eguzki,eguzkilore}`: derivations whose
    `$out/bin/<name>` is a dynamically linked UCI engine.
- Engine builds:
  - Unpack `bin/OS/linux/Engines/<name>/src.7z` with `p7zip`, in
    `nativeBuildInputs`.
  - Irina is C: `$CC -std=gnu17 -O3 -DNDEBUG`, with no `-static`, `-s`,
    `-m64` or `-flto`.
  - Eguzki and Eguzkilore are C++: `$CXX -O3 -DNDEBUG`, same exclusions.
  - A comment says why the upstream Makefile flags are dropped: `-static`
    needs glibc.static, `-s` duplicates Nix stripping, and `-flto=2`
    isn't needed.
  - `meta.license` follows what the built sources' headers say.

- [ ] **Step 1: Write the failing check.** Run
  `nix-build -A lucaschess.fastercode -A lucaschess.engines.irina -A lucaschess.engines.eguzki -A lucaschess.engines.eguzkilore`.
  Expected now: an evaluation error, because the attribute is missing.
- [ ] **Step 2: Implement `src`, `fastercode` and `inTreeEngines`** as
  above, and expose them through `passthru`. Set `src.hash` from the
  first build's mismatch message.
- [ ] **Step 3: Run the build and smoke-test each engine.** For each
  engine, run
  `printf 'uci\nisready\nposition startpos\ngo depth 4\n' | timeout 20 ./result*/bin/<name> | grep -E 'readyok|bestmove'`.
  Expected for each engine: `readyok` followed by a `bestmove` line.

  For FasterCode:
  `nix shell --impure --expr '…python3.withPackages (ps: [ <fastercode> ])' -c python3 -c 'import FasterCode; print(FasterCode.is_bmi2())'`.
  Expected: it prints `True` or `False`.
- [ ] **Step 4: Commit as WIP**, for example
  `lucaschess: wip fastercode and engines`. Task 8 squashes it.

---

### Task 4: Main package, patches and wrapper

**Files:**
- Modify: `pkgs/by-name/lu/lucaschess/package.nix`.
- Create, copied from Task 1 Step 11:
  - `pkgs/by-name/lu/lucaschess/configurable-data-dir.patch`
  - `pkgs/by-name/lu/lucaschess/absolute-file-arguments.patch`

**Interfaces:**
- Consumes: Task 3's `fastercode` and `inTreeEngines`, Task 1's patches
  and Task 2's maintainer.
- Produces:
  - `$out/bin/lucaschess`;
  - `$out/share/lucaschess/{bin,Resources}`;
  - the desktop item and the icon
    `$out/share/icons/hicolor/64x64/apps/lucaschess.png`.
- Main derivation:
  - `python3Packages.buildPythonApplication`, with `pyproject = false`
    and `dontWrapPythonPrograms = true`.
  - `dependencies`: `charset-normalizer`, `chess`, `pillow`, `polib`,
    `psutil`, `pyside6`, `requests`, `sortedcontainers`, `fastercode`.
  - `nativeBuildInputs`: `makeWrapper`, `qt6.wrapQtAppsHook`,
    `copyDesktopItems`.
  - `buildInputs`: `qt6.qtbase`, `qt6.qtsvg`, `qt6.qtmultimedia`.
- Wrapper:
  - Built with `makeWrapper ${python3.interpreter} $out/bin/lucaschess`.
  - Arguments:
    `--add-flags $out/share/lucaschess/bin/LucasR.py`,
    `--prefix PYTHONPATH : ${python3Packages.makePythonPath dependencies}`,
    `--set PYTHONOPTIMIZE 1`,
    `--run 'export LUCASCHESS_HOME="${LUCASCHESS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/lucaschess}"'`,
    and `"${qtWrapperArgs[@]}"`.
  - With `dontWrapQtApps = true`.
  - The `PYTHONPATH` choice gets a comment: helper processes re-execute
    `sys.executable LucasR.py`, so the dependencies must reach the
    interpreter through the environment.

- [ ] **Step 1: Write the failing check.** Run
  `nix-build -A lucaschess && ./result/bin/lucaschess -healthcheck; echo $?`.
  Expected now: the build fails, or the binary is missing.
- [ ] **Step 2: Implement the install.**
  - `patches = [ ./configurable-data-dir.patch ./absolute-file-arguments.patch ]`.
    Each gets a comment: "Upstreamable. PR: (none yet)".
  - Port the flake's `postPatch` `substituteInPlace` blocks, with their
    comments: `Util.py` copy chmod, `Piezas.py` copyfile, and
    `Update.py` updater disabled with a message pointing to Nix.
  - `installPhase`: copy `bin` and `Resources` to `$out/share/lucaschess`.
    From `bin/OS`, keep only `linux/OSEngines.py` and an empty
    `linux/Engines/`, which Task 5 fills.
  - Port the WAL-to-rollback conversion and the `compileall`
    unchecked-hash step from the flake's `installPhase`.
  - Install the desktop item and the icon from the flake. Fill in the
    full `meta` from Global Constraints.
- [ ] **Step 3: Run the check and confirm it passes.** Expected: the build
  succeeds, `-healthcheck` exits `0`, and
  `find result/ -path '*OS/linux/DigitalBoards*' -o -name 'FasterCode*.so' -path '*share*'`
  prints nothing.
- [ ] **Step 4: Confirm the source has no prebuilt binaries.** Run
  `nix run nixpkgs#file -- -L $(find result/share -type f) | grep -E 'ELF|PE32'`.
  Expected: no output. Engines come in Task 5.
- [ ] **Step 5: Check the wrapper environment.** Run `cat result/bin/lucaschess`.
  Expected:
  - `PYTHONPATH` lists PySide6 and FasterCode;
  - `LUCASCHESS_HOME` respects an existing value;
  - `QT_PLUGIN_PATH` is set.
- [ ] **Step 6: Run the offscreen smoke test.** This needs Task 5 for a
  clean start. Run it now and re-run it after Task 5:

  ```bash
  H=$(mktemp -d); mkdir -p $H/UserData && echo marker > $H/UserData/marker
  cd /tmp && echo '[Event "t"]' > rel.pgn
  LUCASCHESS_HOME=$H QT_QPA_PLATFORM=offscreen timeout 25 $OLDPWD/result/bin/lucaschess rel.pgn; true
  ls $H; grep -il traceback $H/bug.log || echo NO-TRACEBACK
  ```

  Expected after Task 5:
  - `$H` contains `UserData` with `marker` still present, and `bug.log`
    if anything was logged;
  - `NO-TRACEBACK` is printed;
  - no `rel.pgn` "not found" error appears in `bug.log`.
- [ ] **Step 7: Commit as WIP.**

---

### Task 5: Engine folders and registry patch

**Files:**
- Create: `pkgs/by-name/lu/lucaschess/remove-unpackaged-engines.patch`
  (Nix-specific) against `bin/OS/linux/OSEngines.py`.
- Modify: `package.nix`, adding the engine assembly to `installPhase` and
  `postPatch` substitutions.

**Interfaces:**
- Consumes: Task 3's engines, plus `stockfish` and `lc0` from nixpkgs.
- Produces the installed layout under
  `$out/share/lucaschess/bin/OS/linux/Engines/`:
  - `stockfish/stockfish` → `${lib.getExe stockfish}`
  - `maia/lc0` → `${lc0}/bin/lc0`. lc0 has no `mainProgram`, so use the
    path. Also `maia/maia-{1100..1900,2200}.pb.gz`, `1100-1500.bin`,
    `1600-1900.bin` and `2200.bin`, copied from the source tree.
  - `irina/irina` → `${engines.irina}/bin/irina`, plus every
    non-executable file of the source folder, except `src.7z`, `*.zip`
    and `*.tar.gz`.
  - `eguzki/…` and `eguzkilore/…`, with the same rule.
- Registry, in the patched `OSEngines.py`:
  - `read_engines()` registers exactly these keys: `maia-1100` …
    `maia-1900`, `maia-2200`, `stockfish`, `eguzkilore`, `eguzki` and
    `irina`.
  - Maia's exe becomes `"lc0"`, both in `mas(...)` and in the
    `cm.path_exe = Util.relative_path(...)` line.
  - Stockfish uses exe `"stockfish"` and version `"@stockfishVersion@"`.
    `postPatch` replaces that with `${stockfish.version}`, using
    `substituteInPlace --replace-fail`.
  - The `bmi2`, `avx2` and `is_avx2` code goes, along with the
    `FasterCode` import if it's left unused.
  - `li_engines_fixed_elo()` returns
    `(("stockfish", 1400, 3100), ("eguzki", 1000, 2700))`.
  - The patch header comment says it narrows the registry to engines
    nixpkgs can ship, and points to the PR description for the policy.

- [ ] **Step 1: Write the failing check** as `<scratchpad>/registry-check.sh`.
  It uses the package's own interpreter and dependency path, read from
  the wrapper:

  ```bash
  W=$(readlink -f result/bin/lucaschess); PY=$(grep -o '/nix/store/[^ ]*/bin/python3[.0-9]*' "$W" | head -1)
  PP=$(grep -oP "PYTHONPATH'?=?'?\K[^']*" "$W" | head -1)
  cd result/share/lucaschess/bin && LUCASCHESS_HOME=$(mktemp -d) PYTHONPATH=$PP "$PY" -c \
    'import Code, OSEngines; print(" ".join(sorted(OSEngines.read_engines(Code.folder_engines))))'
  ```

  `OSEngines` is importable because `Code/__init__.py` puts `OS/linux` on
  `sys.path`. Adjust the two `grep`s to the wrapper's actual text.
  Expected now: a `FileNotFoundError` from `os.chmod`, because the engine
  folders are empty.
- [ ] **Step 2: Write `remove-unpackaged-engines.patch`** with
  `git diff` against the `R6.2.0` source, as described above. Add it to
  `patches` and add the `@stockfishVersion@` substitution.
- [ ] **Step 3: Implement the engine folder assembly** in `installPhase`.
- [ ] **Step 4: Run the check and confirm it passes.** Run
  `bash <scratchpad>/registry-check.sh`. Expected output: exactly the 14
  keys
  `eguzki eguzkilore irina maia-1100 maia-1200 maia-1300 maia-1400 maia-1500 maia-1600 maia-1700 maia-1800 maia-1900 maia-2200 stockfish`.
- [ ] **Step 5: Run the Maia weight check.** Run
  `cd result/share/lucaschess/bin/OS/linux/Engines/maia && (printf 'uci\nsetoption name WeightsFile value maia-1500.pb.gz\nisready\nposition startpos\ngo nodes 1\n'; sleep 10) | ./lc0 | grep -E 'readyok|bestmove'`.
  Expected: `readyok` and `bestmove`.
- [ ] **Step 6: Re-run Task 4 Step 6.** Expected: as stated there.
- [ ] **Step 7: Commit as WIP.**

---

### Task 6: Hide features that need dropped engines

**Files:** extend `remove-unpackaged-engines.patch`. Each hunk is guarded
by `"rodentii" in Code.configuration.engines.dic_engines()`, so the patch
stays correct if Rodent II is packaged later.
- `bin/Code/Engines/SelectEngines.py`:
  - `gen_engines_rodent()` (line 164) returns `{}` when Rodent II isn't
    registered.
  - The Rodent submenu (lines 350-355) is created only when
    `self.dict_rodent` is non-empty.
- `bin/Code/Kibitzers/Kibitzers.py`:
  - `Tipos.li_tipos` (line 39) leaves out `KIB_INDEXES`.
  - `new_indexes()` (line 224) returns `None` without Rodent II.
- `bin/Code/Kibitzers/WindowKibitzers.py`: the menu that offers the
  `"index"` option (it dispatches at line 310) doesn't offer it.
- `bin/Code/Books/Books.py:71-80`: `at_least_one()` doesn't add the Rodent
  book when `path_rodent` doesn't exist.

These are left as they are. They are deliberate, and the PR description
lists them:
- `Albums.py:138` (fruit, critter and komodo fall back to Stockfish; no
  engine name is shown);
- `EnginesWicker.py:99`;
- `ManagerElo`, which already filters by registered engines.

- [ ] **Step 1: Write the failing manual checks** as a checklist in the
  scratchpad, `menu-checks.md`. Run each in the built app (Task 4 Step 6
  command, with a real display instead of offscreen):
  - (a) Play against an engine: no "Rodent" submenu.
  - (b) Kibitzers → New: no "Indexes - RodentII" choice.
  - (c) Openings/Books list on a fresh `LUCASCHESS_HOME`: no entry whose
    file is missing.

  Expected now: (a) shows an empty Rodent submenu, (b) shows Indexes.
  The owner runs these, since a GUI is needed.
- [ ] **Step 2: Implement the hunks above.**
- [ ] **Step 3: Rebuild and re-run the checklist.** Expected: (a), (b)
  and (c) pass.
- [ ] **Step 4: Run the guard check.** Run
  `grep -c 'rodentii' result/share/lucaschess/bin/Code/Engines/SelectEngines.py`.
  Expected: more than 1, which shows the guard is present. Also run the
  Task 4 Step 6 smoke test. Expected: `NO-TRACEBACK`.
- [ ] **Step 5: Commit as WIP.**

---

### Task 7: Package tests

**Files:**
- Create: `pkgs/by-name/lu/lucaschess/tests.nix`, a `runCommand` test.
- Modify: `package.nix`, setting
  `passthru.tests.smoke = callPackage ./tests.nix { lucaschess = finalAttrs.finalPackage; }`.
  If `buildPythonApplication`'s `finalAttrs` isn't available, use the
  `rec`/`self` form nixpkgs Python apps use.

**Interfaces:**
- Consumes: `lucaschess`, with its `passthru.engines` and `fastercode`.

- [ ] **Step 1: Write `tests.nix`.** It asserts that:
  - `lucaschess -healthcheck` exits 0;
  - a UCI handshake with each of the three in-tree engines and the
    `stockfish` symlink in `share/…/Engines` prints `readyok`;
  - `import FasterCode` works under the wrapper's `PYTHONPATH`;
  - the registry check from Task 5 Step 4 returns exactly those 14 keys.

  `HOME` and `LUCASCHESS_HOME` point at `$TMPDIR`. Set
  `meta.timeout = 120`.
- [ ] **Step 2: Run the tests.** Run `nix-build -A lucaschess.tests`.
  Expected: it succeeds.
- [ ] **Step 3: Confirm the tests can fail.** Temporarily change the
  expected key list. Expected: the build fails. Then revert.
- [ ] **Step 4: Commit as WIP.**

---

### Task 8: Verification, squash and PR description

**Files:**
- Create in the LC fork: `docs/superpowers/pr/2026-10-16-lucaschess-nixpkgs-pr.md`,
  the PR description draft.

- [ ] **Step 1: Format.** Run `nix fmt -- pkgs/by-name/lu/lucaschess/`.
  Expected: no diff afterwards.
- [ ] **Step 2: Run the full build with the sandbox on.** Run
  `nix-build -A lucaschess -A lucaschess.tests`. Expected: both succeed.
  The sandbox is on by default on Linux; confirm with
  `nix config show sandbox`, which should print `true`.
- [ ] **Step 3: The owner runs the manual smoke tests** from spec "To
  verify during the build":
  - start-up;
  - play against Irina;
  - analysis with Stockfish;
  - Maia at two levels;
  - a kibitzer;
  - a short engine tournament;
  - the Task 6 checklist;
  - the flake-data check from Review Focus 1, using the owner's real
    `~/.local/share/lucaschess`.

  Expected: all work, and `$LUCASCHESS_HOME/bug.*` has no tracebacks or
  permission errors.
- [ ] **Step 4: Squash the WIP commits into one.** Use
  `git reset --soft <maintainers-commit>` followed by
  `git commit -F <msg>`. The message is `lucaschess: init at 6.2.0`, a
  body of two to four lines on what Lucas Chess is plus its homepage,
  and the `Assisted-by:` trailer. Then check with
  `git log --format='%s%n%(trailers)' upstream/master..`. Expected:
  exactly the two commits from Global Constraints, each with the trailer.
- [ ] **Step 5: Run nixpkgs-review.** Run
  `nix run nixpkgs#nixpkgs-review -- rev HEAD`. Expected: `lucaschess`
  builds, and nothing else is rebuilt.
- [ ] **Step 6: Write the PR description draft.** Keep the nixpkgs PR
  template, and tick only what was done. It covers:
  - what Lucas Chess is, and why it belongs in nixpkgs;
  - the engine policy table, condensed, with a reason for each excluded
    group;
  - why plain lc0 is excluded: no LCZero network has a stated license;
  - the DigitalBoards drivers as future work;
  - the Maia weight sources (`CSSLab/maia-chess`, `CallOn84/LeelaNets`);
  - the degraded features from Task 6 (Rodent personalities, Indexes
    kibitzer, albums using Stockfish);
  - the upstream PR link for the two patches, or "not yet";
  - a reviewer smoke-test recipe: `nix-build -A lucaschess.tests`, plus
    the Task 4 Step 6 command;
  - an LLM-use disclosure line.
- [ ] **Step 7: Commit the draft in the LC fork** with the trailer. Don't
  push either repo and don't open any PR; the owner does that.
