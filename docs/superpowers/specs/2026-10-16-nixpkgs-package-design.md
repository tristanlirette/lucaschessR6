# Lucas Chess in nixpkgs: package design

Date: 2026-10-16
Status: design, approved for planning once reviewed

## Intent

Get Lucas Chess R6 into nixpkgs as `lucaschess`, in a form that reviewers
accept on `NixOS/nixpkgs` `master`. The owner of this design will open the
PR when they judge it ready, and will maintain the package afterwards.

The guiding rule is Nix's: everything the package installs is either built
from source or taken from nixpkgs. The upstream release bundles about 72
prebuilt Linux engines and 19 prebuilt e-board driver libraries. The
package ships only what that rule allows today, and it can grow as more
engines enter nixpkgs.

## Where the work happens

- **The package:** `pkgs/by-name/lu/lucaschess/package.nix` in the owner's
  nixpkgs fork at `/home/tristan/git/nixpkgs` (remote `origin` =
  `github.com/tristanlirette/nixpkgs`).
  - Work on a topic branch off `master`.
  - Patch files live next to `package.nix`.
  - Add `upstream` = `github.com/NixOS/nixpkgs` as a remote for rebasing.
- **Commits:** the full rules are in "nixpkgs contribution rules" below.
  - First commit: `maintainers: add <handle>`, because the owner isn't in
    `maintainers/maintainer-list.nix` yet.
  - Second commit: `lucaschess: init at 6.2.0`.
  - Every commit ends with an `Assisted-by:` trailer naming the tool and
    the model, for example `Assisted-by: Claude Code (Claude Opus 5.5)`.
    nixpkgs requires this (`CONTRIBUTING.md`, "Automation/AI policy"). A
    `Co-authored-by:` trailer does not satisfy the policy, so don't use
    one for the LLM.
- **The flake in this repo** (`/home/tristan/git/lucaschessR6/flake.nix`)
  is not the deliverable.
  - It's the reference for problems already solved: read-only store
    copies, the self-updater, WAL databases, pyc generation, Qt plugins,
    and the Python env that helper processes re-execute.
  - It does not need to keep pace with the package.

## Goals

1. `nix-build -A lucaschess` in the fork produces a working GUI on
   `x86_64-linux`.
2. The installed output contains no prebuilt native code.
   `meta.sourceProvenance` is `[ lib.sourceTypes.fromSource ]`.
3. These engines work:
   - Stockfish, from nixpkgs.
   - Maia: nixpkgs lc0 with the Maia weights. The plain lc0 engine is not
     included. See "The plain lc0 engine is dropped".
   - Irina, Eguzki and Eguzkilore, built from upstream's own source.
4. Lucas Chess writes nothing inside the store. User data, logs and caches
   go under one per-user directory.
5. The package and the PR satisfy every rule in "nixpkgs contribution
   rules" below, and the CI checks that run on a nixpkgs PR pass.

## Non-goals

- Packaging any engine other than the six listed in goal 3.
- aarch64 or Darwin support.
- Getting the upstream patch merged before the nixpkgs PR. Proposing it
  upstream is an optional side task, covered below.
- Keeping this repo's flake in sync.

## Anti-goals

These make the result a failure even if it builds:

- Any prebuilt binary from upstream ends up in the output, whether an
  engine, a driver or the committed FasterCode `.so`.
- Lucas Chess crashes at startup or in a menu because an engine it expects
  is missing.
- Data in the user's existing directory gets lost or orphaned. That covers
  a user moving from this repo's flake (data under
  `~/.local/share/lucaschess/UserData`), or between package versions.
- The patches change upstream's default behaviour for people running
  Lucas Chess outside Nix.

## Engine policy

These rules decide every inclusion, and the PR description restates them:

1. **Already in nixpkgs: include** as a dependency.
2. **Upstream's own code: build from source** inside this package. That
   means the GUI, FasterCode, Irina, Eguzki and Eguzkilore.
3. **Source available but not in nixpkgs: exclude for now.**
   - Each such engine first needs its own nixpkgs package, in its own PR.
   - After that, it joins this package as a dependency the same way as
     rule 1, with no change to this design.
