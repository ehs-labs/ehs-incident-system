# syntax=docker/dockerfile:1.7

# =============================================================================
# core-api Dockerfile — Rails 7.2 API-only
# Multi-stage; final image runs as non-root.
# =============================================================================

# ---------- Build stage ------------------------------------------------------
FROM ruby:3.3.0-slim AS build

ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV="production"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      curl \
      git \
      libpq-dev \
      libyaml-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems (cached layer)
COPY Gemfile Gemfile.lock ./
COPY ../shared/envelope /shared/envelope

RUN bundle install && \
    rm -rf "${BUNDLE_PATH}/ruby/*/cache" && \
    find "${BUNDLE_PATH}" -name "*.o" -delete

COPY . .

# Precompile bootsnap cache
RUN bundle exec bootsnap precompile --gemfile app/ lib/

# ---------- Final stage ------------------------------------------------------
FROM ruby:3.3.0-slim AS final

ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV="production" \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="false"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libpq5 \
      libjemalloc2 \
      tini && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 1001 ruby && \
    useradd --uid 1001 --gid 1001 --create-home --shell /bin/bash ruby

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

WORKDIR /app
COPY --from=build --chown=ruby:ruby /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=ruby:ruby /shared /shared
COPY --from=build --chown=ruby:ruby /app /app

USER ruby:ruby

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS http://localhost:3000/healthz || exit 1

ENTRYPOINT ["tini", "--"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
