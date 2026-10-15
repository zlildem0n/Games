#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - ALL-EVENTS + RAM CACHE SHIELD (STAGE 1 - V10.5)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
MASTER_FILE="/root/COD_Master.txt"

# Console Target Profiles
XBOX_1_IP="192.168.1.15"
XBOX_1_PORT="49806"

XBOX_2_IP="192.168.1.6"
XBOX_2_PORT="49290"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE KERNEL NATIVE CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Filter: sport ($XBOX_1_PORT|$XBOX_2_PORT) -> dport (30000-50000) [RAM SHIELD]"
echo "================================================================================"

# Stream unbuffered flows natively from netfilter
conntrack -E -p udp 2>/dev/null | awk -v ip1="$XBOX_1_IP" -v pt1="$XBOX_1_PORT" -v ip2="$XBOX_2_IP" -v pt2="$XBOX_2_PORT" \
-v dump="$DUMP_FILE" -v pre="$PRE_PENDING_FILE" -v post="$POST_PENDING_FILE" -v mast="$MASTER_FILE" '
BEGIN {
    # 1. Initialize historical files into RAM memory lanes immediately on boot
    while ((getline line < dump) > 0)  { if (line != "") seen[line] = 1 } close(dump)
    while ((getline line < pre) > 0)   { if (line != "") seen[line] = 1 } close(pre)
    while ((getline line < post) > 0)  { if (line != "") seen[line] = 1 } close(post)
    while ((getline line < mast) > 0)  { 
        if (line != "") {
            split(line, m_parts, " ")
            seen[m_parts[1]] = 1 
        }
    } close(mast)
}
{
    is_console_flow = 0
    server_ip = ""
    server_port = 0
    
    # PHASE 1: Look at the port variables anywhere on the line to confirm console sport source
    for (i = 1; i <= NF; i++) {
        if ($i == "sport="pt1 || $i == "sport="pt2) {
            is_console_flow = 1
        }
        if ($i ~ /^dst=/) {
            split($i, p, "=")
            if (server_ip == "") server_ip = p[2]
        }
        if ($i ~ /^dport=/) {
            split($i, p, "=")
            if (server_port == 0) server_port = int(p[2])
        }
    }
    
    # PHASE 2: If verified console flow, enforce gaming port range and duplicate shields
    if (is_console_flow == 1 && server_ip != "" && server_port >= 30000 && server_port <= 50000) {
        
        # LAN & MULTICAST PROTECTION SHIELD
        if (server_ip !~ /^(192\.168\.|10\.|172\.|255\.|127\.)/) {
            
            # 🚨 THE IN-MEMORY RAM DEDUPLICATION CHECK
            # Checks the ultra-fast RAM array. If it is completely fresh, print and lock it.
            if (!(server_ip in seen)) {
                seen[server_ip] = 1
                print server_ip >> dump
                fflush(dump)
            }
        }
    }
}'
