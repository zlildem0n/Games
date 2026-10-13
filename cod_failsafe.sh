#!/bin/sh
# ==============================================================================
# SCRIPT 7: BATCH SWEEPER WITH LIVE HISTORICAL MAXMIND RESCUE MECHANISM (BETA 1.9)
# ==============================================================================
PENDING_FILE="/root/COD_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
UNPINGABLE_FILE="/root/COD_Unpingable.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
MMDB_FILE="/root/GeoLite2-City.mmdb"
LATENCY_LIMIT=70
BATCH_SIZE=32

touch "$POST_PENDING_FILE" "$UNPINGABLE_FILE" "$BLOCKED_FILE"

echo "================================================================================"
echo "      🛡️  INITIALIZING HISTORICAL LOG SCAN & REGIONAL MAXMIND RESCUE"
echo "================================================================================"

# --- THE GEOGRAPHIC RESCUE LOOP ---
# This looks inside your blocked and unpingable logs, finds allowed states, and moves them to post pending
for log_source in "$BLOCKED_FILE" "$UNPINGABLE_FILE"; do
    [ ! -s "$log_source" ] && continue
    
    _tmp_log="/tmp/rescue_scan_$$"
    cp "$log_source" "$_tmp_log"
    
    while read -r line; do
        [ -z "$line" ] && continue
        
        # Isolate just the clean IP subnet block (xxx.xxx.xxx.0/24), ignoring notes/comments
        SUBNET_24=$(echo "$line" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.0/24')
        [ -z "$SUBNET_24" ] && continue
        
        # Establish lookable test IP address format
        NET_PREFIX=$(echo "$SUBNET_24" | sed 's/\.0\/24$//')
        TEST_IP="${NET_PREFIX}.1"
        
        # Interrogate your gateway's custom local MaxMind database
        REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"')
        [ -z "$REGION" ] && REGION="UNK"
        
        # The Target Allowed States Validation Check
        if [ "$REGION" = "NJ" ] || [ "$REGION" = "NY" ] || [ "$REGION" = "PA" ] || [ "$REGION" = "IL" ] || [ "$REGION" = "VA" ] || [ "$REGION" = "OH" ]; then
            # 👑 RESCUE OPERATION: Promote the server and clean it out of the old file
            if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
                echo "$SUBNET_24" >> "$POST_PENDING_FILE"
            fi
            sed -i "\|^$SUBNET_24|d" "$log_source" 2>/dev/null
            echo "👑 [RESCUED] Moving $SUBNET_24 from $(basename $log_source) to Optimal (State: $REGION)"
        fi
    done < "$_tmp_log"
    rm -f "$_tmp_log"
done

echo "================================================================================"
echo "--- LIVE INSTANT ANY-HOST RESPONSE SWEEPER ENGINE ---"
echo "[*] Monitoring $PENDING_FILE for new /24 subnets..."
echo "================================================================================"

# --- THE CONTINUOUS MULTI-STAGE MATCHMAKING STREAM LOOP ---
tail -f -n +1 "$PENDING_FILE" | while read -r line; do
    [ -z "$line" ] && continue

    SUBNET_24=$(echo "$line" | awk '{print $1}')
    NET_PREFIX=$(echo "$SUBNET_24" | sed 's/\.0\/24$//')
    [ -z "$NET_PREFIX" ] && continue

    TMP_DIR="/tmp/ping_sweep_$$"
    mkdir -p "$TMP_DIR"

    SUBNET_ALIVE=0; BEST_MS=""; TOTAL_RESPONSES=0

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
                    TOTAL_RESPONSES=$((TOTAL_RESPONSES + 1))
                    if [ -z "$BEST_MS" ] || [ "$val" -lt "$BEST_MS" ]; then BEST_MS="$val"; fi
                    SUBNET_ALIVE=1; break 2
                fi
            done
        fi
        host_idx=$((host_idx + 1))
    done
    wait

    if [ "$SUBNET_ALIVE" -eq 0 ]; then
        for res_file in "$TMP_DIR"/*.rt; do
            if [ -f "$res_file" ]; then
                val=$(cat "$res_file")
                TOTAL_RESPONSES=$((TOTAL_RESPONSES + 1))
                if [ -z "$BEST_MS" ] || [ "$val" -lt "$BEST_MS" ]; then BEST_MS="$val"; fi
                SUBNET_ALIVE=1; break
            fi
        done
    fi
    rm -rf "$TMP_DIR"

    if [ "$SUBNET_ALIVE" -eq 1 ]; then
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "🟢 %-18s | \033[0;32m%3sms\033[0m       | HOST RESPONDED -> SUBNET PROMOTED\n" "$SUBNET_24" "$BEST_MS"
        continue
    fi

    TEST_IP="${NET_PREFIX}.1"
    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"')
    [ -z "$REGION" ] && REGION="UNK"

    if [ "$REGION" = "NJ" ] || [ "$REGION" = "NY" ] || [ "$REGION" = "PA" ] || [ "$REGION" = "IL" ] || [ "$REGION" = "VA" ] || [ "$REGION" = "OH" ]; then
        if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
            echo "$SUBNET_24" >> "$POST_PENDING_FILE"
        fi
        printf "👑 %-18s | \033[0;35m%-12s\033[0m | TIMEOUT RESCUED -> PASSED (STATE: %s)\n" "$SUBNET_24" "MAXMIND" "$REGION"
    else
        if ! grep -q "^$SUBNET_24" "$UNPINGABLE_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [TIMEOUT] Firewalled Node" >> "$UNPINGABLE_FILE"
        fi
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [TIMEOUT BANNED] Firewalled and outside target region (State: ${REGION:-UNK})" >> "$BLOCKED_FILE"
        fi
        printf "❌ %-18s | \033[0;31m%-12s\033[0m | TIMEOUT REJECTED -> BLOCKED (STATE: %s)\n" "$SUBNET_24" "TIMEOUT" "${REGION:-UNK}"
    fi
done
