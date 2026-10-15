#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - NATIVE KERNEL FILTER ENGINE (STAGE 1 - V8.0)
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
echo "[*] Hard-locked onto native console streams: $XBOX_1_IP & $XBOX_2_IP"
echo "================================================================================"

# UNBUFFERED DUAL-STREAM PIPELINE: Fires up two isolated, native hardware filters concurrently
# This instructs the kernel to drop everything else and output ONLY your exact console match events.
(
    conntrack -E -p udp -e --src "$XBOX_1_IP" --sport "$XBOX_1_PORT" 2>/dev/null &
    conntrack -E -p udp -e --src "$XBOX_2_IP" --sport "$XBOX_2_PORT" 2>/dev/null &
    wait
) | awk '
{
    if ($1 == "[NEW]") {
        # Loop strictly across the first few fields to isolate the game server destination IP address
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^dst=/) {
                split($i, p, "=")
                dst_ip = p[2]
                
                # Verify we captured an external game server host, never local broadcasts
                if (dst_ip != "" && dst_ip !~ /^(192\.168\.|10\.|172\.|255\.)/) {
                    print dst_ip
                    fflush()
                }
                break # Found the server target, exit line loop immediately
            }
        }
    }
}' >> "$DUMP_FILE"
