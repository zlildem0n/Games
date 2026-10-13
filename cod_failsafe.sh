#!/bin/sh
# ==============================================================================
# SCRIPT 7: COUNTRY-FIRST / COMMENT-INSENSITIVE CONFIG LIST ENGINE (BETA 2.6.0)
# ==============================================================================
PENDING_FILE="/root/COD_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
UNPINGABLE_FILE="/root/COD_Unpingable.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
CONFIG_LIST="/root/COD_States"
MMDB_FILE="/root/GeoLite2-City.mmdb"
LATENCY_LIMIT=70
BATCH_SIZE=32

if [ ! -f "$PENDING_FILE" ]; then
    touch "$PENDING_FILE" && chmod 666 "$PENDING_FILE"
fi
touch "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE" && chmod 666 "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE"

echo "--- LIVE COUNTRY-FIRST COMMENT-INSENSITIVE ENGINE ---"
echo "[*] Monitoring $PENDING_FILE for new /24 subnets..."
echo "================================================================================"
printf "%-18s | %-12s | %s\n" "/24 TARGET SUBNET" "ZONE REGION" "VALIDATION STATUS"
echo "--------------------------------------------------------------------------------"

tail -f -n +1 "$PENDING_FILE" | while read -r line; do
    [ -z "$line" ] && continue

    SUBNET_24=$(echo "$line" | awk '{print $1}')
    NET_PREFIX=$(echo "$SUBNET_24" | sed 's/\.0\/24$//')
    [ -z "$NET_PREFIX" ] && continue

    # ==========================================================================
    # STAGE 1: GEOGRAPHIC PRE-FILTER (COUNTRY, REGION, AND CITY MAPPING)
    # ==========================================================================
    TEST_IP="${NET_PREFIX}.1"
    
    # 1. Extract country code (Highly stable)
    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" country iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | tr -d '[:space:]')
    [ -z "$COUNTRY" ] && COUNTRY="US"

    # Foreign Filter: If it's not a US server, block it immediately
    if [ "$COUNTRY" != "US" ]; then
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [Foreign Banned] Located in ($COUNTRY)" >> "$BLOCKED_FILE"
        fi
        printf "❌ %-18s | \033[0;31m%-12s\033[0m | FOREIGN SERVER INTERCEPTED -> BLOCKED\n" "$SUBNET_24" "COUNTRY: $COUNTRY"
        continue
    fi

    # 2. Extract state region subdivision
    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | tr -d '[:space:]')
    [ -z "$REGION" ] && REGION="UNK"

    # 3. Extract City Profile for advanced verification
    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" city names en 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"')
    # Clean up outer padding but preserve inner spacing for multi-word cities (like New York City)
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$CITY" ] && CITY="UnknownCity"

    # INTELLIGENT LIST VERIFICATION RULE: Strips inline comments and trims spacing live in memory
    IS_ALLOWED=0
    if [ -f "$CONFIG_LIST" ]; then
        # Clean the list on the fly: Remove comments, strip trailing whitespace, ignore blank lines
        CLEANED_LIST=$(sed 's/#.*//' "$CONFIG_LIST" | sed 's/[[:space:]]*$//' | grep -v '^$')
        
        if echo "$CLEANED_LIST" | grep -qi "^$CITY$"; then
            IS_ALLOWED=1
            [ "$REGION" = "UNK" ] && REGION="MAPPED"
        elif echo "$CLEANED_LIST" | grep -qi "^$REGION$"; then
            IS_ALLOWED=1
        elif [ "$REGION" = "UNK" ] && [ "$CITY" = "UnknownCity" ]; then
            # Fallback protection for true blank profiles to let pings verify them
            IS_ALLOWED=1
        fi
    else
        # Fail-safe protection if list goes missing locally
        IS_ALLOWED=1
    fi

    if [ "$IS_ALLOWED" -eq 0 ]; then
        # ❌ EXPLICIT REJECT: Outside your custom allowed settings list
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [Distant Zone Banned] Located in ($CITY, $REGION)" >> "$BLOCKED_FILE"
        fi
        printf "❌ %-18s | \033[0;31m%-12s\033[0m | GEOGRAPHIC PROFILE EXCLUDED -> BLOCKED\n" "$SUBNET_24" "$CITY ($REGION)"
        continue
    fi

    # ==========================================================================
    # STAGE 2: BATCH SWEEPER (ONLY RUNS FOR VERIFIED ALLOWED ZONES)
    # ==========================================================================
    TMP_DIR="/tmp/ping_sweep_$$"
    mkdir -p "$TMP_DIR"
    SUBNET_ALIVE=0
    BEST_MS=""

    host_idx=1
    while [ "$host_idx" -le 254 ]; do
        TARGET_IP="${NET_PREFIX}.${host_idx}"
        (
            PING_RES=$(ping -c 1 -W 1 -t 1 "$TARGET_IP" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}' | cut -d. -f1)
            if [ -n "$PING_RES" ]; then
                echo "$PING_RES" > "${TMP_DIR}/${host_idx}.rt"
            fi
        ) &

        if [ $((host_idx % BATCH_SIZE)) -eq 0 ]; then
            wait
            for res_file in "$TMP_DIR"/*.rt; do
                if [ -f "$res_file" ]; then
                    val=$(cat "$res_file")
                    if [ -z "$BEST_MS" ] || [ "$val" -lt "$BEST_MS" ]; then BEST_MS="$val"; fi
                    SUBNET_ALIVE=1
                    break 2
                fi
            done
        fi
        host_idx=$((host_idx + 1))
    done
    wait

    # Fallback sweep catch (.225 - .254)
    if [ "$SUBNET_ALIVE" -eq 0 ]; then
        for res_file in "$TMP_DIR"/*.rt; do
            if [ -f "$res_file" ]; then
                val=$(cat "$res_file")
                if [ -z "$BEST_MS" ] || [ "$val" -lt "$BEST_MS" ]; then BEST_MS="$val"; fi
                SUBNET_ALIVE=1
                break
            fi
        done
    fi
    rm -rf "$TMP_DIR"

    # ==========================================================================
    # STAGE 3: FINAL ROUTING ALLOCATION BASED ON PERFORMANCE METRICS
    # ==========================================================================
    if [ "$SUBNET_ALIVE" -eq 1 ]; then
        if [ "$BEST_MS" -lt "$LATENCY_LIMIT" ]; then
            if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
                echo "$SUBNET_24" >> "$POST_PENDING_FILE"
            fi
            printf "🟢 %-18s | \033[0;32m%-12s\033[0m | OPTIMAL LOCAL SERVER PASSED (PING: %sms)\n" "$SUBNET_24" "$CITY" "$BEST_MS"
        else
            if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
                echo "$SUBNET_24 | Note: [High Latency Filtered] Ping registered (${BEST_MS}ms) Zone: ($CITY)" >> "$BLOCKED_FILE"
            fi
            printf "❌ %-18s | \033[0;31m%-12s\033[0m | HIGH LATENCY POOL DROPPED -> BLOCKED\n" "$SUBNET_24" "${BEST_MS}ms"
        fi
    else
        if ! grep -q "^$SUBNET_24" "$UNPINGABLE_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [Local Trusted Firewalled] Complete Timeout (Zone: $CITY)" >> "$UNPINGABLE_FILE"
        fi
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "👑 %-18s | \033[0;35m%-12s\033[0m | LOCAL TRUSTED FIREWALLED RESCUED -> PASSED\n" "$SUBNET_24" "$CITY"
    fi
done
