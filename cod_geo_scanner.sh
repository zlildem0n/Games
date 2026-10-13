#!/bin/sh
# ==============================================================================
# SCRIPT 2: DYNAMIC GEOGRAPHIC SCANNER ENGINE - GLOBAL SYSTEM MMDB (BETA 3.3)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
CONFIG_LIST="/root/COD_States"

# FIXED TARGET: Pointing strictly to your globally synchronized UniFi system path
MMDB_FILE="/usr/share/GeoIP/GeoLite2-City.mmdb"

touch "$PRE_PENDING_FILE" "$BLOCKED_FILE"

echo "--- LIVE STAGE 2 GLOBAL SYSTEM GEOGRAPHIC FILTER CORE ONLINE ---"

tail -f -n +1 "$DUMP_FILE" | while read -r SERVER_IP; do
    [ -z "$SERVER_IP" ] && continue
    SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')

    if grep -q "^$SERVER_IP" "$PRE_PENDING_FILE" 2>/dev/null || grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
        continue
    fi

    # 1. Country code validation check against global system file
    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" country iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | tr -d '[:space:]')
    [ -z "$COUNTRY" ] && COUNTRY="US"

    if [ "$COUNTRY" != "US" ]; then
        echo "$SUBNET_24 | Note: [Foreign Banned]" >> "$BLOCKED_FILE" && continue
    fi

    # 2. State Region Lookup - Reading cleanly from the system database layer
    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | tr -d '[:space:]')
    [ -z "$REGION" ] && REGION="UNK"

    # 3. City Lookup - Pulls unpadded name metrics
    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" city names en 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"')
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$CITY" ] && CITY="UnknownCity"

    # 4. Cross-reference your clean configuration list file records dynamically
    IS_ALLOWED=0
    if [ -f "$CONFIG_LIST" ]; then
        if grep -qi "^$CITY$" "$CONFIG_LIST" 2>/dev/null; then
            IS_ALLOWED=1
            [ "$REGION" = "UNK" ] && REGION="MAPPED"
        elif grep -qi "^$REGION$" "$CONFIG_LIST" 2>/dev/null; then
            IS_ALLOWED=1
        elif [ "$REGION" = "UNK" ] && [ "$CITY" = "UnknownCity" ]; then
            IS_ALLOWED=1
        fi
    else
        IS_ALLOWED=1
    fi

    if [ "$IS_ALLOWED" -eq 1 ]; then
        # 🟢 GEOPASS: Approved zone, moves forward to Stage 3 conntrack promoter
        echo "$SERVER_IP" >> "$PRE_PENDING_FILE"
    else
        # ❌ GEOBLOCK: Outside your dynamic profile list definitions
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [Distant Zone Banned] ($CITY, $REGION)" >> "$BLOCKED_FILE"
        fi
    fi
done