4. **Binary only: exclude permanently.** The owner won't package these.

**The exception is the DigitalBoards e-board drivers.**
- They are binary only and their licenses are unclear.
- They will be packaged eventually, as an opt-in unfree add-on, but only
  after Lucas Chess is merged into nixpkgs.
- They are out of scope here. The PR description mentions them as future
  work.

### What each bundled Linux engine becomes

| Engine (registry key) | Today | In the package |
|---|---|---|
| `stockfish` | Bundled binary, registered as version 19 | nixpkgs `stockfish`. The registered version comes from the nixpkgs package (18 at the time of writing), not a hard-coded string. |
| `lc0` | Bundled 0.32.0 binary, its own BLAS/Fortran `.so` files, and network `791556.pb.gz` | **Excluded.** The engine is in nixpkgs, but no LCZero network has a stated license. See below. |
| `maia-1100` … `maia-1900`, `maia-2200` | Bundled Lc0 0.27.0 plus 10 `maia-*.pb.gz` | nixpkgs `lc0`, plus the 10 weight files and the 3 opening books `1100-1500.bin`, `1600-1900.bin` and `2200.bin` from the source tree as data |
| `irina` | Bundled static binary | Built from `bin/OS/linux/Engines/irina/src.7z` (C, GPL-3), plus `irina.bin` |
| `eguzki`, `eguzkilore` | Bundled static binaries | Each built from its own `src.7z`. These are C++ derived from Rodent, GPL-2, and the two sources differ in 5 files. Each keeps its `.bin` book. |
| ~62 other source-available engines | Bundled binaries plus vendored source | Excluded (rule 3) |
| `andscacs`, `clarabit`, `critter`, `gaviota`, `godel`, `jabba`, `komodo` (Dragon 1, both builds), `zappa` | Binary only | Excluded (rule 4) |
| `octochess`, `arhanpassant` | Binary, plus a link to upstream source | Excluded (rule 3; their source exists upstream) |
| `cinnamon`, `daydreamer` | 32-bit i386 static binaries, source vendored | Excluded (rule 3) |

Irina's engine source shares FasterCode's C core (`board.c`, `makemove.c`,
`movegen.c`, …) with small differences. It is still a separate build from
its own archive.

## Decisions

### Source

- `fetchFromGitHub` on `lukasmonk/lucaschessR6`, `tag = "R${version}"`.
  Upstream tags releases, and `R6.2.0` is `4bd66bb`.
- `version = "6.2.0"`, written as a literal.
  - The flake parses `VERSION` out of `bin/Code/__init__.py`.
  - Doing that on fetched source would be import-from-derivation, which
    nixpkgs forbids.
- The archive is about 1 GB. The builder may prune it in `postFetch`, for
  example dropping `bin/OS/win32` and the prebuilt Linux engines. That
  changes the hash and needs a comment.
- The tarball also contains the Windows tree (75 PE binaries) and every
  prebuilt Linux engine. None of them reach the output.
- Files tracked with Git LFS (`*.nnue`) arrive as pointer files in GitHub
  archives. Only engines we drop use them.

### Where Lucas Chess writes: the `LUCASCHESS_HOME` patch

Replace the flake's mirror launcher (a symlink farm under
`~/.local/share/lucaschess`) with a patch to Lucas Chess itself. The mirror
is the nixpkgs pattern for programs that can't be patched, such as
`pkgs/games/dwarf-fortress/wrapper`. For an open-source app, reviewers
expect a patch.

The patch adds one setting, the environment variable `LUCASCHESS_HOME`:

- **Unset:** behaviour is exactly as today, on every OS.
- **Set:** everything Lucas Chess writes goes under that directory instead
  of next to `bin/`.

Known write sites relative to `bin/`. The builder must find the rest,
since this list is not exhaustive:

- `Code/Config/ConfigPaths.py:8-9`: `../lc.folder` and `../UserData`.
- `Code/Main/Init.py:15-17`: `bug.log`. Helper processes write their own
  `bug.<name>` files, such as `bug.kibitzers` and `bug.tournaments`.
