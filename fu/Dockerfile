# Verified hexpm Elixir/OTP and Debian image tags; keep their ABI aligned.
FROM hexpm/elixir:1.19.6-erlang-28.5.0.8-debian-bookworm-20261020-slim@sha256:112e516e642218af182ee3d2e84ba6a02d92056fa8e6f0772ab6013d9e5a6cf4 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod --check-locked
COPY config/config.exs config/prod.exs config/
COPY scripts/fetch-tailwind.sh scripts/
RUN mix deps.compile && sh scripts/fetch-tailwind.sh && mix assets.setup
COPY priv priv
COPY lib lib
RUN mix compile --warnings-as-errors
COPY assets assets
RUN mix assets.deploy
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM debian:bookworm-20261020-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8 AS runner
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates && rm -rf /var/lib/apt/lists/*
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 MIX_ENV=prod
WORKDIR /app
RUN chown nobody /app
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/fu ./
USER nobody
EXPOSE 8080
CMD ["/app/bin/server"]
