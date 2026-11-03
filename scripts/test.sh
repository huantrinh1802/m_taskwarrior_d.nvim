#!/bin/sh
# Run every lua/tests/test_*.lua in headless Neovim.
#   scripts/test.sh                      # all suites
#   scripts/test.sh lua/tests/test_x.lua # selected suites
#   COVERAGE=1 scripts/test.sh           # also record luacov stats and report
#   COVERAGE=1 COVERAGE_MIN=100 scripts/test.sh  # and fail below 100% lines
# Coverage needs luacov on LUA_PATH, e.g. `eval "$(luarocks --lua-version 5.1 path)"`.
cd "$(dirname "$0")/.." || exit 1

if [ "$#" -eq 0 ]; then
  set -- lua/tests/test_*.lua
fi

pre="lua _ = 0"
if [ "${COVERAGE:-0}" = 1 ]; then
  rm -f luacov.stats.out luacov.report.out
  pre="lua require('luacov')"
fi

status=0
for t in "$@"; do
  echo "== $t"
  # A suite that errors outside check() would leave headless Neovim waiting
  # for input, so turn any uncaught error into a non-zero exit.
  nvim --headless -u NONE -c "$pre" \
    -c "lua local ok, err = pcall(dofile, '$t'); if not ok then print(err); os.exit(2) end; os.exit(0)" \
    || status=1
done

if [ "${COVERAGE:-0}" = 1 ]; then
  nvim --headless -u NONE -c "lua require('luacov.reporter').report()" -c "qa!"
  sed -n '/^Summary/,$p' luacov.report.out
  # luacov only reports modules that were loaded; a module no suite requires
  # would otherwise slip past COVERAGE_MIN.
  for f in lua/m_taskwarrior_d/*.lua; do
    if ! grep -q "^$f " luacov.report.out; then
      echo "Not loaded by any suite: $f"
      status=1
    fi
  done
  if [ -n "${COVERAGE_MIN:-}" ]; then
    total=$(awk '/^Total/ { sub("%", "", $NF); print $NF }' luacov.report.out)
    if awk -v t="$total" -v m="$COVERAGE_MIN" 'BEGIN { exit !(t + 0 < m + 0) }'; then
      echo "Line coverage ${total}% is below ${COVERAGE_MIN}%"
      status=1
    fi
  fi
fi
exit "$status"
