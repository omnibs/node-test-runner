let
  sources = import nix/sources.nix { };
  pkgs = import sources.nixpkgs {
    overlays = [ (import nix/overlays/elm/default.nix) ];
  };
in
pkgs.mkShell ({
  name = "elm-safe-vdom-sample";

  buildInputs = [
    pkgs.vdom-patched-elm
    pkgs.nodejs_24
  ];

  # We move ELM_HOME to a local directory to avoid impacting projects
  # outside this repository with our elm-safe-virtual-dom patches.
  #
  # This helps elm-language-server look for deps at the right place,
  # if your editor supports direnv.
  ELM_HOME = "${builtins.dirOf __curPos.file}/_build/elm-home";
})
