# syntax=docker/dockerfile:1
# check=error=true

# Production image. JavaScript tooling exists only in the build stage; the
# runtime image contains Ruby, the compiled Vite assets, and system libraries.
ARG RUBY_VERSION=3.3.11
ARG NODE_VERSION=22

FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS node

FROM docker.io/library/ruby:${RUBY_VERSION}-slim-bookworm AS base
WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    gem install bundler -v 4.0.16 --no-document && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Copy Node and npm from the official image instead of installing them in the
# final runtime image.
COPY --from=node /usr/local/ /usr/local/

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .

RUN chmod +x bin/* && \
    bundle exec bootsnap precompile -j 1 app/ lib/ && \
    DATABASE_URL=postgresql://localhost/app_build \
      SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules tmp/cache

FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80

# The image defaults to the web process. Run `bin/jobs` as a separate worker,
# or set SOLID_QUEUE_IN_PUMA=true for a single-instance prototype deployment.
CMD ["./bin/thrust", "./bin/rails", "server"]
