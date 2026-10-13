#!/bin/sh
# ==============================================================================
# SCRIPT 7: GEOGRAPHIC-FIRST MAXMIND FILTER & BATCH ICMP PIPELINE (BETA 2.0)
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

echo "--- LIVE GEOGRAPHIC-FIRST MAXMIND ROUTING ENGINE ---"
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
    # STAGE 1: GEOGRAPHIC PRE-FILTER (MAXMIND FIRST)
    # ==========================================================================
    TEST_IP="${NET_PREFIX}.1"
    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"')
    [ -z "$REGION" ] && REGION="UNK"

    # MULTI-CONSOLE MATCH ZONE: Expanded profile list includes GA (Georgia / Atlanta)
    if [ "$REGION" != "NJ" ] && [ "$REGION" != "NY" ] && [ "$REGION" != "PA" ] && [ "$REGION" != "IL" ] && [ "$REGION" != "VA" ] && [ "$REGION" != "OH" ] && [ "$REGION" != "GA" ]; then
        # ❌ REJECTED: Server is physically located far away. Block it instantly without pinging!
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [Distant Region Banned] Located in state ($REGION)" >> "$BLOCKED_FILE"
        fi
        printf "❌ %-18s | \033[0;31m%-12s\033[0m | DISTANT REGION INTERCEPTED -> BLOCKED\n" "$SUBNET_24" "STATE: $REGION"
        continue
    fi

    # ==========================================================================
    # STAGE 2: BATCH SWEEPER (ONLY RUNS FOR TRUSTED REGIONAL SERVERS)
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
    # STAGE 3: FINAL ROUTING ALLOCATION FOR LOCAL POOLS
    # ==========================================================================
    if [ "$SUBNET_ALIVE" -eq 1 ]; then
        # 🟢 LOCAL AND RESPONSIVE: Passed to Optimal pool
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "🟢 %-18s | \033[0;32m%-12s\033[0m | LOCAL RESPONSIVE PROMOTED (PING: %sms)\n" "$SUBNET_24" "STATE: $REGION" "$BEST_MS"
    else
        # ⚠️ LOCAL AND FIREWALLED: Trusted region but blocks ping packets. Save it to unpingable!
        if ! grep -q "^$SUBNET_24" "$UNPINGABLE_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [Local Trusted Firewalled] Located in state ($REGION)" >> "$UNPINGABLE_FILE"
        fi
        # ALSO save to Post_Pending so your firewall allows it to be used in matchmaking!
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "👑 %-18s | \033[0;35m%-12s\033[0m | LOCAL TRUSTED FIREWALLED RESCUED -> PASSED\n" "$SUBNET_24" "STATE: $REGION"
    fi
done