- `Code/Engines/Engines.py:15`: `uci_options.sqlite`, the cache of
  internal engines' UCI options, which lives in `bin/OS/linux/` today.

`os.chdir` to `bin/` in `Code/__init__.py` stays. Reading from the store is
fine.

**Writes that change the program itself stay where they are** (my call):
- The e-board driver downloader and the self-updater both write into
  `Code.folder_os` (`Code/Z/Update.py:95-110`). The variable leaves them
  alone.
- Both are disabled in the package anyway.
- A missing driver already fails gracefully: `Eboard.activate` returns
  `False`.
- The future DigitalBoards add-on will ship drivers in the store and needs
  no user-directory location.

Write the patch so upstream could accept it as is:
- Small.
- Default unchanged.
- No Nix-specific names.

The package carries it as a `.patch` file with a comment linking the
upstream PR once one exists.

**The wrapper:**
- It sets `LUCASCHESS_HOME` to
  `${XDG_DATA_HOME:-$HOME/.local/share}/lucaschess` unless the user has
  already set it.
- That way user data stays at `.../lucaschess/UserData`, where this repo's
  flake put it, which covers the anti-goal about lost data.
- Helper processes inherit the variable because the GUI starts them as
  children.

### Engine registry patch (nixpkgs-only)

`bin/OS/linux/OSEngines.py::read_engines()` registers every engine
unconditionally. For a missing file it calls `os.chmod`, which raises
`FileNotFoundError` and crashes startup. The package must change it so that:

- It registers exactly the engines in the table above.
- Stockfish and Maia's lc0 resolve to their nixpkgs store paths, and
  their version strings come from the nixpkgs packages.
- Nothing is registered under the `lc0` key. No code outside
  `OSEngines.py` refers to that key.
- Maia's relative `WeightsFile` (`maia-1500.pb.gz`, …) still resolves.
  - Lucas Chess runs each engine with its working directory set to
    `dirname(abspath(path_exe))`.
  - `EngineRun.py:165` uses `abspath`, not `realpath`, so a symlink to the
    nixpkgs binary inside a store folder holding the weights keeps that
    folder as the working directory.
- `li_engines_fixed_elo()` lists only registered engines. Of today's list,
  `stockfish` and `eguzki` remain. `arasan`, `cheng`, `greko`, `texel` and
  `ct800` go.

Book discovery (`Configuration.py:312`) scans
`Engines/{eguzkilore,eguzki,maia,irina,rodentii}` for `.bin` files.
- The kept engines' books must stay where that scan finds them.
- A missing `rodentii` folder must not crash the scan.

### Other places that name dropped engines

Engine lookups by key fall back to `tutor_default` (`"stockfish"`) when a
key is missing (`ConfigEngines.search`). So most references degrade safely.

The builder must still check each reference to a dropped key and confirm
it neither crashes nor leaves a broken menu entry. Found so far:
- `rodentii`: Kibitzers, WindowKibitzers, SelectEngines, EnginesWicker,
  Books, Configuration.
- `komodo`: SelectEngines, Albums.

Patch only where needed.

### Patches carried over from this repo's flake

Keep these. Each gets a comment in `package.nix` explaining it:

- Files copied out of the store keep their read-only mode, and Lucas Chess
  later rewrites them (`recursos.dbl`, `sounds.pkd`, piece SVGs). Make the
  copies writable (`Code/Z/Util.py`, `Code/QT/Piezas.py`).
- Disable the self-updater (`Code/Z/Update.py`), with a message pointing
  to Nix.
- Convert the two bundled game databases that use WAL mode to rollback
  mode. They can't be read from a read-only directory otherwise.
- Generate bytecode at build time, using unchecked-hash pycs and no `-j`,
  so the output doesn't depend on the builder's core count.
