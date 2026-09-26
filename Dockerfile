# Fase 1: Build
FROM debian:trixie-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpcre2-dev \
    zlib1g-dev \
    libbrotli-dev \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG NGINX_VERSION=1.31.6

# Utilizar o ADD para descarregar e extrair o NGINX automaticamente
ADD https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz /tmp/nginx.tar.gz
RUN tar -zxvf /tmp/nginx.tar.gz -C / && rm /tmp/nginx.tar.gz

# Clonar o módulo ngx_brotli
RUN git clone --recurse-submodules https://github.com/google/ngx_brotli.git /ngx_brotli

WORKDIR /nginx-${NGINX_VERSION}
RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/app/nginx.conf \
    --error-log-path=/dev/stderr \
    --http-log-path=/dev/stdout \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --without-http_proxy_module \
    --without-http_fastcgi_module \
    --without-http_uwsgi_module \
    --without-http_scgi_module \
    --without-http_grpc_module \
    --without-http_limit_req_module \
    --without-http_limit_conn_module \
    --without-http_auth_basic_module \
    --without-http_autoindex_module \
    --without-http_geo_module \
    --without-http_split_clients_module \
    --without-http_referer_module \
    --without-http_upstream_hash_module \
    --without-http_upstream_ip_hash_module \
    --without-http_upstream_least_conn_module \
    --without-http_upstream_random_module \
    --without-http_upstream_keepalive_module \
    --without-http_upstream_zone_module \
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module \
    --with-file-aio \
    --with-threads \
    --add-module=/ngx_brotli \
    && make -j$(nproc) \
    && make install

# Fase 2: Runtime
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcre2-8-0 \
    zlib1g \
    libbrotli1 \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mkdir -p /var/cache/nginx /www

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx

# @TODO: rever
COPY --from=builder /etc/nginx /etc/nginx

COPY nginx.conf.template /app/nginx.conf.template
COPY mime.types /app/mime.types
COPY --chmod=+x entrypoint.sh /app/entrypoint.sh

EXPOSE 3000

ENV SWS_MAX_AGE=86400
ENV SWS_CACHE_POLICY=max-age
ENV SWS_SPA_FALLBACK=0

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["nginx", "-c", "/app/nginx.conf", "-g", "daemon off;"]