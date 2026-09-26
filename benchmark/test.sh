#!/usr/bin/env bash

set -e

cleanup() {
    docker stop sws-test >/dev/null 2>&1 || true
}

trap cleanup EXIT


DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rm -rf /tmp/sws-test
cp -r "${DIR}/../tests/fixtures" /tmp/sws-test

# Arquivo de relatório consolidado de recursos
RESOURCE_LOG="${DIR}/resource_metrics.json"
echo "[" > $RESOURCE_LOG

for SERVER in sws nginx; do

    echo
    echo "Testing: ${SERVER}"

	cleanup

    echo "Starting ${SERVER} container..."
    if [[ "$SERVER" == "sws" ]]; then
        CONTAINER_ID=$(docker run -d --rm \
            --name sws-test \
			--network host \
            -v "/tmp/sws-test:/www:ro" \
            sws)
    else
        CONTAINER_ID=$(docker run -d --rm \
            --name sws-test \
			--network host \
            -v "${DIR}/nginx.conf:/etc/nginx/nginx.conf:ro" \
            -v "/tmp/sws-test:/usr/share/nginx/html:ro" \
            nginx:latest)
    fi

    # Warm-up
    echo "Warm-up..."
    sleep 5
    curl -s -o /dev/null "http://127.0.0.1:3000/"
    sleep 5

    for file in index.html logo.png file.bin; do

        echo
        echo "Test: ${file}"

        echo "  {\"server\": \"${SERVER}\", \"test\": \"${file}\", \"stats\": ["  >> $RESOURCE_LOG

        wrk -t 2 -c 2 -d 15s --latency -H "Accept-Encoding: gzip" "http://127.0.0.1:3000/${file}" &
        WRK_PID=$!

        (
            while true; do
                sleep 1
                echo -n "    " >> $RESOURCE_LOG
                docker stats --no-stream --format '{"cpu":"{{.CPUPerc}}","mem":"{{.MemUsage}}"},' "$CONTAINER_ID" >> "$RESOURCE_LOG"
            done
        ) &
        STATS_PID=$!

        wait $WRK_PID

        kill "$STATS_PID" 2>/dev/null

        echo "  ]}," >> $RESOURCE_LOG
    done

done

echo "]" >> $RESOURCE_LOG