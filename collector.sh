#!/bin/sh
# vcgencmd textfile collector for node_exporter.
# Writes raspi.prom to the shared textfile_collector directory every INTERVAL
# seconds via an atomic rename (.tmp -> final), which is what node_exporter's
# textfile collector requires to avoid reading a half-written file.

set -eu

OUT="${OUTPUT_FILE:-/var/lib/node_exporter/textfile_collector/raspi.prom}"
INTERVAL="${INTERVAL_SECONDS:-30}"
TMP="${OUT}.tmp"

# Parse `vcgencmd measure_temp` output of the form `temp=NN.N'C`.
parse_temp() {
    # shellcheck disable=SC2001
    echo "$1" | sed -e "s/temp=//" -e "s/'C$//"
}

# Parse `vcgencmd measure_volts X` output of the form `volt=N.NNNNV`.
parse_volt() {
    # shellcheck disable=SC2001
    echo "$1" | sed -e "s/volt=//" -e "s/V$//"
}

# Parse `vcgencmd measure_clock X` output of the form `frequency(N)=NNNNNNNNNN`.
parse_clock() {
    # shellcheck disable=SC2001
    echo "$1" | sed -e "s/frequency([0-9]*)=//"
}

# Extract a specific bit (0/1) from a hex bitmask. $1 = decimal mask, $2 = bit index.
bit() {
    mask="$1"
    idx="$2"
    echo $(( (mask >> idx) & 1 ))
}

write_block() {
    name="$1"
    help="$2"
    value="$3"
    {
        printf '# HELP %s %s\n' "$name" "$help"
        printf '# TYPE %s gauge\n' "$name"
        printf '%s %s\n' "$name" "$value"
    } >> "$TMP"
}

while true; do
    : > "$TMP"

    # SoC temperature.
    if temp_raw=$(vcgencmd measure_temp 2>/dev/null); then
        write_block rpi_temp_soc_celsius "Raspberry Pi SoC temperature in degrees Celsius." "$(parse_temp "$temp_raw")"
    fi

    # PMIC temperature (Pi 5 only — silently skip on Pi 4 and earlier).
    if pmic_raw=$(vcgencmd measure_temp pmic 2>/dev/null); then
        write_block rpi_temp_pmic_celsius "Raspberry Pi 5 PMIC temperature in degrees Celsius." "$(parse_temp "$pmic_raw")"
    fi

    # Throttling bitmask. Format: `throttled=0xN`. Bits:
    #   0  under-voltage now            16 under-voltage since boot
    #   1  arm freq capped now          17 arm freq capped since boot
    #   2  throttled now                18 throttled since boot
    #   3  soft temp limit now          19 soft temp limit since boot
    if thr_raw=$(vcgencmd get_throttled 2>/dev/null); then
        # shellcheck disable=SC2001
        hex=$(echo "$thr_raw" | sed -e "s/throttled=//")
        dec=$(printf '%d' "$hex")
        write_block rpi_throttled_bitmask "Raw vcgencmd throttled bitmask as a decimal integer." "$dec"
        write_block rpi_throttled_undervoltage_now      "1 if SoC is currently under-voltage."                     "$(bit "$dec" 0)"
        write_block rpi_throttled_arm_freq_capped_now   "1 if ARM frequency is currently being capped."             "$(bit "$dec" 1)"
        write_block rpi_throttled_now                   "1 if SoC is currently throttling (under-volt or thermal)." "$(bit "$dec" 2)"
        write_block rpi_throttled_soft_temp_limit_now   "1 if the soft temperature limit is currently active."      "$(bit "$dec" 3)"
        write_block rpi_throttled_undervoltage_since_boot      "1 if an under-voltage event has occurred since boot."             "$(bit "$dec" 16)"
        write_block rpi_throttled_arm_freq_capped_since_boot   "1 if ARM frequency capping has occurred since boot."              "$(bit "$dec" 17)"
        write_block rpi_throttled_since_boot                   "1 if throttling has occurred since boot."                          "$(bit "$dec" 18)"
        write_block rpi_throttled_soft_temp_limit_since_boot   "1 if the soft temperature limit has been hit since boot."          "$(bit "$dec" 19)"
    fi

    # Voltages.
    if v=$(vcgencmd measure_volts core     2>/dev/null); then write_block rpi_volt_core_volts       "SoC core voltage in volts."        "$(parse_volt "$v")"; fi
    if v=$(vcgencmd measure_volts sdram_c  2>/dev/null); then write_block rpi_volt_sdram_core_volts "SDRAM core voltage in volts."      "$(parse_volt "$v")"; fi
    if v=$(vcgencmd measure_volts sdram_i  2>/dev/null); then write_block rpi_volt_sdram_io_volts   "SDRAM I/O voltage in volts."       "$(parse_volt "$v")"; fi
    if v=$(vcgencmd measure_volts sdram_p  2>/dev/null); then write_block rpi_volt_sdram_phy_volts  "SDRAM PHY voltage in volts."       "$(parse_volt "$v")"; fi

    # Clocks (Hz).
    if c=$(vcgencmd measure_clock arm   2>/dev/null); then write_block rpi_clock_arm_hertz   "ARM core clock frequency in Hz."   "$(parse_clock "$c")"; fi
    if c=$(vcgencmd measure_clock gpu   2>/dev/null); then write_block rpi_clock_gpu_hertz   "GPU/VideoCore clock frequency in Hz." "$(parse_clock "$c")"; fi
    if c=$(vcgencmd measure_clock emmc  2>/dev/null); then write_block rpi_clock_emmc_hertz  "eMMC/SD clock frequency in Hz."    "$(parse_clock "$c")"; fi

    # Liveness — drives the staleness alert.
    write_block rpi_collector_last_success_timestamp_seconds \
        "Unix timestamp of the last successful collector loop." \
        "$(date +%s)"

    # Atomic publish.
    mv "$TMP" "$OUT"

    sleep "$INTERVAL"
done
