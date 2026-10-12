#!/bin/sh
# ==============================================================================
# SCRIPT 7: PARALLEL SUBNET SWEEPER & THREE-WAY LATENCY ROUTING ROUTINE
# ==============================================================================
PENDING_FILE="/root/COD_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
UNPINGABLE_FILE="/root/COD_Unpingable.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
LATENCY_LIMIT=70

if [ ! -f "$PENDING_FILE" ]; then
    touch "$PENDING_FILE" && chmod 666 "$PENDING_FILE"
fi
touch "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE" && chmod 666 "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE"

echo "--- LIVE PARALLEL ICMP SUBNET SWEEPER ENGINE ---"
echo "[*] Monitoring $PENDING_FILE for new /24 subnets..."
echo "================================================================================"
printf "%-18s | %-12s | %s\n" "/24 TARGET SUBNET" "BEST LATENCY" "VALIDATION STATUS"
echo "--------------------------------------------------------------------------------"

# Stream newly promoted /24 subnets in real time
tail -n 0 -f "$PENDING_FILE" | while read -r line; do
    [ -z "$line" ] && continue

    SUBNET_24=$(echo "$line" | awk '{print $1}')
    
    # Strip the trailing '.0/24' to get the network prefix (e.g., 185.34.107)
    NET_PREFIX=$(echo "$SUBNET_24" | sed 's/\.0\/24$//')
    
    # Verify the prefix is syntactically valid before dropping into the sweep loop
    [ -z "$NET_PREFIX" ] && continue

    # Create a temporary secure directory inside ramfs/tmp to hold parallel worker outputs
    TMP_DIR="/tmp/ping_sweep_$$"
    mkdir -p "$TMP_DIR"

    # Stage a high-speed parallel sweep of all 254 host addresses (.1 to .254)
    host_idx=1
    while [ "$host_idx" -le 254 ]; do
        TARGET_IP="${NET_PREFIX}.${host_idx}"
        
        (
            # Send 1 aggressive ICMP packet with a strict 200ms timeout window
            PING_RES=$(ping -c 1 -W 1 -t 1 "$TARGET_IP" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}' | cut -d. -f1)
            
            if [ -n "$PING_RES" ]; then
                echo "$PING_RES" > "${TMP_DIR}/${host_idx}.rt"
            fi
        ) &
        
        host_idx=$((host_idx + 1))
    done

    # Block script execution until all background workers finish their sweeps
    wait

    # Parse through the collected worker files to discover the lowest response metric
    BEST_MS=""
    TOTAL_RESPONSES=0
    for res_file in "$TMP_DIR"/*.rt; do
        if [ -f "$res_file" ]; then
            val=$(cat "$res_file")
            TOTAL_RESPONSES=$((TOTAL_RESPONSES + 1))
            if [ -z "$BEST_MS" ] || [ "$val" -lt "$BEST_MS" ]; then
                BEST_MS="$val"
            fi
        fi
    done

    # Safely clear the memory-backed worker files
    rm -rf "$TMP_DIR"

    # THREE-WAY ROUTING CRITERIA Evaluation
    if [ "$TOTAL_RESPONSES" -eq 0 ]; then
        # PATH A: The entire subnet is completely unpingable
        if ! grep -q "^$SUBNET_24" "$UNPINGABLE_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$UNPINGABLE_FILE"
        fi
        printf "⚠️  %-18s | %-12s | \033[0;33mLOGGED TO UNPINGABLE.TXT\033[0m\n" \
            "$SUBNET_24" "TIMEOUT"

    elif [ -n "$BEST_MS" ] && [ "$BEST_MS" -lt "$LATENCY_LIMIT" ]; then
        # PATH B: At least one host is responsive and under your 70ms ceiling
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "🟢 %-18s | \033[0;32m%3sms\033[0m       | PASSED TO POST_PENDING\n" \
            "$SUBNET_24" "$BEST_MS"

    else
        # PATH C: Active hosts were found, but their ping time is above 70ms
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$BLOCKED_FILE"
        fi
        printf "❌ %-18s | \033[0;31m%3sms\033[0m       | HIGH LATENCY -> BLOCKED.TXT\n" \
            "$SUBNET_24" "$BEST_MS"
    fi
done
