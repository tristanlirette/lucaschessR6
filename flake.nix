{
  description = "Lucas Chess R6: chess GUI for training, play against UCI engines and engine tournaments";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # The bundled engines and e-board drivers are prebuilt x86_64 Linux binaries.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;

      # Parsed from bin/Code/__init__.py, e.g. VERSION = "R 6.2.0"
      version = builtins.head (
        builtins.match ''.*VERSION = "R ([0-9.]+)".*'' (builtins.readFile ./bin/Code/__init__.py)
      );

      python = pkgs.python3;

      # A python.withPackages env, not a wrapped script: the app re-executes
      # sys.executable for its helper processes (kibitzers, tournaments, ...),
      # so the interpreter itself has to see the packages.
      pythonDeps = ps: [
        ps.charset-normalizer
        ps.chess
        ps.pillow
        ps.polib
        ps.psutil
        ps.pyside6
        ps.requests
        ps.sortedcontainers
      ];
      pythonEnv = python.withPackages pythonDeps;

      # Rebuilt from source: the committed .so only loads on CPython 3.12.
      fastercode = pkgs.stdenv.mkDerivation {
        pname = "lucaschess-fastercode";
        inherit version;
        src = ./bin/_fastercode/src;

        nativeBuildInputs = [
          (python.withPackages (ps: [
            ps.cython
            ps.setuptools
          ]))
        ];

        # irina/defs.h has `typedef char bool`, an error under GCC 15's default C23.
        env.NIX_CFLAGS_COMPILE = "-std=gnu17";

        # Same steps as fastercode_linux.sh; setup_linux.py uses distutils, gone since 3.12.
        buildPhase = ''
          runHook preBuild
          (cd irina && $CC -O2 -fPIC -fno-strict-aliasing -DNDEBUG -c *.c && $AR rcs ../libirina.a *.o)
          cat Faster_Irina.pyx Faster_Polyglot.pyx > FasterCode.pyx
          python -c '
          from setuptools import setup, Extension
          from Cython.Build import cythonize
          setup(ext_modules=cythonize([Extension("FasterCode", ["FasterCode.pyx"], libraries=["irina"], library_dirs=["."])]))
          ' build_ext --inplace
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm555 -t $out FasterCode*.so
          runHook postInstall
        '';
      };

      # The read-only program tree: bin/ and Resources/ as upstream lays them out.
      unwrapped = pkgs.stdenv.mkDerivation {
        pname = "lucaschess-unwrapped";
        inherit version;

        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.difference (lib.fileset.unions [
            ./bin/LucasR.py
            ./bin/Code
            ./bin/OS/linux
            ./Resources
          ]) (lib.fileset.fileFilter (f: lib.hasPrefix "FasterCode." f.name) ./bin/OS/linux);
        };

        nativeBuildInputs = [
          pkgs.autoPatchelfHook
          python
        ];

        # Libraries needed by the bundled engines (lc0, texel, ...) and the
        # e-board drivers in DigitalBoards/, which the app loads with ctypes.
        buildInputs = [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
          pkgs.numactl
          pkgs.libx11
          pkgs.libGL
          pkgs.libxkbcommon
          pkgs.hidapi
          pkgs.bluez
          pkgs.dbus
          pkgs.qt6.qtbase
        ];

        # Only libnut.so (Novag UCB e-board) wants Qt5Pas, which isn't shipped.
        autoPatchelfIgnoreMissingDeps = [ "libQt5Pas.so.1" ];
        dontWrapQtApps = true;
        dontStrip = true;

        postPatch = ''
          # Files copied out of the store keep its read-only mode, and the app
          # later rewrites them (recursos.dbl, sounds.pkd, piece SVGs).
          substituteInPlace bin/Code/Z/Util.py \
            --replace-fail "shutil.copy2(origin_path, destino_path)" \
                           "shutil.copy2(origin_path, destino_path)
                  if destino_path.is_file():
                      destino_path.chmod(destino_path.stat().st_mode | 0o200)"
          substituteInPlace bin/Code/QT/Piezas.py \
            --replace-fail "shutil.copy(source_file, dest_file)" "shutil.copyfile(source_file, dest_file)" \
            --replace-fail "shutil.copy(ori, dest)" "shutil.copyfile(ori, dest)"

          # The self-updater unpacks releases and e-board drivers into the program tree.
          substituteInPlace bin/Code/Z/Update.py \
            --replace-fail "def update(main_window):" \
                           "def update(main_window):
              QTMessages.message(main_window, 'This Lucas Chess is installed with Nix. Update it through the flake.')
              return False" \
            --replace-fail "def update_manual(main_window) -> bool:" \
                           "def update_manual(main_window) -> bool:
              return update(main_window)" \
            --replace-fail "def test_update(procesador):" \
                           "def test_update(procesador):
              return"
        '';

        installPhase = ''
          runHook preInstall
          share=$out/share/lucaschess
          mkdir -p $share
          cp -r bin Resources $share/
          cp ${fastercode}/FasterCode*.so $share/bin/OS/linux/

          # Use qtbase's PrintSupport, matching the Qt that PySide6 loads.
          rm $share/bin/OS/linux/DigitalBoards/libQt6PrintSupport.so.6

          # Engines are committed without the exec bit and read_engines() chmods
          # them at startup, which would fail in the store.
          find $share/bin/OS/linux/Engines -type f -print0 | while IFS= read -r -d "" f; do
            if [ "$(head -c4 "$f" | tail -c3 | tr -d '\0')" = ELF ]; then chmod +x "$f"; fi
          done

          # Two bundled game databases are in WAL mode, which needs -shm/-wal files
          # next to the database even to read it. Switch them to rollback mode.
          python - $share/Resources <<'EOF'
          import pathlib, sqlite3, sys
          for p in pathlib.Path(sys.argv[1]).rglob("*"):
              if not p.is_file():
                  continue
              with p.open("rb") as f:
                  header = f.read(19)
              if header[:16] == b"SQLite format 3\0" and header[18] == 2:
                  con = sqlite3.connect(p)
                  con.execute("PRAGMA journal_mode=DELETE")
                  con.close()
                  print("converted from WAL:", p)
          EOF

          # The launcher runs with PYTHONOPTIMIZE=1; hash-less pycs ignore store mtimes.
          python -m compileall -q -o 1 --invalidation-mode unchecked-hash \
            $share/bin/Code $share/bin/OS/linux/OSEngines.py
          runHook postInstall
        '';
      };

      # Code/__init__.py chdirs to bin/ and everything is relative to it: logs in
      # bin/, user data in ../UserData, the engine option cache in bin/OS/linux.
      # So we run from a writable mirror of the tree whose read-only parts are
      # symlinks into the store.
      launcher = pkgs.writeShellApplication {
        name = "lucaschess";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.diffutils
        ];
        text = ''
          share=${unwrapped}/share/lucaschess
          root="''${LUCASCHESS_HOME:-''${XDG_DATA_HOME:-$HOME/.local/share}/lucaschess}"

          # File arguments (.pgn, .lcdb, ...) must be absolute: we're about to cd.
          args=()
          for arg in "$@"; do
            if [[ $arg != -* && -e $arg ]]; then
              args+=("$(realpath "$arg")")
            else
              args+=("$arg")
            fi
          done

          link() {
            if [[ "$(readlink "$2" 2>/dev/null)" != "$1" ]]; then
              ln -sfnT "$1" "$2"
            fi
          }

          mkdir -p "$root/bin/OS/linux" "$root/UserData"
          link "$share/Resources" "$root/Resources"
          link "$share/bin/Code" "$root/bin/Code"

          # Drop links left by a previous version, then link this one.
          for f in "$root/bin/OS/linux"/*; do
            if [[ -L $f && "$(readlink "$f")" != "$share"/* ]]; then
              rm -f "$f"
            fi
          done
          for f in "$share/bin/OS/linux"/*; do
            name=$(basename "$f")
            if [[ $name != uci_options.sqlite ]]; then
              link "$f" "$root/bin/OS/linux/$name"
            fi
          done

          # Writable: internal engines' UCI options are cached here on first use.
          if [[ ! -e "$root/bin/OS/linux/uci_options.sqlite" ]]; then
            install -m644 "$share/bin/OS/linux/uci_options.sqlite" "$root/bin/OS/linux/"
          fi

          # A copy, not a link: Code/__init__.py finds bin/ via realpath(argv[0]).
          if ! cmp -s "$share/bin/LucasR.py" "$root/bin/LucasR.py"; then
            install -m644 "$share/bin/LucasR.py" "$root/bin/LucasR.py.tmp.$$"
            mv -f "$root/bin/LucasR.py.tmp.$$" "$root/bin/LucasR.py"
          fi

          cd "$root/bin"
          # Inherited by the helper processes the GUI spawns.
          export PYTHONOPTIMIZE=1
          exec ${pythonEnv}/bin/python3 LucasR.py "''${args[@]}"
        '';
      };

      desktopItem = pkgs.makeDesktopItem {
        name = "lucaschess";
        desktopName = "Lucas Chess";
        genericName = "Chess GUI";
        comment = "Train, play against engines and run engine tournaments";
        exec = "lucaschess %f";
        icon = "lucaschess";
        categories = [
          "Game"
          "BoardGame"
        ];
        mimeTypes = [ "application/x-chess-pgn" ];
      };

      lucaschess = pkgs.stdenv.mkDerivation {
        pname = "lucaschess";
        inherit version;
        dontUnpack = true;

        nativeBuildInputs = [
          pkgs.qt6.wrapQtAppsHook
          pkgs.copyDesktopItems
        ];

        # Qt plugins for PySide6: platforms, SVG, multimedia (sounds). No
        # qtwayland: run_gui() forces QT_QPA_PLATFORM=xcb on Wayland sessions.
        buildInputs = [
          pkgs.qt6.qtbase
          pkgs.qt6.qtsvg
          pkgs.qt6.qtmultimedia
        ];

        desktopItems = [ desktopItem ];
        dontWrapQtApps = true;

        installPhase = ''
          runHook preInstall
          makeQtWrapper ${lib.getExe launcher} $out/bin/lucaschess
          install -Dm644 ${unwrapped}/share/lucaschess/Resources/IntFiles/logo64r.png \
            $out/share/icons/hicolor/64x64/apps/lucaschess.png
          runHook postInstall
        '';

        passthru = { inherit unwrapped fastercode pythonEnv; };

        meta = {
          description = "Chess GUI for training, play against UCI engines and engine tournaments";
          homepage = "https://lucaschess.pythonanywhere.com";
          license = lib.licenses.gpl3Only;
          mainProgram = "lucaschess";
          platforms = [ system ];
          # Bundles prebuilt engines and e-board drivers.
          sourceProvenance = [
            lib.sourceTypes.fromSource
            lib.sourceTypes.binaryNativeCode
          ];
        };
      };
    in
    {
      packages.${system} = {
        inherit lucaschess;
        default = lucaschess;
      };

      apps.${system}.default = {
        type = "app";
        program = lib.getExe lucaschess;
      };

      # For running from the checkout (python3 bin/LucasR.py) and rebuilding FasterCode.
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          (python.withPackages (
            ps:
            pythonDeps ps
            ++ [
              ps.cython
              ps.setuptools
            ]
          ))
        ];
        inputsFrom = [ lucaschess ];
      };
    };
}
