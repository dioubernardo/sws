#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
    docker stop sws-test >/dev/null 2>&1 || true
}

trap cleanup EXIT

build() {
    echo "==> Building image"
    docker build -t sws "$DIR/../" --no-cache
}

wait_for_server() {
    for i in {1..50}; do
        if curl -fsS "http://127.0.0.1:3000/_health" >/dev/null 2>&1; then
            return 0
        fi

        sleep 0.1
    done

    echo "ERROR: SWS did not become ready"
    docker logs sws-test || true
    return 1
}

start_server() {
    echo
    echo "====================================="
    echo "SWS_SPA_FALLBACK=${SWS_SPA_FALLBACK}"
    echo "SWS_CACHE_POLICY=${SWS_CACHE_POLICY}"
    echo "====================================="

    cleanup

    docker run \
        --rm \
        -d \
        --name sws-test \
        --network host \
        -e "SWS_SPA_FALLBACK=${SWS_SPA_FALLBACK}" \
        -e "SWS_CACHE_POLICY=${SWS_CACHE_POLICY}" \
        -v "${DIR}/fixtures:/www:ro" \
        sws >/dev/null

    wait_for_server
}

check_request_code() {
    local path="$1"
    local expected_code="$2"

    local code

    code=$(curl --path-as-is -sS -o /dev/null -w "%{http_code}" \
        "http://127.0.0.1:3000${path}")

    if [[ "$code" == "$expected_code" ]]; then
        echo "  ✓ ${path} -> ${code}"
        return 0
    fi

    echo "  ✗ ${path} -> expected ${expected_code}, got ${code}"
    return 1
}

check_method() {
    local method="$1"
    local path="$2"
    local expected_code="$3"

    local code

    if [[ "$method" == "HEAD" ]]; then
        code=$(curl -I --path-as-is -sS -o /dev/null -w "%{http_code}" \
            "http://127.0.0.1:3000${path}")
    else
        code=$(curl -X "$method" --path-as-is -sS -o /dev/null -w "%{http_code}" \
            "http://127.0.0.1:3000${path}")
    fi

    if [[ "$code" == "$expected_code" ]]; then
        echo "  ✓ [${method}] ${path} -> ${code}"
        return 0
    fi

    echo "  ✗ [${method}] ${path} -> expected ${expected_code}, got ${code}"
    return 1
}

check_conditional_request() {
    local path="$1"
    local header="$2"

    local headers
    local value
    local code

    headers=$(mktemp)

    # Primeira requisição: obtém o header
    curl -sS -D "$headers" -o /dev/null \
        "http://127.0.0.1:3000${path}"

    value=$(grep -i "^${header}:" "$headers" |
        sed 's/^[^:]*:[[:space:]]*//I' |
        tr -d '\r')

    rm -f "$headers"

    if [[ -z "$value" ]]; then
        echo "  ✗ ${path} -> ${header} header not found"
        return 1
    fi

    # Segunda requisição: envia o mesmo valor
    case "$header" in
        ETag)
            code=$(curl -sS -o /dev/null -w "%{http_code}" \
                -H "If-None-Match: ${value}" \
                "http://127.0.0.1:3000${path}")
            ;;
        Last-Modified)
            code=$(curl -sS -o /dev/null -w "%{http_code}" \
                -H "If-Modified-Since: ${value}" \
                "http://127.0.0.1:3000${path}")
            ;;
        *)
            echo "  ✗ Unsupported conditional header: ${header}"
            return 1
            ;;
    esac

    if [[ "$code" == "304" ]]; then
        echo "  ✓ ${path} -> ${header} -> 304"
        return 0
    fi

    echo "  ✗ ${path} -> ${header} -> expected 304, got ${code}"
    return 1
}

