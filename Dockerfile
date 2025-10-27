FROM node:20.11.0-alpine AS node
FROM ruby:3.4.7-alpine AS base
FROM base AS builder

ENV RAILS_ENV production
ENV NODE_ENV production

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

RUN apk add --no-cache tzdata libpq-dev build-base gcompat yaml-dev

WORKDIR /app

COPY Gemfile* /app/

RUN bundle config --local without 'development test' \
  && bundle install -j4 --retry 3 \
  && bundle exec bootsnap precompile -j 0 --gemfile app/ lib/  \
  && bundle clean --force \
  && rm -rf /usr/local/bundle/cache \
  && find /usr/local/bundle/gems/ -name "*.c" -delete \
  && find /usr/local/bundle/gems/ -name "*.o" -delete

COPY . /app

RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile \
  && npm cache clean --force \
  && rm -rf node_modules tmp/cache/* /tmp/* package-lock.json log/production.log app/javascript/* app/assets/* storage/*


FROM base

ARG COMMIT_HASH

ENV LANG=C.UTF-8 RAILS_ENV=production WEB_CONCURRENCY=auto COMMIT_HASH=$COMMIT_HASH

LABEL service="blackcandy"

RUN apk add --no-cache \
  tzdata \
  libpq \
  vips \
  ffmpeg \
  curl \
  gcompat \
  jemalloc

WORKDIR /app

EXPOSE 80

# Enable jemalloc for reduced memory usage and latency
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2

RUN addgroup -g 1000 -S app && adduser -u 1000 -S app -G app

COPY --from=tianon/gosu /gosu /usr/local/bin/
COPY --from=builder --chown=app:app /usr/local/bundle/ /usr/local/bundle/
COPY --from=builder --chown=app:app /app/ /app/

# Forwards media listener logs to stdout so they can be captured in docker logs.
RUN ln -sf /dev/stdout /app/log/media_listener_production.log \
  && find /app/tmp -type d -exec chmod 1777 '{}' +

ENTRYPOINT ["./bin/docker-entrypoint"]

CMD ["./bin/thrust", "./bin/rails", "server"]
