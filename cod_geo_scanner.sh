
#!/bin/sh
# ==============================================================================
# SCRIPT 2: STRICT 3-TIER GEOGRAPHIC FILTRATION ENGINE (BETA 4.2)
# GitHub-based city, state, and country configuration
# ==============================================================================

DUMP_FILE="/root/COD_Dump.txt"
PRE_PENDING_FILE="/root/COD_Pre_Pending.txt"
BLOCKED_FILE="/root/COD_Blocked.txt"
CONFIG_URL="https://raw.githubusercontent.com/zlildem0n/Games/main/COD_States"
CONFIG_LIST="/root/COD_States"
CONFIG_TMP="/root/COD_States.tmp"
MMDB_FILE="/root/GeoLite2-City.mmdb"

echo "--- LIVE STAGE 2 STRICT 3-TIER FILTRATION ENGINE STARTING ---"

# ==============================================================================
# INITIAL VALIDATION
# ==============================================================================

for CMD in curl mmdblookup awk grep sed tr tail; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "[ERROR] Required command not found: $CMD" >&2
        exit 1
    fi
done

if [ ! -r "$DUMP_FILE" ]; then
    echo "[ERROR] Dump file missing or unreadable: $DUMP_FILE" >&2
    exit 1
fi

if [ ! -r "$MMDB_FILE" ]; then
    echo "[ERROR] GeoIP database missing or unreadable: $MMDB_FILE" >&2
    exit 1
fi

if ! touch "$PRE_PENDING_FILE" "$BLOCKED_FILE" 2>/dev/null; then
    echo "[ERROR] Cannot create or access output files." >&2
    exit 1
fi

# ==============================================================================
# DOWNLOAD REMOTE CONFIGURATION
# ==============================================================================

echo "[INFO] Downloading geographic configuration from GitHub..."

if ! curl -fsSL --connect-timeout 10 --max-time 30 \
    "$CONFIG_URL" -o "$CONFIG_TMP"; then
    rm -f "$CONFIG_TMP"
    echo "[ERROR] GitHub configuration download failed. Exiting." >&2
    exit 1
fi

# The current GitHub file has four blank-line-separated sections:
# Section 1: Allowed cities
# Section 2: Allowed state ISO codes
# Section 3: Additional state names
# Section 4: Allowed country ISO codes

SECTION_COUNT=$(awk '
    /^[[:space:]]*$/ {
        if (count > 0) {
            sections++
            count = 0
        }
        next
    }
    {
        count++
    }
    END {
        if (count > 0) sections++
        print sections
    }
' "$CONFIG_TMP")

if [ "$SECTION_COUNT" -lt 4 ]; then
    rm -f "$CONFIG_TMP"
    echo "[ERROR] GitHub configuration is incomplete (expected 4 sections)." >&2
    exit 1
fi

if ! grep -qx 'US' "$CONFIG_TMP"; then
    if ! awk '
        /^[[:space:]]*$/ { section++; next }
        section >= 3 {
            line = $0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line == "US") found = 1
        }
        END { exit(found ? 0 : 1) }
    ' "$CONFIG_TMP"; then
        rm -f "$CONFIG_TMP"
        echo "[ERROR] Remote configuration does not contain US." >&2
        exit 1
    fi
fi

if ! mv "$CONFIG_TMP" "$CONFIG_LIST"; then
    rm -f "$CONFIG_TMP"
    echo "[ERROR] Could not install downloaded configuration." >&2
    exit 1
fi

echo "[INFO] Geographic configuration updated successfully."

# ==============================================================================
# CONFIGURATION LOOKUP
# ==============================================================================

