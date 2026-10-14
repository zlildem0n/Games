#!/bin/sh
# ==============================================================================
# BLOCKED LIST REVIEWER - Re-checks blocked entries against current city list
# ==============================================================================
BLOCKED_FILE="/root/COD_Blocked.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
CONFIG_LIST="/root/COD_States"
MMDB_FILE="/root/GeoLite2-City.mmdb"
TEMP_FILE="/tmp/COD_Blocked_Review.tmp"

[ ! -f "$BLOCKED_FILE" ] && exit 0
[ ! -f "$MMDB_FILE" ] && echo "[!] GeoIP database missing" && exit 1

touch "$PRE_PENDING_FILE" 2>/dev/null
> "$TEMP_FILE"

echo "--- BLOCKED LIST REVIEW STARTED ---"

while read -r line; do
    [ -z "$line" ] && continue

    # Extract the subnet (everything before the first space or |)
    SUBNET=$(echo "$line" | awk '{print $1}' | cut -d'|' -f1 | tr -d ' ')

    # Skip if it doesn't look like a subnet
    echo "$SUBNET" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' || {
        echo "$line" >> "$TEMP_FILE"
        continue
    }

    # Take a representative IP from the /24 (x.x.x.1)
    TEST_IP=$(echo "$SUBNET" | sed 's/\.0\/24$/\.1/; s/\/[0-9]*$//')

    # Lookup city
    CITY=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" city names en 2>/dev/null \
           | grep -oE '"[^"]+"' | tr -d '"' | head -1)
    CITY=$(echo "$CITY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$CITY" ] && CITY="Unknown"

    COUNTRY=$(mmdblookup --file "$MMDB_FILE" --ip "$TEST_IP" country iso_code 2>/dev/null \
              | grep -oE '"[A-Z]{2}"' | tr -d '"' | head -1)
    [ -z "$COUNTRY" ] && COUNTRY="XX"

    # Only consider US
    if [ "$COUNTRY" != "US" ]; then
        echo "$line" >> "$TEMP_FILE"
        continue
    fi

    # Check against allowed cities
    IS_ALLOWED=0
    if [ -f "$CONFIG_LIST" ]; then
        if sed 's/#.*//' "$CONFIG_LIST" | sed 's/[[:space:]]*$//' | grep -v '^$' | \
           grep -qi "^${CITY}$"; then
            IS_ALLOWED=1
        fi
    fi

    if [ "$IS_ALLOWED" -eq 1 ]; then
        echo "[+] Recovering: $SUBNET ($CITY) → moving to Pre-Pending"
        # Put a representative IP into pre-pending so the rest of the pipeline can process it
        echo "$TEST_IP" >> "$PRE_PENDING_FILE"
        # Do NOT write it back to the blocked file
    else
        # Still blocked
        echo "$line" >> "$TEMP_FILE"
    fi

done < "$BLOCKED_FILE"

# Replace the blocked file with the cleaned version
mv "$TEMP_FILE" "$BLOCKED_FILE"
echo "--- BLOCKED LIST REVIEW FINISHED ---"
