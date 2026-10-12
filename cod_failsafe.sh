#!/bin/sh
# ==============================================================================
# SCRIPT 7: PARALLEL SWEEPER WITH CLEAN REGIONAL AND TIMEOUT ISOLATION ROUTING
# ==============================================================================
PENDING_FILE="/root/COD_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
UNPINGABLE_FILE="/root/COD_Unpingable.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
MMDB_FILE="/root/GeoLite2-City.mmdb"
LATENCY_LIMIT=70

if [ ! -f "$PENDING_FILE" ]; then
    touch "$PENDING_FILE" && chmod 666 "$PENDING_FILE"
fi
touch "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE" && chmod 666 "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE"

echo "--- LIVE PARALLEL ICMP SUBNET SWEEPER & MAXMIND ENGINE ---"
echo "[*] Monitoring $PENDING_FILE for new /24 subnets..."
echo "================================================================================"
printf "%-18s | %-12s | %s\n" "/24 TARGET SUBNET" "BEST LATENCY" "VALIDATION STATUS"
echo "--------------------------------------------------------------------------------"

# Stream newly promoted /24 subnets in real time
tail -f -n +1 "$PENDING_FILE" | while read -r line; do
    [ -z "$line" ] && continue

    SUBNET_24=$(echo "$line" | awk '{print $1}')
    
    # Strip trailing notation to isolate the subnet prefix
    NET_PREFIX=$(echo "$SUBNET_24" | sed 's/\.0\/24$//')
    [ -z "$NET_PREFIX" ] && continue

    # Secure scratchpad location inside volatile RAM
    TMP_DIR="/tmp/ping_sweep_$$"
    mkdir -p "$TMP_DIR"

    # Stage a high-speed parallel sweep of all 254 host addresses (.1 to .254)
    host_idx=1
    while [ "$host_idx" -le 254 ]; do
        TARGET_IP="${NET_PREFIX}.${host_idx}"
        (
            PING_RES=$(ping -c 1 -W 1 -t 1 "$TARGET_IP" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}' | cut -d. -f1)
            if [ -n "$PING_RES" ]; then
                echo "$PING_RES" > "${TMP_DIR}/${host_idx}.rt"
            fi
        ) &
        host_idx=$((host_idx + 1))
    done

    wait

    # Parse metrics out of the scratchpad workers
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

    rm -rf "$TMP_DIR"

    # Evaluate latency constraints
    PASSED_LATENCY=0
    if [ "$TOTAL_RESPONSES" -gt 0 ] && [ -n "$BEST_MS" ] && [ "$BEST_MS" -lt "$LATENCY_LIMIT" ]; then
        PASSED_LATENCY=1
    fi

    # 🟢 CONDITION A: Low Latency Verified (<70ms)
    if [ "$PASSED_LATENCY" -eq 1 ]; then
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "🟢 %-18s | \033[0;32m%3sms\033[0m       | PASSED TO POST_PENDING\n" "$SUBNET_24" "$BEST_MS"
        continue
    fi

    # 👑 GEOGRAPHIC OVERRIDE LAYER: Query Offline MaxMind DB
    TEST_IP="${NET_PREFIX}.1"
    REGION=$(python3 -c "
import sys
try:
    import geoip2.database
    with geoip2.database.Reader('$MMDB_FILE') as reader:
        print(reader.city('$TEST_IP').subdivisions.most_specific.iso_code)
except:
    print('UNKNOWN')
" 2>/dev/null | tr -d '\r\n')

    if [ "$REGION" = "UNKNOWN" ] || [ -z "$REGION" ]; then
        if [ -x "$(command -v mmdblookup)" ]; then
            REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"')
        fi
    fi

    # Pass the server if it matches your home East-Coast/Chicago gaming zones
    if [ "$REGION" = "NJ" ] || [ "$REGION" = "NY" ] || [ "$REGION" = "PA" ] || [ "$REGION" = "IL" ]; then
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        METRIC_STR="${BEST_MS:-TIMEOUT}ms"
        printf "👑 %-18s | \033[0;35m%-12s\033[0m | MAXMIND EXEMPTION OVERRIDE (%s)\n" "$SUBNET_24" "STATE: $REGION" "$METRIC_STR"
        continue
    fi

    # ❌ COLD ISOLATION LOGGING: Outside target region
    if [ "$TOTAL_RESPONSES" -eq 0 ]; then
        # ⚠️ PATH B: True Timeout -> Sent exclusively to firewalled/dead file
        if ! grep -q "^$SUBNET_24" "$UNPINGABLE_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [TIMEOUT] Firewalled or Dead Node (Region: ${REGION:-UNK})" >> "$UNPINGABLE_FILE"
        fi
        printf "⚠️  %-18s | %-12s | LOGGED TO UNPINGABLE.TXT (TIMEOUT)\n" "$SUBNET_24" "TIMEOUT"
    else
        # ❌ PATH C: True High Ping -> Sent exclusively to blocked file
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [HIGH PING] Latency registered (${BEST_MS}ms) (Region: ${REGION:-UNK})" >> "$BLOCKED_FILE"
        fi
        printf "❌ %-18s | \033[0;31m%3sms\033[0m       | HIGH LATENCY TO BLOCKED.TXT\n" "$SUBNET_24" "$BEST_MS"
    fi
done
