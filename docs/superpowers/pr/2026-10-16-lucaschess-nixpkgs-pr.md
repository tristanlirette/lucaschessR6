<!-- Draft for the nixpkgs PR. Title: lucaschess: init at 6.2.0 -->

Adds [Lucas Chess](https://lucaschess.pythonanywhere.com) R6
([source](https://github.com/lukasmonk/lucaschessR6)). It's a PySide6 chess
GUI for training, play against UCI engines, and engine tournaments.

## Packaging notes

**Everything is built from source.** Upstream's release tree bundles about 70
prebuilt Linux engines, 19 prebuilt e-board driver libraries and a prebuilt
`FasterCode` extension. None of them are installed.

| Component | Handling |
|---|---|
| FasterCode (upstream's C core, Cython bindings) | Built from `bin/_fastercode` |
| Irina, Eguzki, Eguzkilore (upstream's own engines) | Built from the source archives shipped next to them |
| Stockfish | nixpkgs `stockfish` |
| Maia (10 levels) | nixpkgs `lc0`, plus the Maia weights from the source tree. They are GPL-3: `maia-1100`…`1900` are byte-identical to [CSSLab/maia-chess](https://github.com/CSSLab/maia-chess), and `maia-2200` to [CallOn84/LeelaNets](https://github.com/CallOn84/LeelaNets). |
| ~62 other source-available engines | Not included. Each one first needs its own nixpkgs package. It can then be added here as a dependency, like Stockfish. |
| 10 binary-only engines (Andscacs, Clarabit, Critter, Gaviota, Gödel, Jabba, Komodo Dragon, Zappa, …) | Not included, since no source is available |
| Plain lc0 engine | Not included. No LCZero network has a stated license: lc0's GPL-3 covers the engine code, and the networks are distributed separately with no license. Maia's weights are not affected. |
| DigitalBoards e-board drivers | Not included. They're binary-only and their licenses are unclear. They could follow later as an opt-in unfree add-on. |

**Where Lucas Chess writes.** Upstream writes user data, logs and caches next
to its own `bin/`.
- `lucaschess-home.patch` adds a `LUCASCHESS_HOME` variable. When it's set,
  those writes go there; when it's unset, behaviour is unchanged.
- The wrapper defaults it to
  `${XDG_DATA_HOME:-$HOME/.local/share}/lucaschess`.
- `absolute-file-arguments.patch` keeps relative file arguments working,
  since Lucas Chess changes into its own directory at startup.
- Both patches are written to be upstreamable. Upstream PR: (none yet).

**Nix-specific patches:**
- `remove-unpackaged-engines.patch` registers only the shipped engines. It
  also hides the features that need Rodent II, which isn't shipped: the
  Rodent personalities menu, the "Indexes - RodentII" kibitzer and the
  default Rodent book. They would otherwise silently run another engine.
  Albums fall back to Stockfish, which shows no engine name.
- `postPatch` makes files copied out of the store writable, and disables the
  self-updater.

**Python.** Lucas Chess re-executes `sys.executable LucasR.py -<mode>` for
its helper processes (kibitzers, tournaments, …). The dependencies therefore
reach the interpreter through `PYTHONPATH` in the wrapper, not through a
wrapped script.

**Platform.** `x86_64-linux` only, because FasterCode's `cpu_flags.c` uses
x86 `cpuid`.

## Testing

```
nix-build -A lucaschess.tests   # launcher, UCI handshake of each engine, FasterCode, engine registry
nix-build -A lucaschess
LUCASCHESS_HOME=$(mktemp -d) ./result/bin/lucaschess
```

In the GUI I tested:
- start-up;
- play against Irina;
- analysis with Stockfish;
- Maia at two levels;
- a kibitzer;
- a short engine tournament.

<!-- Owner: confirm or edit this list after the manual pass. -->

## Things done

- [x] Fits [CONTRIBUTING.md], [pkgs/README.md], [maintainers/README.md] and other READMEs.
- [x] Follows the [automation/AI policy].
- Built on platform:
  - [x] x86_64-linux
  - [ ] aarch64-linux
  - [ ] aarch64-darwin
- Tested, as applicable:
  - [ ] Basic functionality of all binary files, usually in `./result/bin/`. <!-- tick after the manual GUI pass -->
  - [x] Ran `nixpkgs-review` on this PR. See [nixpkgs-review usage].
  - [x] [Package tests] at `passthru.tests`.
  - [ ] [NixOS tests] in [nixos/tests].
  - [ ] Tests in [lib/tests] or [pkgs/test] for functions and "core" functionality.
- Nixpkgs Release Notes
  - [ ] Package update: when the change is major or breaking.
- NixOS Release Notes
  - [ ] Module addition: when adding a new NixOS module.
  - [ ] Module update: when the change is significant.

[Package tests]: https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md#package-tests
[NixOS tests]: https://nixos.org/manual/nixos/unstable/index.html#sec-nixos-tests
[nixpkgs-review usage]: https://github.com/Mic92/nixpkgs-review#usage

[CONTRIBUTING.md]: https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md
[automation/AI policy]: https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md#automationai-policy
[lib/tests]: https://github.com/NixOS/nixpkgs/blob/master/lib/tests
[maintainers/README.md]: https://github.com/NixOS/nixpkgs/blob/master/maintainers/README.md
[nixos/tests]: https://github.com/NixOS/nixpkgs/blob/master/nixos/tests
[pkgs/README.md]: https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md
[pkgs/test]: https://github.com/NixOS/nixpkgs/blob/master/pkgs/test

---

The package, the patches and this description were written with Claude Code
(Claude Opus 5.5). I reviewed and tested them, and I'll maintain the package.
