Adds [Lucas Chess](https://lucaschess.pythonanywhere.com), a chess GUI for training, playing against UCI engines and running engine tournaments.

## Engines

An engine is included if it is:
- in nixpkgs already: used as a dependency;
- written by the Lucas Chess author: built from upstream's sources in this package.

| Engine | Source |
|---|---|
| Stockfish | nixpkgs `stockfish` |
| Maia 1100–1900, 2200 | nixpkgs `lc0`, with the Maia weights from the source tree |
| Irina, Eguzki, Eguzkilore | Built from upstream's sources |

The Maia weights are GPL-3. `maia-1100`…`1900` are the files from [CSSLab/maia-chess](https://github.com/CSSLab/maia-chess), and `maia-2200` is from [CallOn84/LeelaNets](https://github.com/CallOn84/LeelaNets).

Not included:
- 58 engines with source available but not in nixpkgs. Each can be added once it's packaged.
- 8 binary-only engines: Andscacs, Clarabit, Critter, Gaviota, Gödel, Jabba, Komodo, Zappa.
- lc0 as an engine of its own: no LCZero network has a stated license.

## Source

- `postFetch` removes upstream's prebuilt binaries: the engines, e-board drivers, the FasterCode extension and the Windows build. Several are unfree. This takes the source from 1.1 GB to 257 MB.
- `x86_64-linux` only: the bundled C core uses x86 `cpuid`.

## Patches

Upstreamable, in [lukasmonk/lucaschessR6#91](https://github.com/lukasmonk/lucaschessR6/pull/91):
- `configurable-data-dir.patch`: user data, logs and caches go to `$LUCASCHESS_HOME` instead of the program folder. The wrapper defaults it to `$XDG_DATA_HOME/lucaschess`.
- `absolute-file-arguments.patch`: relative file arguments work. Lucas Chess changes into its own folder at startup.

Nix-specific:
- `remove-unpackaged-engines.patch`: registers only the included engines.
  - Hides the features that need Rodent II: the Rodent personalities menu, the "Indexes - RodentII" kibitzer and the Rodent book.
  - Keeps saved Grid ELO progress against engines that aren't installed.
  - Albums that use Fruit, Critter or Komodo fall back to the tutor engine, Stockfish by default. This is upstream behaviour.
- `postPatch`: makes files copied out of the store writable, and disables the self-updater.

The launcher runs a `python3.withPackages` interpreter. Helper processes (kibitzers, tournaments, …) re-run `sys.executable`, and a `PYTHONPATH` would leak into the engines.

## Testing

- `nix-build -A lucaschess.tests`: launcher, UCI handshake of each engine, FasterCode, engine registry.
- In the GUI: start-up, a game against Irina, analysis with Stockfish, Maia at two levels, a kibitzer, a short engine tournament.

Written with Claude Opus 5.5.

## Things done

<!--
Please check what applies. Note that these are not hard requirements but merely serve as information for reviewers.
However, please do not remove the template, even when nothing is checked!
-->

- [x] Fits [CONTRIBUTING.md], [pkgs/README.md], [maintainers/README.md] and other READMEs.
- [x] Follows the [automation/AI policy].
- Built on platform:
  - [x] x86_64-linux
  - [ ] aarch64-linux
  - [ ] aarch64-darwin
- Tested, as applicable:
  - [x] Basic functionality of all binary files, usually in `./result/bin/`.
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
