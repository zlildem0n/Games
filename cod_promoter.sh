#!/bin/sh
# ==============================================================================
# SCRIPT 6: HANDSHAKE PROMOTER (STAGE 3 ARCHITECTURE)
# ==============================================================================
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
PENDING_FILE="/root/COD_Pending.txt"

touch "$PENDING_FILE"

echo "--- LIVE STAGE 3 HANDSHAKE PROMOTER ONLINE ---"
tail -f -n +1 "$PRE_PENDING_FILE" | while read -r SERVER_IP; do
    [ -z "$SERVER_IP" ] && continue
    grep -q "^$SERVER_IP" "$PENDING_FILE" 2>/dev/null && continue

    if [ -x "$(command -v conntrack)" ]; then
        RAW_TRACK=$(conntrack -L -p udp --dst "$SERVER_IP" 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
    else
        RAW_TRACK=$(grep -E "udp.*$SERVER_IP" /proc/net/nf_conntrack 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
    fi
    [ -z "$RAW_TRACK" ] && continue

    PKT_COUNT=$(echo "$RAW_TRACK" | grep -oE 'packets=[0-9]+' | cut -d'=' -f2 | head -n1)
    BYTE_COUNT=$(echo "$RAW_TRACK" | grep -oE 'bytes=[0-9]+' | cut -d'=' -f2 | head -n1)
    [ -z "$PKT_COUNT" ] && PKT_COUNT=0
    [ -z "$BYTE_COUNT" ] && BYTE_COUNT=0

    # 12 Packets or 666 Bytes Handshake Gate Lock
    if [ "$PKT_COUNT" -ge 12 ] || [ "$BYTE_COUNT" -ge 666 ]; then
        echo "$SERVER_IP" >> "$PENDING_FILE"
    fi
done
