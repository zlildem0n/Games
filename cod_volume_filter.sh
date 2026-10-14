#!/bin/sh
# ==============================================================================
# SCRIPT 4: HEAVY VOLUME FILTER (IMPROVED + DETAILED MASTER LIST)
# ==============================================================================
PENDING_FILE="/root/COD_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
MASTER_FILE="/root/COD_Master.txt"
MMDB_FILE="/usr/share/dpi/geoip/GeoLite2-City.mmdb"
PORTS="49806|49290"
BYTE_THRESHOLD=10000
MAX_WAIT=20

touch "$POST_PENDING_FILE" "$MASTER_FILE" 2>/dev/null

echo "--- LIVE STAGE 4 VOLUME FILTER ONLINE ---"

get_conntrack() {
    if command -v conntrack >/dev/null 2>&1; then
        conntrack -L -p udp --dst "$1" 2>/dev/null | grep -E "sport=($PORTS)|dport=($PORTS)"
    else
        grep -E "udp.*$1" /proc/net/nf_conntrack 2>/dev/null | grep -E "sport=($PORTS)|dport=($PORTS)"
    fi
}

# Helper to get clean location string
get_location() {
    ip="$1"
    if [ ! -f "$MMDB_FILE" ]; then
        echo "Unknown, UNK, XX"
        return
    fi

    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$ip" country iso_code 2>/dev/null \
              | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)
    [ -z "$COUNTRY" ] && COUNTRY="XX"

    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$ip" subdivisions 0 iso_code 2>/dev/null \
             | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)
    [ -z "$REGION" ] && REGION="UNK"

    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$ip" city names en 2>/dev/null \
           | grep -oE '"[^"]+"' | tr -d '"' | head -1)
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$CITY" ] && CITY="Unknown"

    echo "$CITY, $REGION, $COUNTRY"
}

tail -F -n +1 "$PENDING_FILE" 2>/dev/null | while read -r RAW_IP; do
    [ -z "$RAW_IP" ] && continue
    SERVER_IP=$(echo "$RAW_IP" | tr -d '[:space:]\r')
    [ -z "$SERVER_IP" ] && continue

    # Basic IP check
    echo "$SERVER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || continue

    SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')
    grep -q "^${SUBNET_24} " "$POST_PENDING_FILE" 2>/dev/null && continue

    cycle=1
    while [ "$cycle" -le "$MAX_WAIT" ]; do
        RAW_TRACK=$(get_conntrack "$SERVER_IP")
        [ -z "$RAW_TRACK" ] && break

        TOTAL_BYTES=$(echo "$RAW_TRACK" | grep -oE 'bytes=[0-9]+' | cut -d= -f2 | \
                     awk '{s+=$1} END {print s+0}')
        TOTAL_BYTES=${TOTAL_BYTES:-0}

        if [ "$TOTAL_BYTES" -gt "$BYTE_THRESHOLD" ]; then
            # Only write once
            if ! grep -q "^${SUBNET_24} " "$POST_PENDING_FILE" 2>/dev/null; then
                LOCATION=$(get_location "$SERVER_IP")
                TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

                echo "$SUBNET_24" >> "$POST_PENDING_FILE"
                echo "$SUBNET_24 | $LOCATION | Optimal_Zone - passed volume filter (>${BYTE_THRESHOLD}B) @ $TIMESTAMP" >> "$MASTER_FILE"
            fi
            break
        fi

        sleep 1
        cycle=$((cycle + 1))
    done
done
