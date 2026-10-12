#!/bin/sh
# ==============================================================================
# SCRIPT 6: ACTIVE PIPELINE DATA PROMOTER (CONNTRACK METRICS -> /24 CONVERTER)
# ==============================================================================
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
PENDING_FILE="/root/COD_Pending.txt"
XBOX_PORT="49806"
BYTE_THRESHOLD=10000

if [ ! -f "$PRE_PENDING_FILE" ]; then
    touch "$PRE_PENDING_FILE" && chmod 666 "$PRE_PENDING_FILE"
fi
touch "$PENDING_FILE" && chmod 666 "$PENDING_FILE"

echo "--- LIVE NETFILTER CONNTRACK VOLUME PROMOTER ENGINE ---"
echo "[*] Monitoring $PRE_PENDING_FILE for high-volume streams (>10KB)..."
echo "================================================================================"
printf "%-16s | %-12s | %-12s | %s\n" "SERVER IP" "VOLUME (BYTES)" "STATE FLAG" "PROMOTION /24 SUBNET"
echo "--------------------------------------------------------------------------------"

# Stream incoming verified IPs from the verifier's file in real-time
tail -f -n +1 "$PRE_PENDING_FILE" | while read -r line; do
    [ -z "$line" ] && continue

    SERVER_IP=$(echo "$line" | awk '{print $1}')

    # Query conntrack specifically for total byte accounting metrics
    if [ -x "$(command -v conntrack)" ]; then
        RAW_TRACK=$(conntrack -L -p udp --dst "$SERVER_IP" 2>/dev/null | grep -E "sport=$XBOX_PORT|dport=$XBOX_PORT")
    else
        RAW_TRACK=$(grep -E "udp.*$SERVER_IP" /proc/net/nf_conntrack 2>/dev/null | grep -E "sport=$XBOX_PORT|dport=$XBOX_PORT")
    fi

    # Drop processing if the active state session dropped out early
    [ -z "$RAW_TRACK" ] && continue

    # CRITERIA 1: Verify the session contains the kernel [ASSURED] network state flag
    if ! echo "$RAW_TRACK" | grep -q "ASSURED"; then
        continue
    fi

    # CRITERIA 2: Parse out total transmitted bytes from the state table row
    TOTAL_BYTES=$(echo "$RAW_TRACK" | grep -oE 'bytes=[0-9]+' | cut -d'=' -f2 | awk '{sum+=$1} END {print sum}')

    if [ -z "$TOTAL_BYTES" ]; then
        TOTAL_BYTES=0
    fi

    # Check if the aggregate match data flow clears your strict 10,000-byte limit
    if [ "$TOTAL_BYTES" -gt "$BYTE_THRESHOLD" ]; then
        
        # STRUCTURAL /24 RANGE CONVERSION
        # Cuts off the last octet and appends .0/24 (e.g., 185.34.107.42 -> 185.34.107.0/24)
        SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')
        
        # Flash storage protection check before promoting to the Pending ledger
        if ! grep -q "^$SUBNET_24" "$PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$PENDING_FILE"
            
            # Print success line with the converted /24 subnet highlighted
            printf "🚀 %-16s | %-12s | \033[0;36m%-12s\033[0m | Converted: \033[0;32m%s\033[0m\n" \
                "$SERVER_IP" "$TOTAL_BYTES" "[ASSURED]" "$SUBNET_24"
        fi
    fi
done
