#!/bin/sh
# ==============================================================================
# SCRIPT 2: STRICT 3-TIER GEOGRAPHIC FILTRATION ENGINE (BETA 4.0 - FIXED)
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
CONFIG_LIST="/root/COD_States"
MMDB_FILE="/root/GeoLite2-City.mmdb"

touch "$PRE_PENDING_FILE" "$BLOCKED_FILE" 2>/dev/null

echo "--- LIVE STAGE 2 STRICT 3-TIER FILTRATION ENGINE ONLINE ---"

is_known() {
    grep -q "^$1" "$PRE_PENDING_FILE" 2>/dev/null || \
    grep -q "^$1" "$BLOCKED_FILE" 2>/dev/null
}

tail -F -n +1 "$DUMP_FILE" 2>/dev/null | while read -r RAW_IP; do
    [ -z "$RAW_IP" ] && continue

    SERVER_IP=$(echo "$RAW_IP" | tr -d '[:space:]\r')
    [ -z "$SERVER_IP" ] && continue

    echo "$SERVER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || continue

    SUBNET_24=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/\.0\/24/')

    is_known "$SERVER_IP" && continue
    is_known "$SUBNET_24" && continue

    if [ ! -f "$MMDB_FILE" ]; then
        echo "[!] GeoIP database missing: $MMDB_FILE"
        continue
    fi

    # ==========================================================================
    # TIER 1: STRICT COUNTRY ISO CHECK (MUST BE 'US')
    # ==========================================================================
    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" country iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)
    
    if [ -z "$COUNTRY" ] || [ "$COUNTRY" != "US" ]; then
        [ -z "$COUNTRY" ] && COUNTRY="BLANK"
        echo "$SUBNET_24 | Note: [Tier 1 Blocked - Non-US/Unknown Country] ($COUNTRY)" >> "$BLOCKED_FILE"
        continue
    fi

    # ==========================================================================
    # TIER 2: STRICT STATE ISO CHECK (MUST MATCH ALLOWED REGIONS)
    # ==========================================================================
    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" subdivisions 0 iso_code 2>/dev/null | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)
    
    # Strict validation gate: If state is unknown, empty, or outside your allowed lanes, drop it!
    if [ -z "$REGION" ] || ! echo "NJ VA IL GA NY PA OH" | grep -qw "$REGION"; then
        [ -z "$REGION" ] && REGION="BLANK"
        echo "$SUBNET_24 | Note: [Tier 2 Blocked - Disallowed/Unknown State] ($REGION)" >> "$BLOCKED_FILE"
        continue
    fi

    # ==========================================================================
    # TIER 3: STRICT CITY NAME CHECK (MUST MATCH YOUR CONFIGURATION LIST)
    # ==========================================================================
    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" city names en 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' | head -1)
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [ -z "$CITY" ] || [ "$CITY" = "UnknownCity" ]; then
        echo "$SUBNET_24 | Note: [Tier 3 Blocked - Empty/Unknown City Name] ($REGION)" >> "$BLOCKED_FILE"
        continue
    fi

    IS_CITY_ALLOWED=0
    if [ -f "$CONFIG_LIST" ]; then
        CLEANED_LIST=$(sed 's/#.*//' "$CONFIG_LIST" | sed 's/[[:space:]]*$//' | grep -v '^$')
        if echo "$CLEANED_LIST" | grep -qi "^$CITY$"; then
            IS_CITY_ALLOWED=1
        fi
    else
        IS_CITY_ALLOWED=1
    fi

    if [ "$IS_CITY_ALLOWED" -eq 1 ]; then
        # 🟢 PASS: Matches your exact Country, State, and City rules!
        echo "$SERVER_IP" >> "$PRE_PENDING_FILE"
    else
        # ❌ FAIL: Outside your explicit city configurations
        echo "$SUBNET_24 | Note: [Tier 3 Blocked - Disallowed City] ($CITY, $REGION)" >> "$BLOCKED_FILE"
    fi
done
