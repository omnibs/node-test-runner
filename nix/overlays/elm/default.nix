self: super:
let
  # Fetch forks for lydell/safe-elm-virtual-dom
  #   see: https://github.com/lydell/elm-safe-virtual-dom/tree/main?tab=readme-ov-file#the-forks
  #
  # This record is conveniently structured to have each package's ELM_HOME
  # path as its key.
  patchedPackages = {
    "elm/virtual-dom/1.0.4" = rec {
      source = {
        owner = "lydell";
        repo = "virtual-dom";
        rev = "2366514"; # tip of the `safe` branch
        sha256 = "sha256-c+2fSg7HptenqI1KJZU8ytfFeQ9xvJbSa/eL4lQ3kAE=";
      };
      derivation = self.fetchFromGitHub source;
    };
    "elm/html/1.0.0" = rec {
      source = {
        owner = "lydell";
        repo = "html";
        rev = "0925779"; # tip of the `safe` branch
        sha256 = "sha256-ugWjEuszB50l+EyOgLwDGrKxJxCDrxpzTzHrCDry3p4=";
      };
      derivation = self.fetchFromGitHub source;
    };
    "elm/browser/1.0.2" = rec {
      source = {
        owner = "lydell";
        repo = "browser";
        rev = "f5de544"; # tip of the `safe` branch
        sha256 = "sha256-29axLnzXcLDeKG+CBX49pjt2ZcYVdVg04XVnfAfImvI=";
      };
      derivation = self.fetchFromGitHub source;
    };
    "rtfeldman/elm-css/18.0.0" = rec {
      source = {
        owner = "omnibs";
        repo = "elm-css";
        rev = "e54998ce73b6"; # tip of the `safe` branch
        sha256 = "sha256-rmil+7lAKUm7Fm0MCba23xyCA0CWrDb1ej5gPeXS2oU=";
      };
      derivation = self.fetchFromGitHub source;
    };
  };

  # A derivation that contains all patched packages in the same structure
  # that Elm uses in its $ELM_HOME/packages directory.
  #
  # It also includes a source.txt file in each package directory
  # that indicates the source of the package and its revision.
  #
  # source.txt is used by replace-kernel.packages.js to avoid re-patching
  # packages unnecessarily and to make sure to patch outdated packages.
  patches = self.stdenv.mkDerivation {
    name = "elm-package-patches";
    dontUnpack = true;

    installPhase = ''
      ${self.lib.concatStringsSep "\n" (
        self.lib.mapAttrsToList (name: value: ''
          echo "Copying contents of ${name}..."

          # Create the subdirectory inside the $out path
          mkdir -p "$out/${name}"

          # Copy the contents of the source derivation into the new subdirectory
          cp -rT "${value.derivation}" "$out/${name}"

          # Write a source.txt file with the source information
          # replace-kernel.packages.js expects this file
          echo "https://github.com/${value.source.owner}/${value.source.repo}/commit/${value.source.rev}" > "$out/${name}/source.txt"

        '') patchedPackages
      )}
    '';
  };

  # A derivation that runs lydell's Node script to patch Elm's core packages.
  patch-elm-packages = self.stdenv.mkDerivation {
    name = "elm";

    src = ./replace-kernel-packages.js;
    nativeBuildInputs = [ self.makeWrapper ];
    buildInputs = [ self.nodejs ];

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin

      makeWrapper ${self.nodejs}/bin/node $out/bin/patch-elm-packages \
        --add-flags $src # Pass the path to our script as an argument to node
    '';
  };
in
{
  # An `elm` executable that first patches the core packages, then runs the real Elm compiler.
  vdom-patched-elm = super.writeShellScriptBin "elm" ''
    # if patching fails, fail the script
    set -e

    # Allow overriding ELM_HOME, e.g. for CI scripts, etc
    # If not overridden, default to elm-home at the repo root
    export ELM_HOME="''${ELM_HOME:-${builtins.dirOf __curPos.file}/../../../_build/elm-home}"

    # Use flock to block concurrent attempts at patching elm packages
    mkdir -p "$ELM_HOME"
    LOCKFILE="$ELM_HOME/elm-safe-vdom.lock"
    touch "$LOCKFILE"
    exec {LOCK_FD}>"$LOCKFILE"
    ${self.util-linuxMinimal}/bin/flock "$LOCK_FD"

    # Run Lydell's patching script
    ${patch-elm-packages}/bin/patch-elm-packages ${patches}

    # Release the lock
    # (lock is released anyway on script exit, but this allows running `elm` concurrently)
    exec {LOCK_FD}>&-

    # At this point, we're reasonably sure that the virtual-dom library used for this
    # elm.json here was installed and patched, and we're ready to go!
    exec ${self.elmPackages.elm}/bin/elm "$@"
  '';
}
