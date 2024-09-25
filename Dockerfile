########################################################################
# Stage: builder
########################################################################

FROM hexpm/elixir:1.17.3-erlang-27.1-alpine-3.20.3@sha256:3ff1231940202c670487c11de2a818835bae2bbbf862215fb5e4accb05653a6a as builder

ENV MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    APP_HOME=/opt/app \
    ERL_AFLAGS="-kernel shell_history enabled"

WORKDIR $APP_HOME

RUN apk --no-cache --update upgrade \
    && apk add --no-cache bash ca-certificates libstdc++ build-base git inotify-tools nodejs npm yarn \
    && update-ca-certificates --fresh \
    && mix do local.hex --force, local.rebar --force

SHELL ["/bin/bash", "-c"]

COPY .docker/etc /etc/
RUN find /etc/bashrc.d/ -name "*.sh" -exec chmod -v +x {} \;
COPY .docker/root/.bashrc /root/
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
RUN mix assets.deploy

# Copy the rest of the application files
COPY . ../

ENTRYPOINT ["entrypoint.sh"]
CMD ["mix", "phx.server"]
EXPOSE 4000

########################################################################
# Stage: release
########################################################################

FROM builder as release

ENV MIX_ENV=prod

# Compile and create the release
RUN mix do deps.get, deps.compile, assets.deploy, sentry.package_source_code, release --overwrite

########################################################################
# Stage: runtime
########################################################################

FROM alpine:3.20.3@sha256:a8f120106f5549715aa966fd7cefaf3b7045f6414fed428684de62fec8c2ca4b as runtime

ENV APP_HOME=/opt/app
WORKDIR $APP_HOME

RUN apk --no-cache --update upgrade \
    && apk add --no-cache bash ca-certificates libstdc++ openssl ncurses-libs \
    && update-ca-certificates --fresh

SHELL ["/bin/bash", "-c"]

COPY --from=builder /etc/bashrc.d /etc/bashrc.d
COPY --from=builder /etc/bash.bashrc /etc/bash.bashrc
COPY --from=builder /opt/scripts /opt/scripts
COPY .docker/root/.bashrc /root/

RUN chown -R nobody:nobody /opt

ENV PATH=/opt/scripts/:/opt/app/bin:$PATH \
    MIX_ENV=prod

COPY --from=release --chown=nobody:nobody /opt/app/demo/_build/${MIX_ENV}/rel/demo .

USER nobody:nobody

ENTRYPOINT ["entrypoint.sh"]
CMD ["bash", "-c", "demo start"]
EXPOSE 4000