config_contains() {
    TARGET_SECTION=$1
    TARGET_VALUE=$2

    awk -v wanted_section="$TARGET_SECTION" -v value="$TARGET_VALUE" '
        BEGIN {
            section = 1
            found = 0
            value = tolower(value)
        }

        /^[[:space:]]*$/ {
            section++
            next
        }

        {
            line = $0
            sub(/#.*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

            if (section == wanted_section &&
                tolower(line) == value) {
                found = 1
                exit
            }
        }

        END {
            exit(found ? 0 : 1)
        }
    ' "$CONFIG_LIST"
}

# ==============================================================================
# DUPLICATE AND SUBNET CHECKS
# ==============================================================================

is_known() {
    KEY=$1

    # Accepted IPs are stored as exact IP lines.
    if grep -Fxq -- "$KEY" "$PRE_PENDING_FILE" 2>/dev/null; then
        return 0
    fi

    # Blocked entries are logged as "subnet | Note: ...".
    awk -v key="$KEY" '
        index($0, " | Note: ") {
            prefix = substr($0, 1, index($0, " | Note: ") - 1)
            if (prefix == key) {
                found = 1
                exit
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$BLOCKED_FILE" 2>/dev/null
}

# ==============================================================================
# STRICT IPv4 VALIDATION
# ==============================================================================

is_valid_ipv4() {
    awk -F '.' '
        NF != 4 { exit 1 }

        {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^[0-9]+$/ || length($i) > 3 ||
                    ($i + 0) > 255) {
                    exit 1
                }
            }
        }

        END {
            if (NF != 4) exit 1
        }
    ' <<EOF
$1
EOF
}

# ==============================================================================
# LIVE PROCESSING
# ==============================================================================

tail -F -n +1 "$DUMP_FILE" 2>/dev/null |
while IFS= read -r RAW_IP; do

    [ -z "$RAW_IP" ] && continue

    SERVER_IP=$(printf '%s' "$RAW_IP" | tr -d '[:space:]\r')
    [ -z "$SERVER_IP" ] && continue

    if ! is_valid_ipv4 "$SERVER_IP"; then
        echo "[WARNING] Invalid IPv4 rejected: $SERVER_IP" >&2
        continue
    fi

    SUBNET_24=$(printf '%s\n' "$SERVER_IP" |
        sed 's/\.[0-9]*$/.0\/24/')

    # Skip already accepted IPs or already blocked /24 subnets.
    is_known "$SERVER_IP" && continue
    is_known "$SUBNET_24" && continue

    # ======================================================================
    # TIER 1: COUNTRY
    # Country ISO code must exist in GitHub section 4.
    # ======================================================================

    COUNTRY=$(
        mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" \
            country iso_code 2>/dev/null |
        grep -oE '"[A-Z]{2}"' |
        tr -d '"' |
        head -n 1
    )

    if [ -z "$COUNTRY" ] || ! config_contains 4 "$COUNTRY"; then
        [ -z "$COUNTRY" ] && COUNTRY="BLANK"

        printf '%s | Note: [Tier 1 Blocked - Country] (%s)\n' \
            "$SUBNET_24" "$COUNTRY" >> "$BLOCKED_FILE"

        continue
    fi

    # ======================================================================
    # TIER 2: STATE
    # Accept an exact ISO code from section 2 or state name from section 3.
    # ======================================================================

    REGION=$(
        mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" \
            subdivisions 0 iso_code 2>/dev/null |
        grep -oE '"[A-Z]{2}"' |
        tr -d '"' |
        head -n 1
    )

    REGION_NAME=$(
        mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" \
            subdivisions 0 names en 2>/dev/null |
        grep -oE '"[^"]+"' |
        tr -d '"' |
        head -n 1
    )

    STATE_ALLOWED=0

    if [ -n "$REGION" ] && config_contains 2 "$REGION"; then
        STATE_ALLOWED=1
    elif [ -n "$REGION_NAME" ] && config_contains 3 "$REGION_NAME"; then
        STATE_ALLOWED=1
    fi

    if [ "$STATE_ALLOWED" -ne 1 ]; then
        [ -z "$REGION" ] && REGION="BLANK"

        printf '%s | Note: [Tier 2 Blocked - State] (%s, %s)\n' \
            "$SUBNET_24" "$REGION" "${REGION_NAME:-Unknown}" \
            >> "$BLOCKED_FILE"

        continue
    fi

    # ======================================================================
    # TIER 3: CITY
    # City must match GitHub section 1, case-insensitively.
    # ======================================================================

    CITY=$(
        mmdblookup --file "$MMDB_FILE" --ip "$SERVER_IP" \
            city names en 2>/dev/null |
        grep -oE '"[^"]+"' |
        tr -d '"' |
        head -n 1
    )

    CITY=$(printf '%s' "$CITY" |
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [ -z "$CITY" ] || [ "$CITY" = "UnknownCity" ]; then
        printf '%s | Note: [Tier 3 Blocked - Unknown City] (%s)\n' \
            "$SUBNET_24" "$REGION" >> "$BLOCKED_FILE"

        continue
    fi

    if ! config_contains 1 "$CITY"; then
        printf '%s | Note: [Tier 3 Blocked - Disallowed City] (%s, %s)\n' \
            "$SUBNET_24" "$CITY" "$REGION" >> "$BLOCKED_FILE"

        continue
    fi

    # ======================================================================
    # PASS
    # ======================================================================

    if ! grep -Fxq -- "$SERVER_IP" "$PRE_PENDING_FILE" 2>/dev/null; then
        if printf '%s\n' "$SERVER_IP" >> "$PRE_PENDING_FILE"; then
            echo "[PASS] $SERVER_IP | $CITY, ${REGION_NAME:-$REGION}, $COUNTRY"
        else
            echo "[ERROR] Could not write accepted IP: $SERVER_IP" >&2
        fi
    fi

done

echo "[INFO] Filtration pipeline stopped."
