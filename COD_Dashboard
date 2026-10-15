#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER (WAN + exact IP Master check)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
MASTER_FILE="/root/COD_Master.txt"
INTERFACE="eth4"
PORTS="49806 or 49290"
MAX_LINES=50000

# Optional: put your public WAN IP here to ignore it
WAN_IP=""

touch "$DUMP_FILE" "$MASTER_FILE" 2>/dev/null
chmod 666 "$DUMP_FILE" 2>/dev/null

# Size protection
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

tcpdump -i "$INTERFACE" -nn -l -q "udp and (port $PORTS)" 2>/dev/null | \
awk -v wan="$WAN_IP" -v master="$MASTER_FILE" '
function already_processed(ip) {
    # Only check for the exact IP in the Master list
    cmd = "grep -q \"^" ip "\" " master " 2>/dev/null"
    return (system(cmd) == 0)
}

{
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
            ip = $i

            # Skip our own WAN IP
            if (wan != "" && ip == wan) continue

            # Only take the remote side
            if ($(i-1) == ">" || $(i+1) == ">") {

                # Skip if this exact IP is already in Master list
                if (already_processed(ip)) continue

                print ip
                fflush()
            }
        }
    }
}' >> "$DUMP_FILE"
