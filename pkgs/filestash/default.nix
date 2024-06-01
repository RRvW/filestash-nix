{ lib
, buildNpmPackage
, filestash-src
, buildGoModule
, glib
, gotools
, libraw
, pkg-config
, pkgs
, pluginImageC ? false # Use plugin for image thumbnails based on C libraries
, giflib
, libwebp
, libheif
, libjpeg
, libtiff
, libpng
, brotli
, stdenv
, vips
, util-linux
, writeShellScriptBin

}:

let
  frontend = buildNpmPackage {
    pname = "filestash-src";
    version = "0.0.0";

    src = filestash-src;
    patches = [ ./fix-vm-polyfill.patch ];

    postPatch = ''
      cp ${./package.json} ./package.json
      cp ${./package-lock.json} ./package-lock.json
    '';

    nativeBuildInputs = [ brotli ];

    npmDepsHash = "sha256-l/uXjPkvqSnQ/xtPrcjtc2poJeAb+4NXKoX5NR1Hb7M=";
    #    npmDepsHash = "sha256-TfbzfwD08ewx18B0A14cjKH+eovzLYeOrwYdJoUdizM=";
    makeCacheWritable = true;
    # The prepack script runs the build script, which we'd rather do in the build phase.
    npmPackFlags = [ "--ignore-scripts" ];
    npmFlags = [ "--legacy-peer-deps" ];
    NODE_OPTIONS = "--openssl-legacy-provider";

    npmBuildScript = "build";

    # Compress static files
    postBuild = ''
      make -C public compress
    '';

    # Webpack output is not copied by buildNpmPackage
    postInstall = ''
      cp -rv server/ctrl/static/www "$out/lib/node_modules/filestash/server/ctrl/static/www"
    '';

    meta = with lib; {
      description = "Filestash Frontend";
      homepage = "https://filestash.app";
      license = licenses.agpl3Only;
    };
  };

  libtranscode = stdenv.mkDerivation {
    name = "libtranscode";
    src = filestash-src + "/server/plugin/plg_image_light/deps/src";
    buildInputs = [ libraw ];
    buildPhase = ''
      $CC -Wall -c libtranscode.c
      ar rcs libtranscode.a libtranscode.o
    '';
    installPhase = ''
      mkdir -p $out/lib
      mv libtranscode.a $out/lib/
    '';
  };
  libresize = stdenv.mkDerivation {
    name = "libresize";
    src = filestash-src + "/server/plugin/plg_image_light/deps/src";
    buildInputs = [ vips glib ];
    nativeBuildInputs = [ pkg-config ];
    buildPhase = ''
      $CC -Wall -c libresize.c `pkg-config --cflags glib-2.0`
      ar rcs libresize.a libresize.o
    '';
    installPhase = ''
      mkdir -p $out/lib
      mv libresize.a $out/lib/
    '';
  };
in
buildGoModule {
  pname = "filestash";
  version = "unstable-" + filestash-src.shortRev;
  inherit frontend;
  src = frontend + "/lib/node_modules/filestash";

  vendorHash = "sha256-ICikIZ7nJtV7lh+w5qD1CoXrsxJbYotn1XI+CAquNKI=";
  #proxyVendor = true;
  excludedPackages = [
    "server/generator"
    "server/plugin/plg_starter_http2"
    "server/plugin/plg_starter_https"
    "server/plugin/plg_search_sqlitefts"
    "server/plugin/plg_image_thumbnail"
    "external"
    "public"
  ] ++ lib.optional (!pluginImageC)
    "server/plugin/plg_image_c"
  ;

  buildInputs = [
    glib
    libraw
    libresize
    libtranscode
    vips
  ] ++ lib.optionals pluginImageC [
    giflib
    libwebp
    libheif
    libjpeg
    libtiff
    libpng
  ];

  nativeBuildInputs = [
    (writeShellScriptBin "git" "echo '${filestash-src.rev}'")
    gotools
    util-linux
    pkg-config
  ];

  patches = [
    ## Use flake input's lastModified as build date (see `postPatch` phase), as
    ## `time.Now()` is impure. The build date is used in Filestash's own version
    ## reporting and the http User-Agent when connecting to a backend.
    ./fix-impure-build-date.patch
  ];

  preBuild = ''
    go generate -x ./server/...
  '';

  postInstall = ''
    mv $out/bin/cmd $out/bin/filestash
  '';

  postPatch =
    let
      platform = {
        aarch64-linux = "linux_arm";
        x86_64-linux = "linux_amd64";
      }.${pkgs.hostPlatform.system} or (throw
        "Unsupported system: ${pkgs.hostPlatform.system}");
    in
    lib.optionalString (!pluginImageC) ''
      sed -i s/plg_image_c/plg_image_golang/g  server/plugin/index.go # Fixing C build is too much effort
      echo "Patched out plg_image_c"
    '' +
    ''
      cp -r ${./external} external # Copy in nonfunctioning package
      echo 'replace github.com/tredoe/osutil => ./external/github.com/tredoe/osutil'  >> go.mod

      substituteInPlace server/generator/constants.go --subst-var-by build_date '${
        toString filestash-src.lastModified
      }'

      ## fix "imported and not used" errors
      goimports -w server/

      sed -i 's#-L./deps -l:libresize_${platform}.a#-L${libresize.outPath}/lib -l:libresize.a -lvips#' server/plugin/plg_image_light/lib_resize_${platform}.go
      sed -i 's#-L./deps -l:libtranscode_${platform}.a#-L${libtranscode.outPath}/lib -l:libtranscode.a -lraw#' server/plugin/plg_image_light/lib_transcode_${platform}.go

      ## server/** requires globstar
      shopt -s globstar
      rename --no-overwrite --verbose linux_arm.go linux_arm64.go server/**
    ''
  ;

  meta = with lib; {
    description = "Filestash Frontend";
    homepage = "https://filestash.app";
    license = licenses.agpl3Only;
  };

}
