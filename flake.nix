{
	inputs.nixpkgs.url = github:nixos/nixpkgs;
	inputs.flake-utils.url = github:numtide/flake-utils;
	outputs = {
		self,
		nixpkgs,
		flake-utils
	}: flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: let
		pkgs = import nixpkgs {
			inherit system;
		};
		concatMapLines = f: args: pkgs.lib.concatLines (builtins.map f args);
		mergeDirs = opts: dirs: pkgs.runCommand (opts.name or "merged") opts (concatMapLines (path: "${pkgs.coreutils}/bin/cp -rT $out ${pkgs.escapeShellArg path}") dirs);
		mkRustPkg = { root, buildInputs ? [] }: let mf = (pkgs.lib.importTOML (root + /Cargo.toml)).package; in pkgs.rustPlatform.buildRustPackage rec {
			pname = mf.name;
			inherit (mf) version;
			src = pkgs.lib.cleanSource root;
			cargoLock.lockFile = root + /Cargo.lock;
			inherit buildInputs;
			postInstall = ''
				${pkgs.tree}/bin/tree target
				mkdir $out/rlib
				find target/*/release -name \*.rlib -print0 | xargs -0 cp -rt $out/rlib/
			'';
		};
	in rec {
		packages.deps = pkgs.runCommand "swici-deps" {
			buildInputs = [pkgs.gcc pkgs.rustc pkgs.cargo];
			__impure = true;
			# outputHash = "sha256:" + pkgs.lib.fakeSha256;
			# outputHashMode = "recursive";
		} ''
			export HOME=${./home /* this is VERY HACKY, run while you can */}
			mkdir .cargo
			echo "[http]"$'\n'"check-revoke = false" >> .cargo/config
			ln -s ${./Cargo.toml} Cargo.toml
			ln -s ${./Cargo.lock} Cargo.lock
			mkdir src
			ln -s ${builtins.toFile "main.rs" ''
				fn main() {}
			''} src/main.rs
			cargo --locked build
			mv target $out
		'';
		# if you even CONSIDER SNEEZING this ENTIRE FUCKING BUILD PROCESS will COLLAPSE INTO TINY SHITLETS OF HACKY WORKAROUNDS
		packages.depsHashed = pkgs.runCommand "swici-deps-hashed" {
			outputHash = sha256:hrCwrZ1SC99XDxwIqGCYlZrgrLFQcwssUXfXMJOQbD8=;
			outputHashMode = "recursive";
		} ''
			tar cJvf $out ${packages.deps}
		'';
		packages.default = pkgs.runCommand "swici" {
			buildInputs = [pkgs.gcc pkgs.rustc pkgs.cargo];
		} ''
			export HOME=${./home /* see above comment */}
			ln -s ${./src} src
			ln -s ${./Cargo.toml} Cargo.toml
			ln -s ${./Cargo.lock} Cargo.lock
			mkdir target
			tar fCJvx ${packages.depsHashed} target
			touch target/**
			cargo --frozen build
			mkdir -p $out/bin
			mv target/*/swici $out/bin/ || (${pkgs.tree}/bin/tree; exit 1)
		'';
	});
}
