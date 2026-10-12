#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER (DUAL CONSOLE WORKSTATION UPDATE)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
INTERFACE="eth4"

# MULTI-CONSOLE EXPANSION: Captures both primary and secondary console ports
FILTER_RULE="udp port 49806 or udp port 49290"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE RECONNAISSANCE PACKET SNIPER ACTIVE ---"
echo "[*] Capturing real-time matchmaking handshakes on $INTERFACE..."
echo "================================================================================"

# Execute stream parsing with line buffering forced (-l) to feed Stage 2 instantly
tcpdump -i "$INTERFACE" -nn -l "$FILTER_RULE" 2>/dev/null | awk '{
    # Isolate inbound server source address fields cleanly
    for(i=1;i<=NF;i++) {
        if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $(i-1) == ">") {
            split($i, parts, ".")
            ip = parts[1]"."parts[2]"."parts[3]"."parts[4]
            print ip
            fflush()
        }
    }
}' >> "$DUMP_FILE"
