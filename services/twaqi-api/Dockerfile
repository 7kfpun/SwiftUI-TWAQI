# Cloud Run image for twaqi-api (Rust). Built by Cloud Build from this folder
# (`make deploy`). The runtime image has no shell or package manager.
FROM rust:1-slim-bookworm AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=build /src/target/release/twaqi-api /twaqi-api
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/twaqi-api"]
