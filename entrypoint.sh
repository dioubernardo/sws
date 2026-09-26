#!/bin/sh

if [ "$SWS_SPA_FALLBACK" = "0" ]; then
    export SPA_TRY_FILES="=404"
else
    export SPA_TRY_FILES="/index.html"
fi

case "$SWS_CACHE_POLICY" in
    immutable)
        export CACHE_CONTROL_HEADER="public, max-age=31536000, immutable"
        ;;
    no-cache)
        export CACHE_CONTROL_HEADER="no-cache"
        ;;
    max-age | *)
        export CACHE_CONTROL_HEADER="public, max-age=${SWS_MAX_AGE}"
        ;;
esac

envsubst '$SPA_TRY_FILES,$CACHE_CONTROL_HEADER'< /app/nginx.conf.template > /app/nginx.conf

exec "$@"