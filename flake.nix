{
  description = "A very basic flake";

  inputs = {
    nixpkgs = { url = "nixpkgs/nixos-unstable"; };
    flake-utils = { url = "github:numtide/flake-utils"; };
     
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem(system:
    let
      pkgs = import nixpkgs {inherit system; };
      beamPkgs = with pkgs.beam; packagesWith interpreters.erlang_27;
    in
    with pkgs;
      {devShell = let
         a = "1";
         
        in pkgs.mkShell {
          buildInputs = [
            beamPkgs.erlang
            beamPkgs.elixir_1_17
                     ];

          shellHook = '' '';
        };
      });
}
