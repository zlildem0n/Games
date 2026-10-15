#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - ALL-EVENTS + EXPANDED DUPLICATE GUARD (V9.8)
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

# HARDCODED SAFETY SHIELD: Your exact public WAN IP address locked permanently
MY_WAN_IP="24.229.189.181"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE KERNEL NATIVE CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Tracking ALL events for consoles. Multi-Queue Duplicate Guard Armed."
echo "================================================================================"

# ALL-EVENTS NATIVE STREAM
conntrack -E -p udp 2>/dev/null | while read -r LINE; do
    # 1. Quick confirmation gate: check if line text belongs to your console target port streams
    if echo "$LINE" | grep -qE "sport=($XBOX_1_PORT|$XBOX_2_PORT)|dport=($XBOX_1_PORT|$XBOX_2_PORT)"; then
        
        # 2. Extract every IP parameter block on the line using clean string splitting rules
        SERVER_IP=""
        for word in $LINE; do
            if echo "$word" | grep -qE '^(src|dst)='; then
                current_ip=$(echo "$word" | cut -d= -f2)
                
                # IRONCLAD SHIELD GATES: Instantly filter out LAN subnets, loopbacks, and your WAN IP
                if [ -n "$current_ip" ] && \
                   [ "$current_ip" != "$XBOX_1_IP" ] && \
                   [ "$current_ip" != "$XBOX_2_IP" ] && \
                   [ "$current_ip" != "$MY_WAN_IP" ] && \
                   [ "$current_ip" != "127.0.0.1" ] && \
                   ! echo "$current_ip" | grep -qE '^(192\.168\.|10\.|172\.|255\.)'; then
                    
                    SERVER_IP="$current_ip"
                    break # Target isolated successfully
                fi
            fi
        done
        
        # 3. 🚨 EXPANDED MULTI-FILE DUPLICATE SHIELD LAYER
        # Before printing, check ALL active pipeline queues including Stage 4 and Stage 5
        if [ -n "$SERVER_IP" ]; then
            if ! grep -q "^${SERVER_IP}$" "$DUMP_FILE" 2>/dev/null && \
               ! grep -q "^${SERVER_IP}$" "$PRE_PENDING_FILE" 2>/dev/null && \
               ! grep -q "^${SERVER_IP}$" "$POST_PENDING_FILE" 2>/dev/null && \
               ! grep -q "^${SERVER_IP} " "$MASTER_FILE" 2>/dev/null; then
                
                echo "$SERVER_IP" >> "$DUMP_FILE"
            fi
        fi
    fi
done
