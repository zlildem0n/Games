# Remote geographic configuration
CONFIG_URL="https://raw.githubusercontent.com/zlildem0n/Games/main/COD_States"
CONFIG_CACHE="/root/COD_States"
CONFIG_TMP="/root/COD_States.tmp"

if ! command -v curl >/dev/null 2>&1; then
    echo "[ERROR] curl is required to download geographic configuration." >&2
    exit 1
fi

if ! curl -fsSL --connect-timeout 10 --max-time 30 \
    "$CONFIG_URL" -o "$CONFIG_TMP"; then
    rm -f "$CONFIG_TMP"
    echo "[ERROR] Could not download COD_States. Refusing to process IPs." >&2
    exit 1
fi

# Require all three nonempty sections before replacing the cache.
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

if [ "$SECTION_COUNT" -lt 3 ]; then
    rm -f "$CONFIG_TMP"
    echo "[ERROR] Remote configuration has fewer than 3 sections." >&2
    exit 1
fi

if ! mv "$CONFIG_TMP" "$CONFIG_CACHE"; then
    rm -f "$CONFIG_TMP"
    echo "[ERROR] Cannot install downloaded configuration." >&2
    exit 1
fi

# Section 1: cities; Section 2: states; Section 3: countries.
config_contains() {
    SECTION=$1
    VALUE=$2

    awk -v section="$SECTION" -v value="$VALUE" '
        BEGIN { IGNORECASE = 1 }
        /^[[:space:]]*$/ { current++; next }
        current == section - 1 {
            line = $0
            sub(/#.*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (tolower(line) == tolower(value)) found = 1
        }
        END { exit(found ? 0 : 1) }
    ' "$CONFIG_CACHE"
}
