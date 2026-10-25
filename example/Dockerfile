# syntax=docker/dockerfile:1
# Conformance example app (WAI, Warp and Lucid). Build with the package folder
# as the context:  docker build -f example/Dockerfile .
FROM haskell:9.6 AS build
WORKDIR /src
# The package from this repo's own source (see example/cabal.project).
COPY privatus-analytics.cabal LICENSE README.md CHANGELOG.md ./
COPY src/ src/
COPY example/ example/
WORKDIR /src/example
ENV CABAL_DIR=/root/.cabal
RUN --mount=type=cache,target=/root/.cabal/packages \
    --mount=type=cache,target=/root/.cabal/store \
    cabal update -v0 && \
    cabal build -v1 exe:privatus-example && \
    cp "$(cabal list-bin exe:privatus-example)" /privatus-example

FROM debian:bullseye-slim
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends libgmp10 && rm -rf /var/lib/apt/lists/*
COPY --from=build /privatus-example /usr/local/bin/privatus-example
EXPOSE 8080
USER 65534
CMD ["privatus-example"]
