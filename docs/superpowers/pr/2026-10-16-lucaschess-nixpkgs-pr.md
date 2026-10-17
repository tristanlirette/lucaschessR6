Adds [Lucas Chess](https://lucaschess.pythonanywhere.com), a chess GUI for training, playing against UCI engines and running engine tournaments.

- Built from source. `postFetch` removes upstream's prebuilt binaries: about 70 engines (several unfree), e-board drivers and the Windows build.
- Engines: Stockfish and lc0 (for Maia) from nixpkgs; Irina, Eguzki and Eguzkilore built from upstream's sources. Other engines can follow once they're packaged in nixpkgs.
- User data goes to `$XDG_DATA_HOME/lucaschess` instead of the store (`configurable-data-dir.patch`, to be submitted upstream).
- `x86_64-linux` only: the bundled C core uses x86 `cpuid`.

Written with Claude Code (Claude Opus 5.5). I reviewed and tested it, and will maintain the package.

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