check_cache_control() {
    local path="$1"
    local expected="$2"

    local headers
    local value

    headers=$(mktemp)

    curl -sS -D "$headers" -o /dev/null \
        "http://127.0.0.1:3000${path}"

    value=$(grep -i "^Cache-Control:" "$headers" |
        sed 's/^[^:]*:[[:space:]]*//I' |
        tr -d '\r')

    rm -f "$headers"

    if [[ "$value" == "$expected" ]]; then
        echo "  ✓ ${path} -> Cache-Control: ${value}"
        return 0
    fi

    echo "  ✗ ${path} -> expected Cache-Control: ${expected}, got: ${value}"
    return 1
}

check_content_type() {
    local path="$1"
    local expected="$2"

    local value

    value=$(curl -sS -o /dev/null -w "%{content_type}" \
        "http://127.0.0.1:3000${path}")

    if [[ "$value" == "$expected" || ("$expected" == "application/javascript" && "$value" == "text/javascript") ]]; then
        echo "  ✓ ${path} -> Content-Type: ${value}"
        return 0
    fi

    echo "  ✗ ${path} -> expected Content-Type: ${expected}, got: ${value}"
    return 1
}

check_compression() {
    local path="$1"
    local accept_encoding="$2"
    local expected_encoding="$3"

    local headers
    local encoding_value
    local vary_value

    headers=$(mktemp)

    if [[ -z "$accept_encoding" ]]; then
        curl -sS -D "$headers" -o /dev/null "http://127.0.0.1:3000${path}"
    else
        curl -sS -H "Accept-Encoding: ${accept_encoding}" -D "$headers" -o /dev/null "http://127.0.0.1:3000${path}"
    fi

    encoding_value=$(grep -i "^Content-Encoding:" "$headers" |
        sed 's/^[^:]*:[[:space:]]*//I' |
        tr -d '\r' || echo "")

    vary_value=$(grep -i "^Vary:" "$headers" |
        sed 's/^[^:]*:[[:space:]]*//I' |
        tr -d '\r' || echo "")

    rm -f "$headers"

    # Se esperamos que NÃO haja compressão, o servidor pode não enviar o Vary: Accept-Encoding
    if [[ -z "$expected_encoding" ]]; then
        if [[ -z "$encoding_value" ]]; then
            echo "  ✓ ${path} [${accept_encoding}] -> Correctly not compressed (Content-Encoding is empty)"
            return 0
        else
            echo "  ✗ ${path} [${accept_encoding}] -> expected no compression, got Content-Encoding: '${encoding_value}'"
            return 1
        fi
    fi

    # Validação normal para quando esperamos compressão
    if [[ "$vary_value" != *"Accept-Encoding"* ]]; then
        echo "  ✗ ${path} [${accept_encoding}] -> expected Vary: Accept-Encoding, got: '${vary_value}'"
        return 1
    fi

    if [[ "$encoding_value" == "$expected_encoding" ]]; then
        echo "  ✓ ${path} [${accept_encoding}] -> Content-Encoding: '${encoding_value}' (Vary: ${vary_value})"
        return 0
    fi

    echo "  ✗ ${path} [${accept_encoding}] -> expected Content-Encoding: '${expected_encoding}', got: '${encoding_value}'"
    return 1
}

check_compressed_body() {
    local path="$1"
    local original
    local decompressed

    original=$(curl -sS "http://127.0.0.1:3000${path}")
    decompressed=$(curl --compressed -sS "http://127.0.0.1:3000${path}")

    if [[ "$original" == "$decompressed" ]]; then
        echo "  ✓ ${path} -> body matches after decompression"
        return 0
    fi

    echo "  ✗ ${path} -> body mismatch after decompression"
    return 1
}

build

# Test HTTP CODE
for spa in 0 1; do

    SWS_SPA_FALLBACK=$spa
    SWS_CACHE_POLICY=no-cache
    start_server

    check_request_code "/" 200
    check_request_code "/index.html" 200
    check_request_code "/folder" 301
    check_request_code "/folder/" 200
    check_request_code "/folder-no-index" 301
    check_request_code "/folder-no-index/" 403

    # Valid paths containing .. that resolve inside document_root
    check_request_code "/folder/../index.html" 200
    check_request_code "/folder/../app.css" 200
    check_request_code "/folder/../folder/" 200
    check_request_code "/folder/../folder/index.html" 200

    # Escape document_root attempts (must always return 40x regardless of SWS_SPA_FALLBACK)
    check_request_code "/../" 400
    check_request_code "/../../" 400
    check_request_code "/../Cargo.toml" 400
    check_request_code "/../../etc/passwd" 400
    check_request_code "/folder/../../etc/passwd" 400
    check_request_code "/folder/../.." 400

    if [[ "$spa" == "1" ]]; then
        check_request_code "/missing.txt" 200
    else
        check_request_code "/missing.txt" 404
    fi

