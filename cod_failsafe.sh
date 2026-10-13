#!/bin/sh
# ==============================================================================
# SCRIPT 7: BATCH SWEEPER WITH INSTANT ANY-HOST RESPONSE APPROVAL PASS
# ==============================================================================
PENDING_FILE="/root/COD_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
UNPINGABLE_FILE="/root/COD_Unpingable.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
MMDB_FILE="/root/GeoLite2-City.mmdb"
LATENCY_LIMIT=70
BATCH_SIZE=32

if [ ! -f "$PENDING_FILE" ]; then
    touch "$PENDING_FILE" && chmod 666 "$PENDING_FILE"
fi
touch "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE" && chmod 666 "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE"

echo "--- LIVE INSTANT ANY-HOST RESPONSE SWEEPER ENGINE ---"
echo "[*] Monitoring $PENDING_FILE for new /24 subnets..."
echo "================================================================================"
printf "%-18s | %-12s | %s\n" "/24 TARGET SUBNET" "BEST LATENCY" "VALIDATION STATUS"
echo "--------------------------------------------------------------------------------"

tail -f -n +1 "$PENDING_FILE" | while read -r line; do
    [ -z "$line" ] && continue

    SUBNET_24=$(echo "$line" | awk '{print $1}')
    NET_PREFIX=$(echo "$SUBNET_24" | sed 's/\.0\/24$//')
    [ -z "$NET_PREFIX" ] && continue

    TMP_DIR="/tmp/ping_sweep_$$"
    mkdir -p "$TMP_DIR"

    SUBNET_ALIVE=0
    BEST_MS=""
    TOTAL_RESPONSES=0

    # DEPLOYMENT ENGINE: Loop through all 254 host endpoints via chunked waves
    host_idx=1
    while [ "$host_idx" -le 254 ]; do
        TARGET_IP="${NET_PREFIX}.${host_idx}"
        (
            PING_RES=$(ping -c 1 -W 1 -t 1 "$TARGET_IP" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}' | cut -d. -f1)
            if [ -n "$PING_RES" ]; then
                echo "$PING_RES" > "${TMP_DIR}/${host_idx}.rt"
            fi
        ) &

        # Batch throttling gateway gate
        if [ $((host_idx % BATCH_SIZE)) -eq 0 ]; then
            wait

            # Check files immediately after the batch wave completes
            for res_file in "$TMP_DIR"/*.rt; do
                if [ -f "$res_file" ]; then
                    val=$(cat "$res_file")
                    TOTAL_RESPONSES=$((TOTAL_RESPONSES + 1))
                    if [ -z "$BEST_MS" ] || [ "$val" -lt "$BEST_MS" ]; then
                        BEST_MS="$val"
                    fi
                    # ANY-HOST PROMOTION GATELOCK: If even 1 host is alive, approve the whole subnet block
                    SUBNET_ALIVE=1
                    break 2
                fi
            done
        fi

        host_idx=$((host_idx + 1))
    done
    wait # Catch trailing tasks if no responses occurred in prior batches

    # Final post-sweep fallback check loop (evaluates remaining hosts .225 - .254)
    if [ "$SUBNET_ALIVE" -eq 0 ]; then
        for res_file in "$TMP_DIR"/*.rt; do
            if [ -f "$res_file" ]; then
                val=$(cat "$res_file")
                TOTAL_RESPONSES=$((TOTAL_RESPONSES + 1))
                if [ -z "$BEST_MS" ] || [ "$val" -lt "$BEST_MS" ]; then
                    BEST_MS="$val"
                fi
                SUBNET_ALIVE=1
                break
            fi
        done
    fi
    rm -rf "$TMP_DIR"

    # ==========================================================================
    # STAGE 2: GEOLOCATION CRITERIA & ROUTING MATRIX DEPLOYMENT
    # ==========================================================================
    
    # 🟢 CONDITION A: Instant Subnet Approval Pass (At least one host responded to ping)
    if [ "$SUBNET_ALIVE" -eq 1 ]; then
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "🟢 %-18s | \033[0;32m%3sms\033[0m       | HOST RESPONDED -> SUBNET PROMOTED\n" "$SUBNET_24" "$BEST_MS"
        continue
    fi

    # 👑 STAGE 3 FALLBACK: 254/254 Timeouts Hit. Escalate to Custom MaxMind DB File
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

    # Verify matching home East-Coast/Chicago trusted locations (NJ, NY, PA, IL, VA, OH)
    if [ "$REGION" = "NJ" ] || [ "$REGION" = "NY" ] || [ "$REGION" = "PA" ] || [ "$REGION" = "IL" ] || [ "$REGION" = "VA" ] || [ "$REGION" = "OH" ]; then
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "👑 %-18s | \033[0;35m%-12s\033[0m | TIMEOUT RESCUED -> PASSED (STATE: %s)\n" "$SUBNET_24" "MAXMIND" "$REGION"
    else
        # Subnet is completely unpingable AND physically outside preferred target zones
        if ! grep -q "^$SUBNET_24" "$UNPINGABLE_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [TIMEOUT] Firewalled Node" >> "$UNPINGABLE_FILE"
        fi
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [TIMEOUT BANNED] Firewalled and outside target region (State: ${REGION:-UNK})" >> "$BLOCKED_FILE"
        fi
        printf "❌ %-18s | \033[0;31m%-12s\033[0m | TIMEOUT REJECTED -> BLOCKED (STATE: %s)\n" "$SUBNET_24" "TIMEOUT" "${REGION:-UNK}"
    fi
done