- Helper processes must see the Python dependencies.
  - Lucas Chess starts kibitzers, tournaments and other helpers by
    re-executing `sys.executable LucasR.py -<mode>`.
  - The flake handles this by running under `python3.withPackages`.
  - pkgs/README asks for the language framework, so the package should use
    `python3Packages.buildPythonApplication` with `pyproject = false` and
    the dependencies in `dependencies`. It then makes the re-executed
    `LucasR.py` see them, for example by applying
    `wrapPythonProgramsIn` to the installed `bin/` folder.
  - If that can't be made to work, keep `withPackages` and explain why in
    a comment.
- Qt modules: `qtbase`, `qtsvg`, `qtmultimedia` through `wrapQtAppsHook`.
  No `qtwayland`, because `run_gui()` forces `xcb`.
- Run with `PYTHONOPTIMIZE=1`. Debug mode echoes stderr to stdout and
  installs debug builtins.
- Desktop item and the 64px icon.

These flake pieces go away:
- The mirror launcher, including its `.store-path` stamp.
- The `LucasR.py` copy.
- `autoPatchelfHook` and its `buildInputs` list.
- The `libQt6PrintSupport` exclusion.
- The `chmod +x` loop over engines.

### FasterCode

Build it from `bin/_fastercode` as the flake does:
- Run upstream's `fastercode_linux.sh`.
- Use `-std=gnu17`, because `irina/defs.h` has `typedef char bool`, which
  breaks under GCC 15's C23 default.
- Install it into site-packages for the Python env.
- Exclude the committed `FasterCode.*.so`.

### Platform and metadata

- `meta.platforms = [ "x86_64-linux" ]`. FasterCode's `cpu_flags.c` uses
  x86 `cpuid`, and `read_engines()` calls it at startup. A comment says
  so. aarch64 is later work.
- `meta.license` is a list covering everything installed. It must match
  upstream exactly:
  - **Lucas Chess.** `LICENSE` is the GPL-3 text, and the Python sources
    have no license headers. Use `gpl3Only` unless upstream states "or
    later" somewhere.
  - **Irina.** `README.txt` says GPL-3 or later, but source headers say
    "version 2 … or (at your option) any later version". Pick the one
    that matches the files actually built.
  - **Eguzki and Eguzkilore.** `LICENSE.txt` is the GPL-2 text, but three
    source headers say "either version 3 of the License". Resolve this the
    same way.
  - **Maia weights.** GPL-3. The bundled files are byte-identical (same
    git blob hashes) to their upstream copies, both in GPL-3.0 repos:
    - `maia-1100` … `maia-1900`: `CSSLab/maia-chess`, `maia_weights/`
      and release `v1.0`.
    - `maia-2200`: a community network by @CallOn84, in
      `CallOn84/LeelaNets`, `Nets/Maia 2200/`. LCZero's sparring-nets
      page links it.
    - Cite both sources in the PR.
- `meta.sourceProvenance = [ lib.sourceTypes.fromSource ]`.
- `meta.mainProgram = "lucaschess"`.
- `meta.maintainers`: the owner.
- `homepage`: `https://lucaschess.pythonanywhere.com`.

## Already verified

nixpkgs `lc0` 0.32.1 loads each of these networks, answers `readyok`, and
returns `bestmove` on the Eigen backend:
- `maia-1100.pb.gz`
- `maia-2200.pb.gz`
- `791556.pb.gz`

So Maia needs no older lc0.

## The plain lc0 engine is dropped

The owner decided this after looking at the options.
- **No LCZero network has a stated license.** That covers `791556` and the
  current recommended networks alike:
  - lc0's `COPYING` (GPL-3) covers the engine source. The lc0 repo contains
    no network files.
  - The networks are downloaded separately from `storage.lczero.org`. The
    download server and lczero.org's networks page carry no license text.
  - The only other license LCZero states is ODbL, and it covers the
    training data, not the networks.
- **pkgs/README:** "If there is no upstream license, `meta.license` should
  default to `lib.licenses.unfree`". One unfree file would make the whole
  package unfree.
- **Excluded alternatives:**
  - Shipping it as unfree, for the reason above.
  - Asking LCZero to state a license, which the owner doesn't want to do.
- **Effect:** the `lc0` engine entry disappears. Users can still add lc0
  as an external engine with a network they download themselves.
