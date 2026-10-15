#!/bin/sh
# ==============================================================================
# SCRIPT 1: DUAL-CONSOLE STRICT CONNTRACK SNIPER (STAGE 1 - V4.5)
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

echo "--- LIVE KERNEL CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Monitoring strict console targets: $XBOX_1_IP:$XBOX_1_PORT & $XBOX_2_IP:$XBOX_2_PORT"
echo "================================================================================"

# Stream unbuffered new UDP flows from netfilter
conntrack -E -p udp -e NEW 2>/dev/null | awk -v ip1="$XBOX_1_IP" -v pt1="$XBOX_1_PORT" -v ip2="$XBOX_2_IP" -v pt2="$XBOX_2_PORT" '
BEGIN {
    # Set explicit profile markers
    src_ip = ""
    dst_ip = ""
    sport  = 0
    dport  = 0
}
{
    if ($1 == "[NEW]") {
        src_ip = ""; dst_ip = ""; sport = 0; dport = 0
        
        # Parse fields dynamically out of the kernel connection tracking string
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^src=/) {
                split($i, p, "=")
                src_ip = p[2]
            }
            if ($i ~ /^dst=/) {
                split($i, p, "=")
                dst_ip = p[2]
            }
            if ($i ~ /^sport=/) {
                split($i, p, "=")
                sport = p[2]
            }
            if ($i ~ /^dport=/) {
                split($i, p, "=")
                dport = p[2]
                break # Reached end of outbound tracking parameters
            }
        }
        
        # --- STRICT ENFORCEMENT FILTER ---
        # Rule A: Matches your Xbox IP and your exact Xbox port allocation
        # Rule B: Matches your Brother's Xbox IP and his exact port allocation
        if ((src_ip == ip1 && sport == pt1) || (src_ip == ip2 && sport == pt2)) {
            # Ensure we are capturing the external gaming server, never an internal broadcast
            if (dst_ip != "" && dst_ip !~ /^(192\.168\.|10\.|172\.|255\.)/) {
                print dst_ip
                fflush()
            }
        }
    }
}' >> "$DUMP_FILE"
