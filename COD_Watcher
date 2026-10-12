#!/bin/sh
# ==============================================================================
# SCRIPT 1: STUN-TRIGGERED ENGINE - INTERFACE WAN CONTEXT WATCHER
# ==============================================================================
XBOX_PORT="49806"
DUMP_FILE="/root/COD_Dump.txt"
MASTER_FILE="/root/COD_Master.txt"
OFFICIAL_FILE="/root/COD_Official_Allowed.txt"
WAN_IP="24.229.189.181"          # Your public/WAN IP
IFACE="eth4"                     # WAN edge interface

touch "$DUMP_FILE" "$MASTER_FILE" "$OFFICIAL_FILE" 2>/dev/null
chmod 666 "$DUMP_FILE" "$OFFICIAL_FILE" 2>/dev/null

echo "[*] COD Sniper Active. Monitoring WAN edge interface $IFACE smoothly..."

# BPF Filter Breakdown:
# 1. Must be UDP and involve your Xbox Port (49806).
# 2. MATCH IF: It uses standard ports 3074 or 3544.
# 3. MATCH IF: It uses ports 30000-50000 AND matches the exact 16 or 214 byte lengths.
BPF_FILTER="udp and port $XBOX_PORT and ( \
    port 3074 or port 3544 or \
    ( \
        ((udp[2:2] >= 30000 and udp[2:2] <= 50000) or (udp[0:2] >= 30000 and udp[0:2] <= 50000)) and \
        (udp[11:2] == 16 or udp[11:2] == 214) \
    ) \
)"

while true; do
    # Force line-buffered mode (-l) to output clean matches instantly
    tcpdump -l -npi "$IFACE" "$BPF_FILTER" 2>/dev/null | while read -r line; do

        # Extract out the ports involved to check for official routing
        SRC_PORT=$(echo "$line" | awk '{print $3}' | grep -oE '[0-9]+$')
        DST_PORT=$(echo "$line" | awk '{print $5}' | tr -d ':' | grep -oE '[0-9]+$')

        # Structurally parse out the source IP and destination IP
        # Strips trailing port numbers cleanly
        SRC_IP=$(echo "$line" | awk '{print $3}' | sed 's/\.[0-9]*$//')
        DST_IP=$(echo "$line" | awk '{print $5}' | sed 's/\.[0-9]*$//' | tr -d ':')

        SERVER_IP=""

        # Evaluate packet directionality relative to your edge WAN IP
        if [ "$SRC_IP" = "$WAN_IP" ]; then
            SERVER_IP="$DST_IP"
            TARGET_PORT="$DST_PORT"
        elif [ "$DST_IP" = "$WAN_IP" ]; then
            SERVER_IP="$SRC_IP"
            TARGET_PORT="$SRC_PORT"
        fi

        # Safety catch for empty / invalid / loopback addresses
        if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" = "0.0.0.0" ] || [ "$SERVER_IP" = "127.0.0.1" ]; then
            continue
        fi

        # ROUTING CRITERIA: Check if the traffic hit an official port
        if [ "$TARGET_PORT" = "3074" ] || [ "$TARGET_PORT" = "3544" ]; then
            if ! grep -q "^$SERVER_IP" "$OFFICIAL_FILE" 2>/dev/null; then
                echo "$SERVER_IP" >> "$OFFICIAL_FILE"
            fi
        else
            # Otherwise, it falls in the 30k-50k block. Send to the verifier's dump file.
            if ! grep -q "^$SERVER_IP" "$MASTER_FILE" 2>/dev/null; then
                echo "$SERVER_IP" >> "$DUMP_FILE"
            fi
        fi
    done

    # If tcpdump exits for any reason, wait briefly and restart
    sleep 2
done