- **The PR description** gives this reason in the "excluded" part.

## To verify during the build

These don't change the design, but the PR states their results:

1. Lucas Chess works from a read-only store path with `LUCASCHESS_HOME`
   set. Smoke-test each of these:
   - Start-up.
   - Play against Irina.
   - Analysis with Stockfish.
   - Maia at two levels.
   - A kibitzer, which is a helper process.
   - A short engine tournament, which uses worker processes.
2. Nothing writes into the store. Look for permission errors in the
   `bug.*` logs under `LUCASCHESS_HOME`.

## nixpkgs contribution rules

Sources: `CONTRIBUTING.md`, `pkgs/README.md`, `pkgs/by-name/README.md`,
`maintainers/README.md` and `.github/PULL_REQUEST_TEMPLATE.md` in the fork.
Each rule below is a requirement unless marked otherwise.

### Before submitting: suitability (pkgs/README "Quick Start")

The PR must answer the questions reviewers ask of a new package:
- **Ready for general use?** Yes, R6 has regular tagged releases.
- **Clear license?** Yes, see "Platform and metadata".
- **Used by others?** The PR says what Lucas Chess is and why it belongs
  in nixpkgs. Upstream issue activity or other distributions' packages
  are useful evidence.
- **Maintained upstream?** Yes, R6.2.0 is recent.
- **Owner willing to maintain it** for at least one full release cycle?
  Yes.
- **Built from source where possible.** This design does that.
- **Security-critical parts unvendored.** Not applicable beyond the
  engines, which come from nixpkgs.

### Commits (CONTRIBUTING "Commit conventions", pkgs/README "Commit conventions")

- One commit per logical unit. Squash fixups before pushing.
- Subject lines have no trailing period.
- **Commit 1:** `maintainers: add <handle>`. It adds an entry to
  `maintainers/maintainer-list.nix`:
  - Required fields: `name`, `github` and `githubId`, and the GitHub name
    and ID must match. Optional fields: `email`, `matrix` and `keys`.
  - The handle should equal the GitHub username (`tristanlirette`).
  - The entry is settled. The owner gave the name and email, and the
    GitHub API confirmed the login, ID and name:
    ```nix
    tristanlirette = {
      name = "Tristan Lirette";
      email = "dev@tristanl.net";
      github = "tristanlirette";
      githubId = 31151912;
    };
    ```
    No `matrix` and no `keys`. Signing isn't required for maintainers.
  - Keep the list alphabetical.
  - Check it with `nix-build lib/tests/maintainers.nix`.
  - Add `keys` only if the owner really signs with them. In that case,
    this commit must be signed with that key.
- **Commit 2:** `lucaschess: init at 6.2.0`. Its body says what Lucas
  Chess is and links the homepage.
  - The `lucaschess:` prefix is also what makes CI build the package.
- **Every commit** ends with `Assisted-by: Claude Code (Claude Opus 5.5)`,
  or whichever model actually did the work. That format matches the
  trailers already used on nixpkgs `master`. Never `Co-authored-by:`.

### Code (CONTRIBUTING "Code conventions", pkgs/README "Conventions")

- File and directory names in kebab-case: `pkgs/by-name/lu/lucaschess/`.
- `pname = "lucaschess"`, lowercase. The attribute name is the same.
- `version` starts with a digit: `6.2.0`.
- Formatted with nixfmt. CI runs it; run `nix fmt` or `treefmt` locally.
- Arguments listed explicitly, with no `...` or `with args;`.
  - Use `lib.optional(s)` for conditional lists.
  - No needless string conversions: `tag = "R${version}"` is fine.
- No import-from-derivation.
- No new `overrideAttrs` or `overridePythonAttrs` on other packages. Use
  `stockfish` and `lc0` as they are. Maia uses `lc0`.
- Use the language framework for Python. See "Patches carried over from
  this repo's flake".
- Build-only tools go in `nativeBuildInputs`: Cython, p7zip and the
  wrappers.
- Don't override the `phases` list. Any overridden phase starts with
  `runHook pre<Phase>` and ends with `runHook post<Phase>`.
