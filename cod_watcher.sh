#!/bin/bash

# Script 1 — UniFi Xbox UDP traffic capture
# Interface: eth4
# Output: /root/COD_Dump.txt

set -u

IFACE="eth4"
LOG="/root/COD_Dump.txt"

# Xbox ports paired with the game-server candidate range
GAME_FILTER='udp and (port 49806 or port 49290) and portrange 30000-50000'

# Xbox service traffic on ports 3074 and 3544
SERVICE_FILTER='udp and (port 49806 or port 49290) and (port 3074 or port 3544)'

if ! command -v tcpdump >/dev/null 2>&1; then
    echo "ERROR: tcpdump is not installed."
    exit 1
fi

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "ERROR: Interface $IFACE was not found."
    exit 1
fi

touch "$LOG" || {
    echo "ERROR: Cannot write to $LOG"
    exit 1
}

chmod 600 "$LOG"

echo "Starting capture on $IFACE"
echo "Output: $LOG"
echo "Press Ctrl+C to stop."

tcpdump -ni "$IFACE" -l -tttt \
    "(($GAME_FILTER) or ($SERVICE_FILTER))" \
    >> "$LOG" 2>&1
