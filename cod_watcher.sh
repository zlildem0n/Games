#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - TOP-GATE DUPLICATE CHECK FILTRATION (V10.0)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
MASTER_FILE="/root/COD_Master.txt"

# Console Target Profiles
XBOX_1_IP="192.168.1.15"
XBOX_1_PORT="49806"

XBOX_2_IP="192.168.1.6"
XBOX_2_PORT="49290"

# HARDCODED SAFETY SHIELD: Your public WAN IP address locked permanently
MY_WAN_IP="24.229.189.181"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE KERNEL NATIVE CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Tracking ALL events for consoles. Top-Gate Duplicate Shield Armed."
echo "================================================================================"

# ALL-EVENTS NATIVE STREAM
conntrack -E -p udp 2>/dev/null | while read -r LINE; do
    # PHASE 1: FAST PORT GATE CHECK (Must match your consoles)
    if ! echo "$LINE" | grep -qE "sport=($XBOX_1_PORT|$XBOX_2_PORT)|dport=($XBOX_1_PORT|$XBOX_2_PORT)"; then
        continue
    fi

    # PHASE 2: INSTANTLY EXTRACT FIRST EXTERNAL IP CANDIDATE
    CURRENT_SERVER=""
    for word in $LINE; do
        if echo "$word" | grep -qE '^(src|dst)='; then
            ip_candidate=$(echo "$word" | cut -d= -f2)
            
            # Skip LAN subnets, loopbacks, and your hardcoded public WAN IP address
            if [ -n "$ip_candidate" ] && \
               [ "$ip_candidate" != "$XBOX_1_IP" ] && \
               [ "$ip_candidate" != "$XBOX_2_IP" ] && \
               [ "$ip_candidate" != "$MY_WAN_IP" ] && \
               [ "$ip_candidate" != "127.0.0.1" ] && \
               ! echo "$ip_candidate" | grep -qE '^(192\.168\.|10\.|172\.|255\.)'; then
                
                CURRENT_SERVER="$ip_candidate"
                break # First external game server target found
            fi
        fi
    done

    [ -z "$CURRENT_SERVER" ] && continue

    # ==========================================================================
    # 🚨 3. TOP-GATE DUPLICATE CHECK GATES
    # ==========================================================================
    # Drop immediately BEFORE running any more functions if the IP is known anywhere
    grep -q "^${CURRENT_SERVER}$" "$DUMP_FILE" 2>/dev/null && continue
    grep -q "^${CURRENT_SERVER}$" "$PRE_PENDING_FILE" 2>/dev/null && continue
    grep -q "^${CURRENT_SERVER}$" "$POST_PENDING_FILE" 2>/dev/null && continue
    grep -q "^${CURRENT_SERVER} " "$MASTER_FILE" 2>/dev/null && continue

    # ==========================================================================
    # 4. APPROVED PIPELINE REGISTRATION
    # ==========================================================================
    echo "$CURRENT_SERVER" >> "$DUMP_FILE"
done
