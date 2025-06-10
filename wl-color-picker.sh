#!/bin/bash
#
# License: MIT
#
# A script to easily pick a color on a wayland session by using:
# slurp to select the location, grim to get the pixel, convert
# to make the pixel a hex number and zenity to display a nice color
# selector dialog where the picked color can be tweaked further.
#
# The script was possible thanks to the useful information on:
# https://www.trst.co/simple-colour-picker-in-sway-wayland.html
# https://unix.stackexchange.com/questions/320070/is-there-a-colour-picker-that-works-with-wayland-or-xwayland/523805#523805
#

showhelp() {
    echo "A basic wlroots compatible color picker script."
    echo ""
    echo "Usage:"
    echo "  wl-color-picker [options]"
    echo ""
    echo "Options:"
    echo "  --dest DEST     Output destination: comma-separated list of 'stdout' and/or 'clipboard' (default: stdout)"
    echo "  -c, --copy      Also copy to clipboard (equivalent to --dest stdout,clipboard)"
    echo "  --picker        Show color picker dialog to adjust color before output"
    echo "  --notify        Show system notification with the color"
    echo "  -h, --help      Show this help message"
}

DEST="stdout"
USE_PICKER=0
USE_NOTIFY=0

while [ "$1" ]; do
    case $1 in
        '-h' | '--help' | 'help' | '?' )
            showhelp
            exit
            ;;
        '--dest' )
            shift
            DEST="$1"
            ;;
        '-c' | '--copy' )
            DEST="stdout,clipboard"
            ;;
        '--picker' )
            USE_PICKER=1
            ;;
        '--notify' )
            USE_NOTIFY=1
            ;;
        # Legacy support
        'clipboard' )
            DEST="clipboard"
            ;;
        '--no-notify' )
            USE_NOTIFY=0
            ;;
    esac

    shift
done

# Check if running under wayland.
if [ "$WAYLAND_DISPLAY" = "" ]; then
    zenity  --error --width 400 \
        --title "No wayland session found." \
        --text "This color picker must be run under a valid wayland session."

    exit 1
fi

# Get color position
position=$(slurp -b 00000000 -p)

# Sleep at least for a second to prevet issues with grim always
# returning improper color.
sleep 1

# Store the hex color value using graphicsmagick or imagemagick.
if command -v /usr/bin/gm &> /dev/null; then
    convert_cmd="/usr/bin/gm convert"
    color_field=1
elif command -v magick &> /dev/null; then
    convert_cmd="magick"
    color_field=4
else
    convert_cmd="convert"
    color_field=4
fi

color=$(grim -g "$position" -t png - \
    | $convert_cmd - -format '%[pixel:p{0,0}]' txt:- \
    | tail -n 1 \
    | if [ "$color_field" -eq 1 ]; then rev | cut -d ' ' -f 1 | rev; else cut -d ' ' -f 4; fi
)

final_color="$color"

# Show picker dialog if requested
if [ $USE_PICKER -eq 1 ]; then
    rgb_color=$(zenity --color-selection \
        --title="Adjust Color" \
        --color="${color}"
    )

    # Convert rgb color to hex if user didn't cancel
    if [ "$rgb_color" != "" ]; then
        hex_color="#"
        for value in $(echo "${rgb_color}" | grep -E -o -m1 '[0-9]+'); do
           hex_color="$hex_color$(printf "%.2x" $value)"
        done
        final_color="$hex_color"
    fi
fi

# Handle output destinations
IFS=',' read -ra DESTS <<< "$DEST"
for dest in "${DESTS[@]}"; do
    case "$dest" in
        "stdout")
            echo "$final_color"
            ;;
        "clipboard")
            echo "$final_color" | wl-copy -n
            ;;
        *)
            echo "Invalid destination: $dest" >&2
            exit 1
            ;;
    esac
done

# Show notification if requested
if [ $USE_NOTIFY -eq 1 ]; then
    if [[ "$DEST" == *"clipboard"* ]]; then
        notify-send "$final_color" "copied to clipboard"
    else
        notify-send "$final_color"
    fi
fi
