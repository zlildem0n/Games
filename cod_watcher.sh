#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - ALL-EVENTS NATIVE RUNTIME (STAGE 1 - V9.0)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"

# Console Target Profiles
XBOX_1_IP="192.168.1.15"
XBOX_1_PORT="49806"

XBOX_2_IP="192.168.1.6"
XBOX_2_PORT="49290"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE KERNEL NATIVE CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Tracking ALL events for consoles: $XBOX_1_IP & $XBOX_2_IP"
echo "================================================================================"

# ALL-EVENTS NATIVE STREAM: Removed the '-e NEW' constraint to capture every single packet flow status
(
    conntrack -E -p udp --src "$XBOX_1_IP" --sport "$XBOX_1_PORT" 2>/dev/null &
    conntrack -E -p udp --src "$XBOX_2_IP" --sport "$XBOX_2_PORT" 2>/dev/null &
    wait
) | awk '
{
    event_type = $1
    target_ip = ""
    
    # --------------------------------------------------------------------------
    # PROCESSING PATH A: HANDSHAKES & STATUS CHANGES ([NEW] / [UPDATE])
    # --------------------------------------------------------------------------
    if (event_type == "[NEW]" || event_type == "[UPDATE]") {
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^dst=/) {
                split($i, p, "=")
                target_ip = p[2]
                break
            }
        }
    }
    # --------------------------------------------------------------------------
    # PROCESSING PATH B: PACKET TEARDOWNS & TIMEOUTS ([DESTROY])
    # --------------------------------------------------------------------------
    # In [DESTROY] blocks, the game server moves to the first src= field of the 
    # second tracking segment. We count src instances to grab it accurately.
    else if (event_type == "[DESTROY]") {
        src_count = 0
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^src=/) {
                src_count++
                if (src_count == 2) {
                    split($i, p, "=")
                    target_ip = p[2]
                    break
                }
            }
        }
    }
    
    # --- STRICT ENFORCEMENT FILTER ---
    # Write the server IP only if it successfully clears your local subnet rules
    if (target_ip != "" && target_ip !~ /^(192\.168\.|10\.|172\.|255\.|127\.)/) {
        print target_ip
        fflush()
    }
}' >> "$DUMP_FILE"
