#!/bin/sh
# ==============================================================================
# SCRIPT 6: UNBUFFERED HANDSHAKE PROMOTER (STAGE 3 ARCHITECTURE)
# ==============================================================================
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
PENDING_FILE="/root/COD_Pending.txt"

touch "$PENDING_FILE"

echo "--- LIVE STAGE 3 UNBUFFERED HANDSHAKE PROMOTER ONLINE ---"

# FIXED: Forcing instant line delivery with an unbuffered awk flush rule
tail -f -n +1 "$PRE_PENDING_FILE" | awk '{print $0; fflush()}' | while read -r RAW_IP; do
    [ -z "$RAW_IP" ] && continue
    
    # Scrub all hidden space and carriage return layout artifacts off the IP variable
    SERVER_IP=$(echo "$RAW_IP" | tr -d '[:space:]' | tr -d '\r')
    [ -z "$SERVER_IP" ] && continue
    
    grep -q "^$SERVER_IP" "$PENDING_FILE" 2>/dev/null && continue

    # FIXED: Give the server connection up to 5 seconds to complete its operational handshake
    handshake_loop=1
    while [ "$handshake_loop" -le 5 ]; do
        if [ -x "$(command -v conntrack)" ]; then
            RAW_TRACK=$(conntrack -L -p udp --dst "$SERVER_IP" 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
        else
            RAW_TRACK=$(grep -E "udp.*$SERVER_IP" /proc/net/nf_conntrack 2>/dev/null | grep -E "sport=(49806|49290)|dport=(49806|49290)")
        fi
        
        [ -z "$RAW_TRACK" ] && break

        PKT_COUNT=$(echo "$RAW_TRACK" | grep -oE 'packets=[0-9]+' | cut -d'=' -f2 | head -n1)
        BYTE_COUNT=$(echo "$RAW_TRACK" | grep -oE 'bytes=[0-9]+' | cut -d'=' -f2 | head -n1)
        [ -z "$PKT_COUNT" ] && PKT_COUNT=0
        [ -z "$BYTE_COUNT" ] && BYTE_COUNT=0

        # 12 Packets or 666 Bytes Handshake Gate Lock Passed!
        if [ "$PKT_COUNT" -ge 12 ] || [ "$BYTE_COUNT" -ge 666 ]; then
            if ! grep -q "^$SERVER_IP" "$PENDING_FILE" 2>/dev/null; then
                echo "$SERVER_IP" >> "$PENDING_FILE"
            fi
            break
        fi
        
        sleep 1
        handshake_loop=$((handshake_loop + 1))
    done
done
