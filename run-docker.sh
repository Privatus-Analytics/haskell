#!/bin/sh
# Builds, tests, lints, checks formatting, runs cabal check, cabal sdist and
# haddock in the official haskell:9.6 image. Usage: ./run-docker.sh
#
# The cabal store, the build folder and the hlint and ormolu binaries live in
# named Docker volumes, so only the first run is slow.
set -e
docker run --rm \
  -v "$PWD":/app:ro \
  -v privatus-haskell-cabal:/root/.cabal \
  -v privatus-haskell-dist:/build \
  -w /app \
  -e CABAL_DIR=/root/.cabal \
  haskell:9.6 sh -c 'set -e
  # Work on a copy, so nothing is written to your folder.
  mkdir -p /src && cp -R /app/. /src && rm -rf /src/dist-newstyle && cd /src
  export PATH=/root/.cabal/bin:$PATH
  cabal update -v0 --builddir=/build
  if ! command -v hlint >/dev/null || ! command -v ormolu >/dev/null; then
    echo "Installing hlint and ormolu (first run only)..."
    cd / && cabal install -v1 --overwrite-policy=always --installdir=/root/.cabal/bin --install-method=copy \
      hlint-3.8 ormolu-0.7.4.0 && cd /src
  fi
  cabal build -v1 --builddir=/build all
  cabal test --builddir=/build --test-show-details=direct
  hlint src test
  ormolu --mode check $(find src test -name "*.hs")
  cabal check
  cabal sdist --builddir=/build -o /build/sdist
  cabal haddock --builddir=/build lib:privatus-analytics
  echo "All checks passed."
'
