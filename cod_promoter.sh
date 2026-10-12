#!/bin/sh
# ==============================================================================
# SCRIPT 6: ACTIVE PIPELINE DATA PROMOTER (DUAL XBOX METRIC ENGINE)
# ==============================================================================
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
PENDING_FILE="/root/COD_Pending.txt"
BYTE_THRESHOLD=10000

if [ ! -f "$PRE_PENDING_FILE" ]; then
    touch "$PRE_PENDING_FILE" && chmod 666 "$PRE_PENDING_FILE"
fi
touch "$PENDING_FILE" && chmod 666 "$PENDING_FILE"

echo "--- LIVE NETFILTER CONNTRACK VOLUME PROMOTER ENGINE ---"
echo "[*] Monitoring $PRE_PENDING_FILE for dual-console streams..."
echo "================================================================================"
printf "%-16s | %-12s | %-12s | %s\n" "SERVER IP" "VOLUME (BYTES)" "STATE FLAG" "PROMOTION /24 SUBNET"
echo "--------------------------------------------------------------------------------"

tail -f -n +1 "$PRE_PENDING_FILE" | while read -r line; do
    [ -z "$line" ] && continue

    SERVER_IP=$(echo "$line" | awk '{print $1}')

    # MULTI-CONSOLE EXPANSION: Scan conntrack tables using an OR pipe matching either port footprint
    if [ -x "$(command -v conntrack)" ]; then
        RAW_TRACK=$(conntrack -L -p udp --dst "$SERVER_IP" 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
    else
        RAW_TRACK=$(grep -E "udp.*$SERVER_IP" /proc/net/nf_conntrack 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
    fi

    [ -z "$RAW_TRACK" ] && continue

    if ! echo "$RAW_TRACK" | grep -q "ASSURED"; then
        continue
    fi

    TOTAL_BYTES=$(echo "$RAW_TRACK" | grep -oE 'bytes=[0-9]+' | cut -d'=' -f2 | awk '{sum+=$1} END {print sum}')
    [ -z "$TOTAL_BYTES" ] && TOTAL_BYTES=0

    if [ "$TOTAL_BYTES" -gt "$BYTE_THRESHOLD" ]; then
        SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')
        
        if ! grep -q "^$SUBNET_24" "$PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$PENDING_FILE"
            printf "🚀 %-16s | %-12s | \033[0;36m%-12s\033[0m | Converted: \033[0;32m%s\033[0m\n" \
                "$SERVER_IP" "$TOTAL_BYTES" "[ASSURED]" "$SUBNET_24"
        fi
    fi
done
