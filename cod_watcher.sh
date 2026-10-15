#!/bin/sh
# ==============================================================================
# SCRIPT 1: RAW NETWORK SNIPER - HARDCODED WAN PROTECTION SHIELD (STAGE 1 - V9.6)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"

# Console Target Profiles
XBOX_1_IP="192.168.1.15"
XBOX_1_PORT="49806"

XBOX_2_IP="192.168.1.6"
XBOX_2_PORT="49290"

# FIXED: Hardcoded strictly as a text value to stop command execution loops
MY_WAN_IP="24.229.189.181"

if [ ! -f "$DUMP_FILE" ]; then
    touch "$DUMP_FILE" && chmod 666 "$DUMP_FILE"
fi

echo "--- LIVE KERNEL NATIVE CONNTRACK PACKET SNIPER ACTIVE ---"
echo "[*] Tracking ALL events for consoles. Hardcoded WAN Shield: $MY_WAN_IP"
echo "================================================================================"

# ALL-EVENTS NATIVE STREAM
(
    conntrack -E -p udp --src "$XBOX_1_IP" --sport "$XBOX_1_PORT" 2>/dev/null &
    conntrack -E -p udp --src "$XBOX_2_IP" --sport "$XBOX_2_PORT" 2>/dev/null &
    wait
) | awk -v ip1="$XBOX_1_IP" -v pt1="$XBOX_1_PORT" -v ip2="$XBOX_2_IP" -v pt2="$XBOX_2_PORT" -v wan="$MY_WAN_IP" '
{
    is_console_flow = 0
    server_ip = ""
    
    # Phase 1: Verify the line belongs to one of your targeted gaming console ports
    for (i = 1; i <= NF; i++) {
        if ($i == "sport="pt1 || $i == "dport="pt1 || $i == "sport="pt2 || $i == "dport="pt2) {
            is_console_flow = 1
        }
    }
    
    # Phase 2: Evaluate every unique IP on the connection event layout string
    if (is_console_flow == 1) {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^(src|dst)=/) {
                split($i, p, "=")
                current_ip = p[2]
                
                # IRONCLAD SHIELD GATES:
                # Instantly drop if the string matches your console IPs or your hardcoded WAN IP
                if (current_ip != "" && 
                    current_ip != ip1 && 
                    current_ip != ip2 && 
                    current_ip != wan && 
                    current_ip != "127.0.0.1" && 
                    current_ip !~ /^(192\.168\.|10\.|172\.|255\.)/) {
                    
                    server_ip = current_ip
                    break # Isolated the true external server target cleanly
                }
            }
        }
        
        # Print only the verified game server destination
        if (server_ip != "") {
            print server_ip
            fflush()
        }
    }
}' >> "$DUMP_FILE"
