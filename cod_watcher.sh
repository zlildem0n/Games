#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - DUAL-PORT + GAME SERVER RANGE GATING (V10.4)
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

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE KERNEL NATIVE CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Filter Armed: sport ($XBOX_1_PORT|$XBOX_2_PORT) --> dport (30000-50000)"
echo "================================================================================"

# Stream unbuffered flows natively from netfilter
conntrack -E -p udp 2>/dev/null | while read -r LINE; do
    # 1. 🚨 EXCLUSIVE SOURCE PORT FILTER GATE: Only process if sport matches your consoles
    if ! echo "$LINE" | grep -qE "sport=($XBOX_1_PORT|$XBOX_2_PORT)"; then
        continue
    fi

    # 2. EXTRACT INTERCEPT PARAMETERS (Isolate both Server IP and Destination Port)
    SERVER_IP=""
    SERVER_PORT=0
    
    for word in $LINE; do
        if echo "$word" | grep -q '^dst='; then
            SERVER_IP=$(echo "$word" | cut -d= -f2)
        fi
        if echo "$word" | grep -q '^dport='; then
            SERVER_PORT=$(echo "$word" | cut -d= -f2)
            break # Once we hit the primary dport field, we have our outbound server targets!
        fi
    done

    [ -z "$SERVER_IP" ] || [ "$SERVER_PORT" -eq 0 ] && continue

    # 3. 🛡️ GAME SERVER DESTINATION PORT RANGE SHIELD
    # Drop instantly if the packet is headed somewhere outside your 30000-50000 game server block
    if [ "$SERVER_PORT" -lt 30000 ] || [ "$SERVER_PORT" -gt 50000 ]; then
        continue
    fi

    # 4. LAN & MULTICAST PROTECTION SHIELD
    if echo "$SERVER_IP" | grep -qE '^(192\.168\.|10\.|172\.|255\.|127\.)'; then
        continue
    fi

    # 5. TOP-GATE DUPLICATE CHECK GATES
    grep -q "^${SERVER_IP}$" "$DUMP_FILE" 2>/dev/null && continue
    grep -q "^${SERVER_IP}$" "$PRE_PENDING_FILE" 2>/dev/null && continue
    grep -q "^${SERVER_IP}$" "$POST_PENDING_FILE" 2>/dev/null && continue
    grep -q "^${SERVER_IP} " "$MASTER_FILE" 2>/dev/null && continue

    # 6. APPROVED PIPELINE REGISTRATION
    echo "$SERVER_IP" >> "$DUMP_FILE"
done
