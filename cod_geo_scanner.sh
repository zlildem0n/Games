#!/bin/sh
# ==============================================================================
# SCRIPT 2: 3-TIER GEO FILTER
# Country (US) → State (from GitHub) → City (from GitHub)
# Writes individual IP + reason to blocked list
# ==============================================================================
DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
CONFIG_LIST="/root/COD_States"
MMDB_FILE="/root/GeoLite2-City.mmdb"
REMOTE_STATES="https://raw.githubusercontent.com/zlildem0n/Games/refs/heads/main/COD_States"

# Download latest list from GitHub
echo "[*] Fetching latest COD_States from GitHub..."
if curl -k -sSL --connect-timeout 10 "$REMOTE_STATES" -o "${CONFIG_LIST}.tmp" && [ -s "${CONFIG_LIST}.tmp" ]; then
    mv -f "${CONFIG_LIST}.tmp" "$CONFIG_LIST"
    chmod 644 "$CONFIG_LIST"
    echo "[+] COD_States updated from GitHub"
else
    echo "[!] Failed to download COD_States – using local copy if available"
    rm -f "${CONFIG_LIST}.tmp"
fi

touch "$PRE_PENDING_FILE" "$BLOCKED_FILE" 2>/dev/null

echo "--- LIVE STAGE 2: 3-TIER FILTER (GitHub list) ONLINE ---"

is_known() {
    grep -q "^$1" "$PRE_PENDING_FILE" 2>/dev/null || \
    grep -q "^$1" "$BLOCKED_FILE" 2>/dev/null
}

# Helper: check if value exists in the config list
in_list() {
    value="$1"
    [ ! -f "$CONFIG_LIST" ] && return 1
    sed 's/#.*//' "$CONFIG_LIST" | sed 's/[[:space:]]*$//' | grep -v '^$' | grep -qiw "^${value}$"
}

tail -F -n +1 "$DUMP_FILE" 2>/dev/null | while read -r RAW_IP; do
    [ -z "$RAW_IP" ] && continue

    SERVER_IP=$(echo "$RAW_IP" | tr -d '[:space:]\r')
    [ -z "$SERVER_IP" ] && continue

    echo "$SERVER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || continue

    is_known "$SERVER_IP" && continue

    if [ ! -f "$MMDB_FILE" ]; then
        echo "[!] GeoIP database missing: $MMDB_FILE"
        continue
    fi

    # --------------------------------------------------------------------------
    # TIER 1: Country must be US
    # --------------------------------------------------------------------------
    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" country iso_code 2>/dev/null \
              | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)

    if [ -z "$COUNTRY" ] || [ "$COUNTRY" != "US" ]; then
        [ -z "$COUNTRY" ] && COUNTRY="UNKNOWN"
        echo "$SERVER_IP | Note: [Tier 1] Non-US ($COUNTRY)" >> "$BLOCKED_FILE"
        continue
    fi

    # --------------------------------------------------------------------------
    # TIER 2: State must be in the GitHub list
    # --------------------------------------------------------------------------
    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" subdivisions 0 iso_code 2>/dev/null \
             | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)

    if [ -z "$REGION" ] || ! in_list "$REGION"; then
        [ -z "$REGION" ] && REGION="UNKNOWN"
        echo "$SERVER_IP | Note: [Tier 2] State not in list ($REGION)" >> "$BLOCKED_FILE"
        continue
    fi

    # --------------------------------------------------------------------------
    # TIER 3: City must be in the GitHub list
    # --------------------------------------------------------------------------
    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" city names en 2>/dev/null \
           | grep -oE '"[^"]+"' | tr -d '"' | head -1)
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [ -z "$CITY" ]; then
        echo "$SERVER_IP | Note: [Tier 3] Unknown City ($REGION)" >> "$BLOCKED_FILE"
        continue
    fi

    if in_list "$CITY"; then
        # All tiers passed
        echo "$SERVER_IP" >> "$PRE_PENDING_FILE"
    else
        echo "$SERVER_IP | Note: [Tier 3] City not in list ($CITY, $REGION)" >> "$BLOCKED_FILE"
    fi
done