- `passthru` comes before `meta`, and `meta` is the last attribute.
- **Every patch and `substituteInPlace`** is either a clearly named
  `.patch` file or has a comment that says *why* it exists. Every vendored
  patch also says either its upstream URL or why it wasn't sent upstream.
  - The `LUCASCHESS_HOME` patch links the upstream PR once it exists.
  - The registry, self-updater and read-only-copy patches say they are
    Nix-specific.
- Every non-default build flag gets a comment. That covers `-std=gnu17`
  and any Makefile flag overrides.

### Metadata (pkgs/README "Meta attributes")

- `description`:
  - One sentence, capitalized, factual.
  - No leading article, no package name, no trailing punctuation.
  - The flake's "Chess GUI for training, play against UCI engines and
    engine tournaments" fits.
- `license` matches upstream. See "Platform and metadata".
- `platforms` is set. Without it there are no binary substitutes.
- `maintainers` is set.
- `mainProgram = "lucaschess"`, as a literal string, not `pname`.
- `sourceProvenance`: `fromSource` only.

### Testing before the PR (CONTRIBUTING "Pull request template")

- Build with the sandbox on. It's the default on Linux.
- Run `nixpkgs-review rev HEAD` (or `pr <number>` once open), and say so
  in the PR.
- Run every binary in `./result/bin/`. That's `lucaschess`, plus the
  smoke tests in "To verify during the build".
- **Recommended:** `passthru.tests`, since packages with tests get merged
  faster. A GUI is hard to test headless, so a small test is enough. For
  example: import FasterCode, and do a UCI handshake with `irina`,
  `eguzki` and `eguzkilore`. The builder chooses what is feasible.

### The PR (CONTRIBUTING "How to create pull requests" and "How to help committers")

- Branch from current `upstream/master`, push to `origin`, and open the PR
  against `NixOS/nixpkgs` `master`.
- The title matches the commit: `lucaschess: init at 6.2.0`.
- Keep the template and tick only what was actually done:
  - "Fits CONTRIBUTING.md…"
  - "Follows the automation/AI policy"
  - "Built on x86_64-linux"
  - "Basic functionality of all binary files"
  - "Ran nixpkgs-review"
  - "Package tests", if added
- Give reviewers a ready-to-run smoke test, a short recipe showing it
  works.
- Keep the PR mergeable. Answer all review comments in one round.

## PR description must cover

- What Lucas Chess is, its homepage, and why it belongs in nixpkgs.
- The engine policy and the table above, condensed, with the reason for
  each excluded group.
- The DigitalBoards drivers as planned future work, once the package is
  merged.
- The upstream PR link for `LUCASCHESS_HOME`, if one exists.
- What was smoke-tested, and a recipe reviewers can run themselves.
- A disclosure of LLM use in writing the PR text itself. The policy
  requires this separately from the commit trailers.

## Optional side task: propose the patch upstream

Send the same `LUCASCHESS_HOME` diff to `lukasmonk/lucaschessR6` whenever
the owner chooses.
- Upstream has never merged an outside PR, and its commits are
  whole-release snapshots, so the nixpkgs package doesn't wait for it.
- If upstream merges the patch, or implements it differently, drop or
  adapt the patch at the next version bump.

## Left to the builder

- How the three in-tree engines are built:
  - inside the main derivation, or as small derivations in `package.nix`;
  - how `src.7z` is unpacked (`p7zip`);
  - overriding the Makefiles' `-static`, `-s` and `-flto` flags.
- How the registry change is expressed: a patch file, or a generated
  replacement `OSEngines.py`.
- Whether to seed `uci_options.sqlite` from the bundled copy or let Lucas
  Chess build it. The bundled copy describes the old engine set.
- Whether to add `passthru.updateScript`, for example `gitUpdater` with
  `rev-prefix = "R"`.
- Exact wrapper mechanics: `makeWrapper` arguments, and where the
  launcher's Python entry point lives.
- Whether to prune the source archive in `postFetch`.
- What `passthru.tests` checks.
