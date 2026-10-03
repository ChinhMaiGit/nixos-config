# Development setup: direnv with nix-direnv (a project's Nix dev shell turns on when you `cd`
# into it), and `pyinit`, which starts a Python project in one command: uv for the Python
# packages, a flake dev shell for Python itself and any system tools.
{ pkgs, ... }:

let
  # Written into each new project. nixpkgs is the stable branch this system uses; the project's
  # flake.lock pins the exact version. Add system tools (ffmpeg, ruff, ...) to `packages`.
  flakeTemplate = pkgs.writeText "python-flake.nix" ''
    {
      description = "@NAME@";

      inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

      outputs = { nixpkgs, ... }:
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          python = pkgs.@PYTHON@;
        in {
          devShells.x86_64-linux.default = pkgs.mkShell {
            packages = [ python pkgs.uv ];
            env = {
              # uv uses this Python instead of downloading its own
              UV_PYTHON = "''${python}/bin/python";
              UV_PYTHON_DOWNLOADS = "never";
              # Prebuilt wheels with C/C++ parts (numpy, polars, ...) expect these system
              # libraries; Nix's Python doesn't search the usual places. Add more if a package
              # reports a missing .so (e.g. pkgs.libGL for OpenCV).
              LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];
            };
          };
        };
    }
  '';

  # direnv: load the dev shell, then create/refresh .venv and activate it, so `python` and the
  # project's packages work directly (uv run works either way).
  envrc = pkgs.writeText "python-envrc" ''
    use flake
    uv sync --quiet
    source .venv/bin/activate
  '';

  pyinit = pkgs.writeShellScriptBin "pyinit" ''
    set -euo pipefail
    if [ $# -lt 1 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
      echo "usage: pyinit <project-name> [python-version, default 3.12]"
      echo "Creates the folder with uv init, a Nix dev shell (flake.nix) and direnv (.envrc)."
      exit 0
    fi
    name=$1
    version=''${2:-3.12}
    attr=python''${version//./}   # 3.12 -> python312
    if ! nix eval --raw "nixpkgs#$attr.version" >/dev/null 2>&1; then
      echo "pyinit: Python $version isn't in nixpkgs ($attr)" >&2
      exit 1
    fi
    if [ -e "$name" ]; then
      echo "pyinit: $name already exists" >&2
      exit 1
    fi

    mkdir -p "$name"
    cd "$name"
    ${pkgs.uv}/bin/uv init --quiet --python "$version" --name "$(basename "$name")"
    sed -e "s/@NAME@/$(basename "$name")/" -e "s/@PYTHON@/$attr/" ${flakeTemplate} > flake.nix
    cp ${envrc} .envrc
    chmod u+w flake.nix .envrc
    printf '\n# Nix / direnv\n.direnv/\nresult\n' >> .gitignore
    git add -A   # flakes only see files git tracks (no commit needed)
    echo "Pinning nixpkgs (the first time downloads it)..."
    nix flake lock
    git add flake.lock
    ${pkgs.direnv}/bin/direnv allow
    echo
    echo "Ready: $PWD"
    echo "  cd $name   (the dev shell and .venv turn on automatically)"
    echo "  uv add <package>   uv run main.py"
  '';
in
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;   # caches the dev shell, so entering a project is instant
    config.global.hide_env_diff = true;   # no long list of changed variables on every cd
  };

  home.packages = [ pyinit ];
}
