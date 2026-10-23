#!/bin/sh
set -eu
if [ "${FU_LOCAL_MOBILE:-}" != "1" ]; then
  echo 'This image requires FU_LOCAL_MOBILE=1 and isolated local settings.' >&2
  exit 1
fi
case "${1:-serve}" in
  init)
    mix ecto.create --quiet
    mix ecto.migrate --quiet
    exec mix run -e 'IO.inspect(Fu.Simulation.seed!(), label: "Spontaan Commons ready")'
    ;;
  serve) exec mix phx.server ;;
  *) exec "$@" ;;
esac
