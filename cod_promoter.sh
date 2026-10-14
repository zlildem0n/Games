#!/bin/sh
# ==============================================================================
# SCRIPT 3: HANDSHAKE PROMOTER (IMPROVED)
# ==============================================================================
PRE_PENDING_FILE="/root/COD_dump.txt"
PENDING_FILE="/root/COD_Pending.txt"
PORTS="49806|49290"
MIN_PACKETS=12
MIN_BYTES=666
MAX_WAIT=8

touch "$PENDING_FILE" 2>/dev/null

echo "--- LIVE STAGE 3 HANDSHAKE PROMOTER ONLINE ---"

get_conntrack() {
    if command -v conntrack >/dev/null 2>&1; then
        conntrack -L -p udp --dst "$1" 2>/dev/null | grep -E "sport=($PORTS)|dport=($PORTS)"
    else
        grep -E "udp.*$1" /proc/net/nf_conntrack 2>/dev/null | grep -E "sport=($PORTS)|dport=($PORTS)"
    fi
}

tail -F -n +1 "$dump.txt" 2>/dev/null | while read -r RAW_IP; do
    [ -z "$RAW_IP" ] && continue
    SERVER_IP=$(echo "$RAW_IP" | tr -d '[:space:]\r')
    [ -z "$SERVER_IP" ] && continue

    grep -q "^${SERVER_IP}$" "$PENDING_FILE" 2>/dev/null && continue

    loop=1
    while [ "$loop" -le "$MAX_WAIT" ]; do
        RAW_TRACK=$(get_conntrack "$SERVER_IP")
        [ -z "$RAW_TRACK" ] && break

        PKT_COUNT=$(echo "$RAW_TRACK" | grep -oE 'packets=[0-9]+' | cut -d= -f2 | head -1)
        BYTE_COUNT=$(echo "$RAW_TRACK" | grep -oE 'bytes=[0-9]+' | cut -d= -f2 | head -1)
        PKT_COUNT=${PKT_COUNT:-0}
        BYTE_COUNT=${BYTE_COUNT:-0}

        if [ "$PKT_COUNT" -ge "$MIN_PACKETS" ] || [ "$BYTE_COUNT" -ge "$MIN_BYTES" ]; then
            if ! grep -q "^${SERVER_IP}$" "$PENDING_FILE" 2>/dev/null; then
                echo "$SERVER_IP" >> "$PENDING_FILE"
            fi
            break
        fi

        sleep 1
        loop=$((loop + 1))
    done
done
