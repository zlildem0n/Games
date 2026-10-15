#!/bin/sh
# ==============================================================================
# BLOCKED LIST REVIEWER (Single IP + 3-Tier)
# Re-checks blocked IPs against current GitHub list
# ==============================================================================
BLOCKED_FILE="/root/COD_Blocked.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
CONFIG_LIST="/root/COD_States"
MMDB_FILE="/root/GeoLite2-City.mmdb"
REMOTE_STATES="https://raw.githubusercontent.com/zlildem0n/Games/refs/heads/main/COD_States"
TEMP_FILE="/tmp/COD_Blocked_Review.tmp"

[ ! -f "$BLOCKED_FILE" ] && exit 0
[ ! -f "$MMDB_FILE" ] && echo "[!] GeoIP database missing" && exit 1

# Refresh the list from GitHub
echo "[*] Fetching latest COD_States from GitHub..."
if curl -k -sSL --connect-timeout 10 "$REMOTE_STATES" -o "${CONFIG_LIST}.tmp" && [ -s "${CONFIG_LIST}.tmp" ]; then
    mv -f "${CONFIG_LIST}.tmp" "$CONFIG_LIST"
    chmod 644 "$CONFIG_LIST"
    echo "[+] COD_States updated"
else
    echo "[!] Could not download COD_States – using local copy"
    rm -f "${CONFIG_LIST}.tmp"
fi

touch "$PRE_PENDING_FILE" 2>/dev/null
> "$TEMP_FILE"

echo "--- BLOCKED LIST REVIEW STARTED ---"

# Helper: check if value is in the GitHub list
in_list() {
    value="$1"
    [ ! -f "$CONFIG_LIST" ] && return 1
    sed 's/#.*//' "$CONFIG_LIST" | sed 's/[[:space:]]*$//' | grep -v '^$' | grep -qiw "^${value}$"
}

while read -r line; do
    [ -z "$line" ] && continue

    # Extract the IP (everything before the first space or |)
    SERVER_IP=$(echo "$line" | awk '{print $1}' | cut -d'|' -f1 | tr -d ' ')

    # Skip if it doesn't look like a single IP
    echo "$SERVER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || {
        echo "$line" >> "$TEMP_FILE"
        continue
    }

    # --- Tier 1: Country must be US ---
    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" country iso_code 2>/dev/null \
              | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)

    if [ -z "$COUNTRY" ] || [ "$COUNTRY" != "US" ]; then
        echo "$line" >> "$TEMP_FILE"
        continue
    fi

    # --- Tier 2: State must be in list ---
    REGION=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" subdivisions 0 iso_code 2>/dev/null \
             | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)

    if [ -z "$REGION" ] || ! in_list "$REGION"; then
        echo "$line" >> "$TEMP_FILE"
        continue
    fi

    # --- Tier 3: City must be in list ---
    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" city names en 2>/dev/null \
           | grep -oE '"[^"]+"' | tr -d '"' | head -1)
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [ -z "$CITY" ] || ! in_list "$CITY"; then
        echo "$line" >> "$TEMP_FILE"
        continue
    fi

    # All 3 tiers now pass → recover it
    echo "[+] Recovering: $SERVER_IP ($CITY, $REGION) → moving to Pre-Pending"
    echo "$SERVER_IP" >> "$PRE_PENDING_FILE"
    # Do not write it back to the blocked file

done < "$BLOCKED_FILE"

# Replace blocked file with the cleaned version
mv "$TEMP_FILE" "$BLOCKED_FILE"
echo "--- BLOCKED LIST REVIEW FINISHED ---"
