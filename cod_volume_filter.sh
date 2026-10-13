#!/bin/sh
# ==============================================================================
# SCRIPT 4: UNBUFFERED HEAVY VOLUME FILTER ENGINE (STAGE 4 ARCHITECTURE)
# ==============================================================================
PENDING_FILE="/root/COD_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
MASTER_FILE="/root/COD_Master.txt"
BYTE_THRESHOLD=10000

touch "$POST_PENDING_FILE" "$MASTER_FILE"

echo "--- LIVE STAGE 4 UNBUFFERED HEAVY VOLUME FILTER ENGINE ONLINE ---"

# FIXED: Added 'awk' flush rule to instantly push lines down the pipe without buffering lag
tail -f -n +1 "$PENDING_FILE" | awk '{print $0; fflush()}' | while read -r RAW_IP; do
    [ -z "$RAW_IP" ] && continue
    
    # Clean hidden whitespace artifacts off the IP address string instantly
    SERVER_IP=$(echo "$RAW_IP" | tr -d '[:space:]' | tr -d '\r')
    [ -z "$SERVER_IP" ] && continue
    
    SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')
    grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null && continue

    # FIXED: Check the traffic counter multiple times over a 15-second span 
    # to catch the match data as it climbs toward 10K bytes!
    check_cycle=1
    while [ "$check_cycle" -le 15 ]; do
        if [ -x "$(command -v conntrack)" ]; then
            RAW_TRACK=$(conntrack -L -p udp --dst "$SERVER_IP" 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
        else
            RAW_TRACK=$(grep -E "udp.*$SERVER_IP" /proc/net/nf_conntrack 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
        fi
        
        [ -z "$RAW_TRACK" ] && break # Exit if the lobby closed or disconnected

        TOTAL_BYTES=$(echo "$RAW_TRACK" | grep -oE 'bytes=[0-9]+' | cut -d'=' -f2 | awk '{sum+=$1} END {print sum}')
        [ -z "$TOTAL_BYTES" ] && TOTAL_BYTES=0

        # 10,000+ Bytes Active Match Flow Gate Lock Passed!
        if [ "$TOTAL_BYTES" -gt "$BYTE_THRESHOLD" ]; then
            if ! grep -q "^$SUBNET_24" "$POST_PENDING_FILE" 2>/dev/null; then
                echo "$SUBNET_24" >> "$POST_PENDING_FILE"
                echo "$SUBNET_24 #Optimal_Zone" >> "$MASTER_FILE"
            fi
            break
        fi
        
        sleep 1
        check_cycle=$((check_cycle + 1))
    done
done
