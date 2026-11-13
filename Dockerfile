########################################################################
# Versions & Images
########################################################################

# renovate: datasource=github-tags depName=elixir packageName=elixir-lang/elixir versioning=semver
ARG ELIXIR_VERSION=1.20.5
# renovate: datasource=github-tags depName=erlang packageName=erlang/otp versioning=regex:^(?<major>\d+?)\.(?<minor>\d+?)(\.(?<patch>\d+))?$ extractVersion=^OTP-(?<version>\S+)
ARG OTP_VERSION=29.1.2
# renovate: datasource=docker depName=ubuntu packageName=ubuntu versioning=ubuntu
ARG UBUNTU_VERSION=resolute-20261024.1
# renovate: datasource=node-version depName=node versioning=node
ARG NODE_VERSION=26.13.0
# renovate: datasource=github-tags depName=bun packageName=oven-sh/bun versioning=semver extractVersion=^bun-v(?<version>\S+)
ARG BUN_VERSION=1.4.4

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${UBUNTU_VERSION}"
ARG RUNTIME_IMAGE="ubuntu:${UBUNTU_VERSION}"

########################################################################
# Stage: base
########################################################################

FROM ${BUILDER_IMAGE} AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NODE_VERSION
ARG BUN_VERSION

ENV MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    APP_HOME=/opt/app \
    ERL_AFLAGS="-kernel shell_history enabled"

WORKDIR $APP_HOME

# The stage is also the development container (compose.yml), so it keeps the recommended packages, e.g. openssh-client
# and less for git.
# hadolint ignore=DL3015
RUN apt-get update -y \
    && apt-get install -y build-essential curl git gnupg inotify-tools libatomic1 unzip watchman \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Node.js and bun are verified like in the official node and oven/bun images: the download must match the GPG-signed