done

# Test ETag and Last-Modified headers
SWS_SPA_FALLBACK=0
SWS_CACHE_POLICY=no-cache
start_server

check_conditional_request "/app.css" "ETag"
check_conditional_request "/app.css" "Last-Modified"

# Test Cache-Control header
for policy in max-age immutable no-cache; do

    SWS_SPA_FALLBACK=0
    SWS_CACHE_POLICY=$policy
    start_server

    check_cache_control "/index.html" "no-cache"

    case "$policy" in
        max-age)
            check_cache_control "/app.js" "public, max-age=86400"
            ;;

        immutable)
            check_cache_control "/app.js" "public, max-age=31536000, immutable"
            ;;

        no-cache)
            check_cache_control "/app.js" "no-cache"
            ;;
    esac
done

# Test HTTP Methods (only GET and HEAD are allowed)
SWS_SPA_FALLBACK=0
SWS_CACHE_POLICY=no-cache
start_server

# Allowed methods (HEAD)
check_method "HEAD" "/" 200
check_method "HEAD" "/index.html" 200
check_method "HEAD" "/app.css" 200
check_method "HEAD" "/folder/" 200
check_method "HEAD" "/_health" 200

# Disallowed methods (must return 405 Method Not Allowed)
for method in POST PUT DELETE PATCH OPTIONS; do
    check_method "$method" "/" 405
    check_method "$method" "/index.html" 405
    check_method "$method" "/app.css" 405
    check_method "$method" "/folder/" 405
    check_method "$method" "/_health" 403
done

# Test Content-Type header
SWS_SPA_FALLBACK=0
SWS_CACHE_POLICY=no-cache
start_server

check_content_type "/" "text/html"
check_content_type "/index.html" "text/html"
check_content_type "/app.css" "text/css"
check_content_type "/app.js" "application/javascript"
check_content_type "/logo.png" "image/png"
check_content_type "/file.zip" "application/zip"
check_content_type "/file.bin" "application/octet-stream"
check_content_type "/folder/" "text/html"
check_content_type "/folder/index.html" "text/html"

# Test Content-Type with SPA fallback
SWS_SPA_FALLBACK=1
SWS_CACHE_POLICY=no-cache
start_server

check_content_type "/missing.txt" "text/html"
check_content_type "/folder-no-index" "text/html"
check_content_type "/folder-no-index/" "text/html"

# Test Compression (Brotli and Gzip)
SWS_SPA_FALLBACK=0
SWS_CACHE_POLICY=no-cache
start_server

# Brotli support
check_compression "/index.html" "br" "br"
check_compression "/app.css" "br" "br"
check_compression "/app.js" "br" "br"

# Gzip support
check_compression "/index.html" "gzip" "gzip"
check_compression "/app.css" "gzip" "gzip"
check_compression "/app.js" "gzip" "gzip"

# Preference order: br preferred over gzip
check_compression "/index.html" "gzip, br" "br"
check_compression "/app.css" "gzip, deflate, br" "br"

# Without Accept-Encoding: no Content-Encoding
check_compression "/index.html" "" ""
check_compression "/app.css" "" ""

# Non-compressible files (should NEVER have Content-Encoding)
check_compression "/logo.png" "br, gzip" ""
check_compression "/file.zip" "br, gzip" ""

# Decompressed body validation
check_compressed_body "/index.html"

# Cache test: verify that cached entries retain compression
check_compression "/index.html" "br" "br"
check_compression "/index.html" "gzip" "gzip"
check_compression "/index.html" "" ""

echo "EOF!"