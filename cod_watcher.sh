#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - KERNEL CONNTRACK EVENT ENGINE (STAGE 1)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PORTS="49806"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE KERNEL CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Monitoring real-time matchmaking handshakes via netfilter states..."
echo "================================================================================"

# Force unbuffered streaming (-o unbuffered) tracking ONLY new UDP gaming sockets
# Output line example: [NEW] udp 17 30 src=192.168.1.50 dst=45.76.4.42 sport=49806 dport=49806
conntrack -E -p udp -e NEW 2>/dev/null | awk -v ports="$PORTS" '
BEGIN {
    # Split allowed destination ports into an array for high-speed checking
    split(ports, p_arr, ",")
}
{
    # Validate it is a fresh kernel flow tracking string
    if ($1 == "[NEW]") {
        dst_ip = ""
        dport = 0
        
        # Scan fields to pull destination metrics cleanly
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^dst=/) {
                split($i, ip_part, "=")
                dst_ip = ip_part[2]
            }
            if ($i ~ /^dport=/) {
                split($i, port_part, "=")
                dport = port_part[2]
                break # We found the primary layer direction parameters
            }
        }
        
        # Cross-reference extracted destination port against your console ports
        if (dst_ip != "" && (dport == p_arr[1] || dport == p_arr[2])) {
            print dst_ip
            fflush()
        }
    }
}' >> "$DUMP_FILE"
