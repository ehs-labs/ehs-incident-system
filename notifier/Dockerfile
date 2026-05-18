# syntax=docker/dockerfile:1.7

# =============================================================================
# notifier Dockerfile — Sinatra app with Karafka consumers + Falcon WS server
# =============================================================================

FROM ruby:3.4.1-slim AS build

# Gemfile.lock is committed; BUNDLE_DEPLOYMENT=1 enforces the lockfile and
# fails loud if it is out of sync with the Gemfile.
ENV BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential curl git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

# Shared local-path gem (outside this service's context) — exposed by the
# compose / buildx `shared-envelope` named build context.
COPY --from=shared-envelope . /shared/envelope

# Avro schemas — Karafka deserializer reads them at /schemas/events/v1/.
COPY --from=schemas . /schemas/events/v1

WORKDIR /app

# Trailing * makes Gemfile.lock optional until committed.
COPY Gemfile* ./

RUN bundle install && \
    rm -rf "${BUNDLE_PATH}/ruby/*/cache"

COPY . .

# ---------- Final stage ------------------------------------------------------
FROM ruby:3.4.1-slim AS final

ENV BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RACK_ENV="production"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libpq5 tini && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 1001 ruby && \
    useradd --uid 1001 --gid 1001 --create-home --shell /bin/bash ruby

WORKDIR /app
COPY --from=build --chown=ruby:ruby /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=ruby:ruby /shared /shared
COPY --from=build --chown=ruby:ruby /schemas /schemas
COPY --from=build --chown=ruby:ruby /app /app

USER ruby:ruby

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:4000/healthz || exit 1

ENTRYPOINT ["tini", "--"]
CMD ["bundle", "exec", "falcon", "serve", "--bind", "http://0.0.0.0:4000"]