# SHASUMS256.txt of the release, and only the listed keys may sign it. Node.js release keys:
# https://github.com/nodejs/node#release-keys. bun uses the x64-baseline build on amd64 like oven/bun, so it also runs
# on CPUs without AVX2. set -e does not apply inside the key loop, so a key missing on both keyservers exits explicitly. The
# positional parameters collect the --assert-signer options.
# The downloads go to a temporary directory that the same RUN removes.
# hadolint ignore=DL3003
RUN set -ex \
    && case "$(dpkg --print-architecture)" in \
         amd64) NODE_ARCH=x64 BUN_ARCH=x64-baseline ;; \
         arm64) NODE_ARCH=arm64 BUN_ARCH=aarch64 ;; \
         *) echo "unsupported architecture" >&2; exit 1 ;; \
       esac \
    && WORK="$(mktemp -d)" && cd "$WORK" \
    && GNUPGHOME="$(mktemp -d)" && export GNUPGHOME \
    && set -- \
    && for key in \
         5BE8A3F6C8A5C01D106C0AD820B1A390B168D356 \
         DD792F5973C6DE52C432CBDAC77ABFA00DDBF2B7 \
         CC68F5A3106FF448322E48ED27F5E38D5B0A215F \
         890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
         C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
         108F52B48DB57BB0CC439B2997B01419BD92F80A \
         655F3B5C1FB3FA8D1A0CA6BDE4A7D232B936D2FD \
         A363A499291CBBC940DD62E41F10027AF002F8B0 \
       ; do \
         { gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" && gpg --batch --fingerprint "$key"; } \
         || { gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" && gpg --batch --fingerprint "$key"; } \
         || { echo "key $key not found" >&2; exit 1; }; \
         set -- "$@" --assert-signer "$key"; \
       done \
    && curl -fsSLO --compressed --retry 5 "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
    && curl -fsSLO --compressed --retry 5 "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt.asc" \
    && gpg --batch "$@" --verify --output SHASUMS256.verified.txt SHASUMS256.txt.asc \
    && grep " node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz\$" SHASUMS256.verified.txt | sha256sum -c - \
    && tar -xJf "node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
    && gpgconf --kill all && rm -rf "$GNUPGHOME" "${WORK:?}"/* \
    && GNUPGHOME="$(mktemp -d)" && export GNUPGHOME \
    && printf '%s\n' \
         '-----BEGIN PGP PUBLIC KEY BLOCK-----' \
         '' \
         'mDMEY9GQFhYJKwYBBAHaRw8BAQdAkppAqaXl0RkROz6NfdvlwYd2UuUVfHLk2NNY' \
         'IzEdnT+0GVJvYm9idW4gPHJvYm9idW5Ab3Zlbi5zaD6IkwQTFgoAOxYhBPPcwIqF' \
         'csB0mz4YiI6rTUCnsitZBQJj0ZAWAhsDBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4H' \
         'AheAAAoJEI6rTUCnsitZ96UBAMvwCLD6Ud1RZkpvvnGUU+idHt2hcNmYU2d0XxDI' \
         'HQ0rAQCA9VFOtjZefQkfhDzgIgnEEdSFXaMiyY+D+LP8awNMCrg4BGPRkBYSCisG' \
         'AQQBl1UBBQEBB0BpfePYSOEx8PihYkNXjlK5YT89CGHjEK5etleaB9i6OwMBCAeI' \
         'eAQYFgoAIBYhBPPcwIqFcsB0mz4YiI6rTUCnsitZBQJj0ZAWAhsMAAoJEI6rTUCn' \
         'sitZvhAA/j4SQxOCLheRG86A2181WAP4qLS1qxSw+fCf28DgiPfbAQCL0kcel+M9' \
         'qbRIlMnwn6TwlQgN9w1qqlSnA9CbKXT9Aw==' \
         '=dGV6' \
         '-----END PGP PUBLIC KEY BLOCK-----' \
       | gpg --batch --import \
    && curl -fsSLO --compressed --retry 5 "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${BUN_ARCH}.zip" \
    && curl -fsSLO --compressed --retry 5 "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/SHASUMS256.txt.asc" \
    && gpg --batch --assert-signer F3DCC08A8572C0749B3E18888EAB4D40A7B22B59 \
         --verify --output SHASUMS256.verified.txt SHASUMS256.txt.asc \
    && grep " bun-linux-${BUN_ARCH}.zip\$" SHASUMS256.verified.txt | sha256sum -c - \
    && unzip -q "bun-linux-${BUN_ARCH}.zip" \
    && install -m 0755 "bun-linux-${BUN_ARCH}/bun" /usr/local/bin/bun \
    && gpgconf --kill all && cd / && rm -rf "$GNUPGHOME" "$WORK" \
    && node --version && npm --version && bun --version

COPY .docker/opt/scripts/ /opt/scripts
RUN chmod -R +x /opt/scripts/
ENV PATH=/opt/scripts/:/opt/app/_build/prod/rel/demo/bin:$PATH

ARG MIX_ENV=prod
ENV MIX_ENV=$MIX_ENV

# Install root-level (Backpex) dependencies
COPY package.json bun.lock bunfig.toml ./
RUN bun install --frozen-lockfile --production

WORKDIR $APP_HOME/demo

COPY mix.exs mix.lock .formatter.exs ../

COPY demo/mix.exs demo/mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY demo/config/config.exs demo/config/${MIX_ENV}.exs config/
# Backpex is compiled together with the demo, so changes to Backpex do not invalidate the compiled deps
RUN mix deps.compile --skip-local-deps

COPY demo/package.json demo/bun.lock demo/bunfig.toml demo/.stylelintrc.json ./

COPY assets ../assets/
COPY package.json ../

RUN bun install --frozen-lockfile

COPY lib ../lib/
COPY demo/priv priv/
COPY demo/assets assets/
COPY demo/lib lib/

RUN mix compile && mix assets.deploy

########################################################################
# Stage: builder
########################################################################

FROM base AS builder

# Copy the rest of the application files
COPY . ../

ENTRYPOINT ["entrypoint.sh"]
CMD ["mix", "phx.server"]
EXPOSE 4000

########################################################################
# Stage: release
########################################################################

FROM base AS release

ENV MIX_ENV=prod

COPY demo/config/runtime.exs config/
COPY demo/rel rel/

# Compile and create the release. ShellCheck mistakes the mix task `do` for the shell keyword.
# hadolint ignore=SC1010
RUN mix do deps.get + deps.compile + sentry.package_source_code + release --overwrite

########################################################################
# Stage: runtime
########################################################################

FROM ${RUNTIME_IMAGE} AS runtime

ENV APP_HOME=/opt/app
WORKDIR $APP_HOME

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=base /opt/scripts /opt/scripts

# Only the app directory belongs to nobody, so the release cannot modify the entrypoint scripts.
RUN chown -R nobody $APP_HOME

ENV PATH=/opt/scripts/:/opt/app/bin:$PATH \
    MIX_ENV=prod

COPY --from=release --chown=nobody /opt/app/demo/_build/${MIX_ENV}/rel/demo .

# nobody:nogroup, numeric so that a runtime can check that the user is not root (e.g. runAsNonRoot in Kubernetes)
USER 65534:65534

ENTRYPOINT ["entrypoint.sh"]
CMD ["bash", "-c", "demo start"]
EXPOSE 4000
