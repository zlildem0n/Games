#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER (IMPROVED)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
INTERFACE="eth4"
PORTS="49806 or 49290"
MAX_LINES=50000          # prevent unbounded growth

# Ensure file exists
touch "$DUMP_FILE" 2>/dev/null
chmod 666 "$DUMP_FILE" 2>/dev/null

# Simple size protection
if [ -f "$DUMP_FILE" ]; then
    lines=$(wc -l < "$DUMP_FILE" 2>/dev/null || echo 0)
    if [ "$lines" -gt "$MAX_LINES" ]; then
        tail -n $((MAX_LINES / 2)) "$DUMP_FILE" > "${DUMP_FILE}.tmp"
        mv "${DUMP_FILE}.tmp" "$DUMP_FILE"
    fi
fi

echo "--- LIVE RECONNAISSANCE PACKET SNIPER ACTIVE ---"
echo "[*] Interface: $INTERFACE | Ports: $PORTS"
echo "================================================================================"

# More reliable IP extraction
tcpdump -i "$INTERFACE" -nn -l -q "udp and (port $PORTS)" 2>/dev/null | \
awk '
{
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
            # Prefer the side that is NOT the local console when possible
            if ($(i-1) == ">" || $(i+1) ~ /^[0-9]+$/) {
                print $i
                fflush()
            }
        }
    }
}' >> "$DUMP_FILE"
