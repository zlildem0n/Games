#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - EXCLUSIVE DESTINATION IP GATING (STAGE 1 - V11.7)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
MASTER_FILE="/root/COD_Master.txt"

# Console Target Profiles
XBOX_1_PORT="49806"
XBOX_2_PORT="49290"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE KERNEL NATIVE CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Strict Target Filter: sport ($XBOX_1_PORT|$XBOX_2_PORT) --> dport (30000-50000) [STRICT DST ONLY]"
echo "================================================================================"

# Stream unbuffered flows natively from netfilter
conntrack -E -p udp 2>/dev/null | awk -v pt1="$XBOX_1_PORT" -v pt2="$XBOX_2_PORT" \
-v dump="$DUMP_FILE" -v pre="$PRE_PENDING_FILE" -v post="$POST_PENDING_FILE" -v mast="$MASTER_FILE" '
BEGIN {
    # Initialize historical files into RAM memory lanes immediately on boot
    while ((getline line < dump) > 0)  { if (line != "") seen[line] = 1 } close(dump)
    while ((getline line < pre) > 0)   { if (line != "") seen[line] = 1 } close(pre)
    while ((getline line < post) > 0)  { if (line != "") seen[line] = 1 } close(post)
    while ((getline line < mast) > 0)  { 
        if (line != "") {
            split(line, m_parts, " ")
            seen[m_parts] = 1 
        }
    } close(mast)
}
{
    sport = ""; dst_ip = ""; dport = 0
    sport_count = 0; dst_count = 0; dport_count = 0

    # Isolate strictly the absolute first instance of the connection parameters
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^sport=/) {
            sport_count++
            if (sport_count == 1) { split($i, p, "="); sport = p[2] }
        }
        # TARGET LOCKED: Capture strictly the first dst= field on the line
        if ($i ~ /^dst=/) {
            dst_count++
            if (dst_count == 1) { split($i, p, "="); dst_ip = p[2] }
        }
        if ($i ~ /^dport=/) {
            dport_count++
            if (dport_count == 1) { split($i, p, "="); dport = int(p[2]) }
        }
        
        # Stop parsing immediately the moment the first destination block is isolated
        if (sport_count >= 1 && dst_count >= 1 && dport_count >= 1) { break }
    }

    # DOUBLE-PORT + FIRST DST LOCKDOWN GATE
    if ((sport == pt1 || sport == pt2) && (dport >= 30000 && dport <= 50000)) {
        
        # Filter out local network broadcasts or loopbacks safely
        if (dst_ip != "" && dst_ip !~ /^(192\.168\.|10\.|172\.|255\.|127\.)/) {
            
            # Check RAM array cache for deduplication
            if (!(dst_ip in seen)) {
                seen[dst_ip] = 1
                print dst_ip >> dump
                fflush(dump)
            }
        }
    }
}'
