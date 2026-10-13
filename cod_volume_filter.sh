#!/bin/sh
# ==============================================================================
# SCRIPT 4: HEAVY VOLUME FILTER ENGINE (STAGE 4 ARCHITECTURE)
# ==============================================================================
PENDING_FILE="/root/COD_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
MASTER_FILE="/root/COD_Master.txt"
BYTE_THRESHOLD=10000

touch "$POST_PENDING_FILE" "$MASTER_FILE"

echo "--- LIVE STAGE 4 HEAVY VOLUME FILTER ENGINE ONLINE ---"
tail -f -n +1 "$PENDING_FILE" | while read -r SERVER_IP; do
    [ -z "$SERVER_IP" ] && continue
    SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')
    grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null && continue

    if [ -x "$(command -v conntrack)" ]; then
        RAW_TRACK=$(conntrack -L -p udp --dst "$SERVER_IP" 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
    else
        RAW_TRACK=$(grep -E "udp.*$SERVER_IP" /proc/net/nf_conntrack 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
    fi
    [ -z "$RAW_TRACK" ] && continue

    TOTAL_BYTES=$(echo "$RAW_TRACK" | grep -oE 'bytes=[0-9]+' | cut -d'=' -f2 | awk '{sum+=$1} END {print sum}')
    [ -z "$TOTAL_BYTES" ] && TOTAL_BYTES=0

    # 10,000+ Bytes Active Match Flow Gate Lock
    if [ "$TOTAL_BYTES" -gt "$BYTE_THRESHOLD" ]; then
        echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        if ! grep -q "^$SUBNET_24" "$MASTER_FILE" 2>/dev/null; then
            echo "$SUBNET_24 #Optimal_Zone" >> "$MASTER_FILE"
        fi
    fi
done
