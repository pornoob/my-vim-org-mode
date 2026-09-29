#!/bin/sh
# Run the Vader test suite (or the .vader files given as arguments) in a clean
# headless Vim with only this plugin loaded. Vader is fetched into tests/.vader
# on first use. Exit status is Vader's: non-zero on any failure.
cd "$(dirname "$0")/.." || exit 1
if [ ! -d tests/.vader ]; then
  git clone --quiet --depth 1 https://github.com/junegunn/vader.vim tests/.vader || exit 1
fi
[ $# -eq 0 ] && set -- 'tests/*.vader'
log=$(mktemp)
timeout 120 vim -N -u tests/vimrc -i NONE --not-a-term "+Vader! $*" </dev/null >"$log" 2>&1
status=$?
# Keep Vader's report only: drop its :version banner and terminal codes
sed 's/\x1b\[[0-9;?>=]*[a-zA-Z]//g; s/\x1b[=>]//g' "$log" | awk '/Starting Vader/ { p = 1 } p'
if [ $status -eq 124 ]; then
  echo "Timed out (a test is probably waiting for input)"
elif ! grep -q '^Success/Total' "$log"; then
  echo "Vim quit before Vader finished (a prompt read EOF?)"
  status=1
fi
rm -f "$log"
exit $status
