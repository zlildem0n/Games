#!/bin/sh
# ==============================================================================
# SCRIPT 1: UDP NETWORK CAPTURE
# Captures individual IPv4 addresses matching the specified port rules.
# ==============================================================================

DUMP_FILE="/root/COD_Dump.txt"
INTERFACE="eth4"

# Ensure the dump file exists and is writable by this process.
if ! touch "$DUMP_FILE"; then
    echo "[ERROR] Cannot create or access $DUMP_FILE" >&2
    exit 1
fi

chmod 600 "$DUMP_FILE" 2>/dev/null

if ! command -v tcpdump >/dev/null 2>&1; then
    echo "[ERROR] tcpdump is not installed." >&2
    exit 1
fi

echo "--- LIVE UDP NETWORK CAPTURE ACTIVE ---"
echo "[*] Interface: $INTERFACE"
echo "[*] Required port: 49806 or 49290"
echo "[*] Matching port range: 30000-50000"
echo "[*] Output: $DUMP_FILE"
echo "============================================================"

tcpdump -i "$INTERFACE" -nn -l \
    'udp and (port 49806 or port 49290) and portrange 30000-50000' \
    2>/dev/null |
awk '
{
    # Extract IPv4 endpoints from tcpdump output.
    # Expected format includes: 192.0.2.10.49806 > 192.0.2.20.35000
    for (i = 1; i <= NF; i++) {
        if ($i == ">") {
            src = $(i-1)
            dst = $(i+1)

            sub(/\.$/, "", src)
            sub(/\.$/, "", dst)

            # Remove the final .PORT component.
            sub(/\.[0-9]+$/, "", src)
            sub(/\.[0-9]+$/, "", dst)

            if (src ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                print src
                fflush()
            }

            if (dst ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                print dst
                fflush()
            }
        }
    }
}' >> "$DUMP_FILE"
