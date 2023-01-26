FROM elixir:1.14.3

WORKDIR /var/www/frog
ADD mix* ./
ADD test test
ADD config config
ADD lib lib
ADD asserts assets
RUN mix do local.hex --force, local.rebar --force
RUN mix deps.get
RUN mix compile
ENTRYPOINT mix phx.server
