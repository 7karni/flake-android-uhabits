{
  description = "Loop Habit Tracker (uhabits): reproducible apk build with nix";
  inputs = {nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";};
  outputs = {
    self,
    nixpkgs,
  }: let
    lib = nixpkgs.lib;
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfreePredicate = pkg: let
        pname = pkg.pname or (lib.getName pkg);
        isAndroidSdkComponent = builtins.elem pname [
          "platforms"
          "build-tools"
          "platform-tools"
          "tools"
          "cmdline-tools"
          "system-images"
          "emulator"
          "ndk-bundle"
          "sources"
          "add-ons"
        ];
      in
        isAndroidSdkComponent
        || lib.hasPrefix "android-" pname;
    };
    src = pkgs.fetchFromGitHub {
      owner = "iSoron";
      repo = "uhabits";
      rev = "dev";
      sha256 = "0qklvnfkkq5ld56ddk7hmm4sfcdwa7lxk1jfsmzldhxakqxzlc29";
    };
    androidSdk = (pkgs.androidenv.override {licenseAccepted = true;})
      .composeAndroidPackages {
      platformVersions = ["36"];
      buildToolsVersions = ["35.0.0"];
      includeEmulator = false;
      includeNDK = false;
      includeSystemImages = false;
      includeSources = false;
      includeExtras = [];
      includeCmake = false;
    };
    fhs = pkgs.buildFHSEnv {
      name = "uhabits-fhs";
      targetPkgs = pkgs:
        with pkgs; [
          jdk17
          git
          glibc
          zlib
          stdenv.cc.cc.lib
          androidSdk.androidsdk
        ];
      profile = ''
        export ANDROID_HOME="${androidSdk.androidsdk}/libexec/android-sdk"
        export ANDROID_SDK_ROOT="${androidSdk.androidsdk}/libexec/android-sdk"
      '';
      runScript = "bash";
    };
  in {
    packages.${system} = {
      uhabits = pkgs.stdenv.mkDerivation {
        pname = "uhabits";
        version = "2.3.1";
        inherit src;
        nativeBuildInputs = [
          fhs
          pkgs.jdk17
          pkgs.git
        ];
        ANDROID_HOME = "${androidSdk.androidsdk}/libexec/android-sdk";
        buildPhase = ''
          mkdir -p "$PWD/home/.android"
          export HOME="$PWD/home"
          export ANDROID_USER_HOME="$PWD/home/.android"
          export GRADLE_USER_HOME="$out-gradle"
          ${fhs}/bin/uhabits-fhs -c '
            cd "$1" || exit 1
            sh ./gradlew \
              --no-daemon \
              -Dorg.gradle.jvmargs="-Xms2048m -Xmx2048m" \
              :uhabits-android:assembleDebug
          ' sh "$PWD"
        '';
        installPhase = ''
          mkdir -p "$out"
          cp uhabits-android/build/outputs/apk/debug/uhabits-android-debug.apk "$out/"
        '';

        meta = with pkgs.lib; {
          description = "Loop Habit Tracker - habit tracker for Android";
          homepage = "https://github.com/iSoron/uhabits";
          license = licenses.gpl3Plus;
          platforms = ["x86_64-linux"];
        };
      };
      default = self.packages.${system}.uhabits;
    };

    devShells.${system}.default = fhs.env;
    apps.${system} = {
      install = {
        type = "app";
        program = toString (pkgs.writeShellApplication {
          name = "uhabits-install";
          runtimeInputs = [androidSdk.androidsdk];
          text = ''
            apk="${self.packages.${system}.uhabits}/uhabits-android-debug.apk"
            echo "installing $apk"
            adb install -r "$apk"
          '';
        });
      };
      default = self.apps.${system}.install;
    };
  };
}
