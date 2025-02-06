########################################################################
# Versions & Images
########################################################################

# renovate: datasource=github-tags depName=elixir packageName=elixir-lang/elixir versioning=semver
ARG ELIXIR_VERSION=1.18.2
# renovate: datasource=github-tags depName=erlang packageName=erlang/otp versioning=regex:^(?<major>\d+?)\.(?<minor>\d+?)(\.(?<patch>\d+))?$ extractVersion=^OTP-(?<version>\S+)
ARG OTP_VERSION=27.2.1
# renovate: datasource=docker depName=ubuntu packageName=ubuntu versioning=ubuntu
ARG UBUNTU_VERSION=noble-20241015

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${UBUNTU_VERSION}"
ARG RUNTIME_IMAGE="ubuntu:${UBUNTU_VERSION}"

########################################################################
# Stage: builder
########################################################################

FROM ${BUILDER_IMAGE} AS builder

ENV MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    APP_HOME=/opt/app \
    ERL_AFLAGS="-kernel shell_history enabled"

WORKDIR $APP_HOME

RUN apt-get update -y \
    && apt-get install -y build-essential curl git inotify-tools \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && npm install --global yarn

COPY .docker/opt/scripts/ /opt/scripts
ADD https://github.com/naymspace/env-secrets-expand/raw/main/env-secrets-expand.sh /opt/scripts/
RUN chmod -R +x /opt/scripts/
ENV PATH=/opt/scripts/:/opt/app/_build/prod/rel/demo/bin:$PATH

ARG MIX_ENV=prod
ENV MIX_ENV=$MIX_ENV

RUN mkdir demo
WORKDIR $APP_HOME/demo

COPY lib ../lib/
COPY mix.exs mix.lock .formatter.exs ../

COPY demo/mix.exs demo/mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY demo/config/config.exs demo/config/${MIX_ENV}.exs config/
RUN mix do deps.compile

COPY demo/priv priv/

COPY demo/package.json demo/yarn.lock demo/.stylelintrc.json ./
RUN yarn install --pure-lockfile
COPY demo/assets assets/
COPY demo/lib lib/
COPY assets ../assets/
COPY package.json ../
RUN mix assets.deploy

# Copy the rest of the application files
COPY . ../

ENTRYPOINT ["entrypoint.sh"]
CMD ["mix", "phx.server"]
EXPOSE 4000

########################################################################
# Stage: release
########################################################################

FROM builder AS release

ENV MIX_ENV=prod

# Compile and create the release
RUN mix do deps.get, deps.compile, assets.deploy, sentry.package_source_code, release --overwrite

########################################################################
# Stage: runtime
########################################################################

FROM ${RUNTIME_IMAGE} AS runtime

ENV APP_HOME=/opt/app
WORKDIR $APP_HOME

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates wget \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

COPY --from=builder /opt/scripts /opt/scripts

RUN chown -R nobody /opt

ENV PATH=/opt/scripts/:/opt/app/bin:$PATH \
    MIX_ENV=prod

COPY --from=release --chown=nobody /opt/app/demo/_build/${MIX_ENV}/rel/demo .

USER nobody

ENTRYPOINT ["entrypoint.sh"]
CMD ["bash", "-c", "demo start"]
EXPOSE 4000
