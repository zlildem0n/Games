#!/bin/sh
# ==============================================================================
# SCRIPT 2: GEOGRAPHIC FILTER CORE (STAGE 2 ARCHITECTURE)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
CONFIG_LIST="/root/COD_States"
MMDB_FILE="/root/GeoLite2-City.mmdb"

touch "$PRE_PENDING_FILE" "$BLOCKED_FILE"

echo "--- LIVE STAGE 2 GEOGRAPHIC FILTER CORE ONLINE ---"
tail -f -n +1 "$DUMP_FILE" | while read -r SERVER_IP; do
    [ -z "$SERVER_IP" ] && continue
    SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')

    if grep -q "^$SERVER_IP" "$PRE_PENDING_FILE" 2>/dev/null || grep -q "^$SUBNET_24" "$BLOCKED_FILE" 2>/dev/null; then
        continue
    fi

    # Country and location parsing blocks
    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" country iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | tr -d '[:space:]')
    [ -z "$COUNTRY" ] && COUNTRY="US"

    if [ "$COUNTRY" != "US" ]; then
        echo "$SUBNET_24 | Note: [Foreign]" >> "$BLOCKED_FILE" && continue
    fi

    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | tr -d '[:space:]')
    [ -z "$REGION" ] && REGION="UNK"
    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" city names en 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$CITY" ] && CITY="UnknownCity"

    IS_ALLOWED=0
    if grep -qi "^$CITY$" "$CONFIG_LIST" 2>/dev/null || grep -qi "^$REGION$" "$CONFIG_LIST" 2>/dev/null || [ "$REGION" = "UNK" ]; then
        IS_ALLOWED=1
    fi

    if [ "$IS_ALLOWED" -eq 1 ]; then
        echo "$SERVER_IP" >> "$PRE_PENDING_FILE"
    else
        echo "$SUBNET_24 | Note: [Distant Banned ($CITY, $REGION)]" >> "$BLOCKED_FILE"
    fi
done
