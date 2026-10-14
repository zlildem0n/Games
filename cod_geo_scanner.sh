#!/bin/sh
# ==============================================================================
# SCRIPT 2: DYNAMIC GEOGRAPHIC SCANNER ENGINE - UNIFI NATIVE PATH (BETA 3.7)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
CONFIG_LIST="/root/COD_States"

# FIXED NATIVE TARGET: Pointing strictly to the real UniFi OS database file folder path
MMDB_FILE="/usr/share/dpi/geoip/GeoLite2-City.mmdb"

touch "$PRE_PENDING_FILE" "$BLOCKED_FILE"

echo "--- LIVE STAGE 2 GLOBAL SYSTEM GEOGRAPHIC FILTER CORE ONLINE ---"

tail -f -n +1 "$DUMP_FILE" | awk '{print $0; fflush()}' | while read -r RAW_IP; do
    [ -z "$RAW_IP" ] && continue
    SERVER_IP=$(echo "$RAW_IP" | tr -d '[:space:]' | tr -d '\r')
    [ -z "$SERVER_IP" ] && continue
    
    SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')

    if grep -q "^$SERVER_IP" "$PRE_PENDING_FILE" 2>/dev/null || grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
        continue
    fi

    # 1. Country code validation check against global system file
    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" country iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | tr -d '[:space:]')
    [ -z "$COUNTRY" ] && COUNTRY="US"

    if [ "$COUNTRY" != "US" ]; then
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [Foreign Banned] ($COUNTRY)" >> "$BLOCKED_FILE"
        fi
        continue
    fi

    # 2. State Region Lookup
    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | tr -d '[:space:]')
    [ -z "$REGION" ] && REGION="UNK"

    # 3. City Lookup - Pulls name metrics
    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" city names en 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"')
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$CITY" ] && CITY="UnknownCity"

    # 4. Cross-reference your clean city-only configuration list file records dynamically
    IS_ALLOWED=0
    if [ -f "$CONFIG_LIST" ]; then
        CLEANED_LIST=$(sed 's/#.*//' "$CONFIG_LIST" | sed 's/[[:space:]]*$//' | grep -v '^$')
        
        if echo "$CLEANED_LIST" | grep -qi "^$CITY$"; then
            IS_ALLOWED=1
            [ "$REGION" = "UNK" ] && REGION="MAPPED"
        elif [ "$REGION" = "UNK" ] && [ "$CITY" = "UnknownCity" ]; then
            IS_ALLOWED=1
        fi
    else
        IS_ALLOWED=1
    fi

    if [ "$IS_ALLOWED" -eq 1 ]; then
        echo "$SERVER_IP" >> "$PRE_PENDING_FILE"
    else
        if ! grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
            echo "$SUBNET_24 | Note: [Distant Zone Banned] ($CITY)" >> "$BLOCKED_FILE"
        fi
    fi
done
