#!/bin/bash
# EXIF Stats Script for Commander Photo Importer
# Usage: exif_stats.sh <file_list.txt> [output_dir]
# Requires: exiftool (brew install exiftool)

FILE_LIST="${1:-last_import_files.txt}"
OUTPUT_DIR="${2:-$HOME/Documents/exif_report_final}"

mkdir -p "$OUTPUT_DIR"

if ! command -v exiftool &> /dev/null; then
    echo "ERROR: exiftool not found. Install with: brew install exiftool"
    exit 1
fi

if [ ! -f "$FILE_LIST" ]; then
    echo "ERROR: File list not found: $FILE_LIST"
    exit 1
fi

TOTAL=$(wc -l < "$FILE_LIST" | tr -d ' ')
echo "Analyzing $TOTAL files..."

# Generate JSON report
exiftool -json -LensModel -Make -Model -ShutterSpeed -ExposureTime -FocalLength -ISO -@ "$FILE_LIST" > "$OUTPUT_DIR/exif_raw.json" 2>/dev/null

# Top Lenses
echo ""
echo "=== TOP LENSES ==="
exiftool -LensModel -@ "$FILE_LIST" 2>/dev/null | grep "^Lens Model" | sed 's/Lens Model *: *//' | sort | uniq -c | sort -rn | head -3 | while read count lens; do
    echo "  $count x $lens"
done

# Most Used Camera
echo ""
echo "=== MOST USED CAMERA ==="
exiftool -Make -Model -@ "$FILE_LIST" 2>/dev/null | paste - - | sed 's/Make *: *//;s/Camera Model Name *: *//' | sort | uniq -c | sort -rn | head -1

# Top Shutter Speeds
echo ""
echo "=== TOP SHUTTER SPEEDS ==="
exiftool -ExposureTime -@ "$FILE_LIST" 2>/dev/null | grep "^Exposure Time" | sed 's/Exposure Time *: *//' | sort | uniq -c | sort -rn | head -5 | while read count speed; do
    echo "  $count x $speed"
done

echo ""
echo "Report saved to: $OUTPUT_DIR"
echo "Files analyzed: $TOTAL"
