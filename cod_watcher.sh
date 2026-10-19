#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - PURE PORT GATED SUBNET FILTER (V12.4)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
POST_PENDING_FILE="/root/COD_Post_Pending.txt"
MASTER_FILE="/root/COD_Master.txt"
NET_BLOCKS="/root/COD_Hardware_Blocks"

# Console Target Profiles
XBOX_1_PORT="49806"
XBOX_2_PORT="49290"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

if [ ! -f "$NET_BLOCKS" ]; then
    touch "$NET_BLOCKS" && chmod 644 "$NET_BLOCKS"
fi

echo "--- LIVE KERNEL NATIVE CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Strict Gating: sport ($XBOX_1_PORT|$XBOX_2_PORT) --> dport (30000-50000)"
echo "================================================================================"

# Stream unbuffered flows natively from netfilter into your pure filter matrix
conntrack -E -p udp 2>/dev/null | awk -v pt1="$XBOX_1_PORT" -v pt2="$XBOX_2_PORT" \
-v dump="$DUMP_FILE" -v pre="$PRE_PENDING_FILE" -v post="$POST_PENDING_FILE" -v mast="$MASTER_FILE" -v blocks="$NET_BLOCKS" '
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

    # 2. Load your complete /24 subnet blocks directly into RAM
    while ((getline line < blocks) > 0) {
        if (line != "" && line !~ /^#/) {
            banned_subnets[line] = 1
        }
    } close(blocks)
}
{
    # FAST TOP-GATE CHECK: Only look at lines starting with [NEW] or [UPDATE] to avoid processing garbage
    if ($0 ~ "sport="pt1 || $0 ~ "sport="pt2) {
        
        sport = ""; dst_ip = ""; dport = 0
        sport_count = 0; dst_count = 0; dport_count = 0
        
        # FIXED: Loop through all fields on the line dynamically (NF) instead of cutting off at field 7
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^sport=/) { 
                sport_count++; if (sport_count == 1) { split($i, p, "="); sport = p[2] } 
            }
            if ($i ~ /^dst=/) { 
                dst_count++; if (dst_count == 1) { split($i, p, "="); dst_ip = p[2] } 
            }
            if ($i ~ /^dport=/) { 
                dport_count++; if (dport_count == 1) { split($i, p, "="); dport = int(p[2]) } 
            }
            if (sport_count >= 1 && dst_count >= 1 && dport_count >= 1) { break }
        }

        # HARD ENFORCEMENT: Enforce your exact sport profiles and your 30000-50000 dport range strictly
        if ((sport == pt1 || sport == pt2) && (dport >= 30000 && dport <= 50000)) {
            
            # Discard any local loopbacks or local home network broadcasts safely
            if (dst_ip != "" && dst_ip !~ /^(192\.168\.|10\.|172\.|255\.|127\.)/) {
                
                # Natively calculate the true /24 subnet string layout cleanly
                split(dst_ip, ip_parts, ".")
                current_subnet = ip_parts[1] "." ip_parts[2] "." ip_parts[3] ".0/24"
                
                # THE EXEMPTION BYPASS AND SUB-FILTER CORE
                if (current_subnet == "20.201.200.0/24") {
                    if (!(dst_ip in seen)) {
                        seen[dst_ip] = 1
                        print dst_ip >> dump
                        fflush(dump)
                    }
                } else {
                    if (!(current_subnet in banned_subnets)) {
                        if (!(dst_ip in seen)) {
                            seen[dst_ip] = 1
                            print dst_ip >> dump
                            fflush(dump)
                        }
                    }
                }
            }
        }
    }
}'
