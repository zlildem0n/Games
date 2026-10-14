#!/bin/sh
# ==============================================================================
# SCRIPT 2: DYNAMIC GEOGRAPHIC SCANNER (IMPROVED)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
CONFIG_LIST="/root/COD_States"
MMDB_FILE="/mnt/.rwfs/data/root/GeoLite2-City.mmdb"

touch "$PRE_PENDING_FILE" "$BLOCKED_FILE" 2>/dev/null

echo "--- LIVE STAGE 2 GEOGRAPHIC FILTER ONLINE ---"

# Helper: check if IP already processed
is_known() {
    grep -q "^$1" "$PRE_PENDING_FILE" 2>/dev/null || \
    grep -q "^$1" "$BLOCKED_FILE" 2>/dev/null
}

tail -F -n +1 "$DUMP_FILE" 2>/dev/null | while read -r RAW_IP; do
    [ -z "$RAW_IP" ] && continue

    SERVER_IP=$(echo "$RAW_IP" | tr -d '[:space:]\r')
    [ -z "$SERVER_IP" ] && continue

    # Basic IP validation
    echo "$SERVER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || continue

    SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')

    is_known "$SERVER_IP" && continue
    is_known "$SUBNET_24" && continue

    # GeoIP lookup
    if [ ! -f "$MMDB_FILE" ]; then
        echo "[!] GeoIP database missing: $MMDB_FILE"
        continue
    fi

    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" country iso_code 2>/dev/null \
              | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)
    [ -z "$COUNTRY" ] && COUNTRY="XX"

    if [ "$COUNTRY" != "US" ]; then
        echo "$SUBNET_24 | Note: [Foreign] ($COUNTRY)" >> "$BLOCKED_FILE"
        continue
    fi

    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" subdivisions 0 iso_code 2>/dev/null \
             | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)
    [ -z "$REGION" ] && REGION="UNK"

    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" city names en 2>/dev/null \
           | grep -oE '"[^"]+"' | tr -d '"' | head -1)
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$CITY" ] && CITY="UnknownCity"

    IS_ALLOWED=0
    if [ -f "$CONFIG_LIST" ]; then
        if sed 's/#.*//' "$CONFIG_LIST" | sed 's/[[:space:]]*$//' | grep -v '^$' | \
           grep -qi "^${CITY}$"; then
            IS_ALLOWED=1
        fi
    else
        IS_ALLOWED=1
    fi

    if [ "$IS_ALLOWED" -eq 1 ]; then
        echo "$SERVER_IP" >> "$PRE_PENDING_FILE"
    else
        echo "$SUBNET_24 | Note: [Distant] ($CITY, $REGION)" >> "$BLOCKED_FILE"
    fi
done
