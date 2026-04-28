#!/bin/bash
# Generate the centered READY FOR INPUT banner at terminal width
# Usage: bash generate-banner.sh [width]

RAW="${1:-$(stty size < /dev/pts/0 2>/dev/null | awk '{print $2}')}"
RAW="${RAW:-90}"
REDUCE=$(( RAW / 10 ))
(( REDUCE < 2 )) && REDUCE=2
W=$(( RAW - REDUCE ))
CORE=39
(( W < CORE )) && W=$CORE
PAD=$(( W - CORE ))
LEFT=$(( PAD / 2 ))
RIGHT=$(( PAD - LEFT ))

repeat() {
  local pat="$1" n="$2" out=""
  while (( ${#out} < n )); do out+="$pat"; done
  printf '%s' "${out:0:$n}"
}

BL=$(repeat '█▒░▒' "$LEFT")
BR=$(repeat '▒░▒█' "$RIGHT")
SL=$(repeat '▒█' "$LEFT")
SR=$(repeat '▒█' "$RIGHT")
TL=$(repeat '░▒█▒' "$LEFT")
TR=$(repeat '░▒█▒' "$RIGHT")

echo "${BL}██▒░▒█▒░▒█▒░▒█▒░▒█▒░▒█▒░▒█▒░▒█▒░▒█▒░▒██${BR}"
echo "${SL}██                                   ██${SR}"
echo "${TL}██      >>> READY FOR INPUT <<<      ██${TR}"
echo "${SL}██                                   ██${SR}"
echo "${BL}██▒░▒█▒░▒█▒░▒█▒░▒█▒░▒█▒░▒█▒░▒█▒░▒█▒░▒██${BR}"
