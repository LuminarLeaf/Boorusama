{
  description = "Boorusama Linux build";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {allowUnfree = true;};
    };
  in {
    packages.${system}.default = pkgs.flutter327.buildFlutterApplication rec {
      pname = "boorusama";
      version = "4.0.16";
      src = ./.;

      nativeBuildInputs = with pkgs; [
        autoPatchelfHook
        mdk-sdk
        jdk21
        jq
        yq-go
      ];

      buildInputs = with pkgs; [
        alsa-lib
        libdrm
        libepoxy
        libGL
        mesa
      ];

      runtimeDependencies = with pkgs; [libva];

      # TODO: Move to non IFD
      # pubspecLock = lib.importJSON ./pubspec.lock.json;
      autoPubspecLock = src + "/pubspec.lock";

      flutterBuildFlags = [
        "--release"
        "--dart-define-from-file env/foss.json"
      ];

      buildPhase = ''
        runHook preBuild

        PACKAGE_CONFIG_JSON=".dart_tool/package_config.json"
        TEMP_JSON=$(mktemp)
        mv $PACKAGE_CONFIG_JSON $TEMP_JSON

        LOCAL_PACKAGES=$(yq eval '.dependencies | to_entries | map(select(.value.path)) | map({ "name": .key, "rootUri": ("../" + .value.path), "packageUri": "lib/" })' -oj < ./pubspec.yaml)
        JQ_FILTER='.packages += $local_packages'

        jq --argjson local_packages "$LOCAL_PACKAGES" "$JQ_FILTER" "$TEMP_JSON" > $PACKAGE_CONFIG_JSON

        mkdir -p build/flutter_assets/fonts

        flutter build linux -v --split-debug-info="$debug" $flutterBuildFlags

        runHook postBuild
      '';

      gitHashes = {
        context_menus = "sha256-TglVuFdNGC8st08F8kVhREKG0aMr2qIgx9+qDJhBVl8=";
        flutter_launcher_icons = "sha256-sGlMmHVG2hJx6H3fujl8Vnt2hje2oM0noiSuqs6FQ2s=";
        fvp = "sha256-79O9INAnEAYsaxsDlLtnMfJqEV650a74UuNZ8Lu9FW4=";
        reorderables = "sha256-LTeCKYQZLHoKinmBHv0v9bpA3oEHu5fGVOZQ+JOzY84=";
        searchfield = "sha256-HXs1/q3zQSjGZYUKekfIR+/UCXhQOj56BtCqD1s6d9o=";
        webview_cookie_manager = "sha256-fd+T1XpDXBuFYAgzlKUMQ5sTjQ07R7eaj03pYdJnpuA=";
      };

      meta.mainProgram = "boorusama";
    };
  };
}
