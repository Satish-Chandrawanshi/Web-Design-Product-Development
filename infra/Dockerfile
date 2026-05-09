# syntax=docker/dockerfile:1.6
FROM swift:5.10-jammy AS build
WORKDIR /build
COPY server/Package.swift Package.resolved* ./server/
WORKDIR /build/server
RUN swift package resolve
COPY server/ /build/server/
RUN swift build -c release --static-swift-stdlib
RUN mkdir -p /staging \
    && cp .build/release/Run /staging/ \
    && find -L .build/release -name '*.resources' -exec cp -R {} /staging/ \;

FROM ubuntu:22.04 AS runtime
RUN apt-get update -q \
    && apt-get install -q -y --no-install-recommends \
        ca-certificates tzdata libcurl4 \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --shell /bin/bash vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging /app
USER vapor
EXPOSE 8080
ENTRYPOINT ["/app/Run"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "8080"]
