FROM elixir:1.15.7

WORKDIR /var/www/frog
ADD mix* ./
RUN mix do local.hex --force, local.rebar --force
RUN mix deps.get --only prod
ADD config config
RUN MIX_ENV=prod mix deps.compile
ADD assets assets
RUN MIX_ENV=prod mix assets.deploy
ADD lib lib
RUN MIX_ENV=prod mix compile
ENTRYPOINT MIX_ENV=prod mix phx.server
