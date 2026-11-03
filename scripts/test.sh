#!/bin/sh
# Run every lua/tests/test_*.lua in headless Neovim.
#   scripts/test.sh                      # all suites
#   scripts/test.sh lua/tests/test_x.lua # selected suites
#   COVERAGE=1 scripts/test.sh           # also record luacov stats and report
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
fi
exit "$status"
