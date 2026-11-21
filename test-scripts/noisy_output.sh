#!/bin/zsh
# 5. Continuous heavy stdout and stderr output (tests /dev/null discard & zero memory buildup)
trap 'exit 0' TERM INT
i=0
while true; do
  i=$((i + 1))
  printf 'STDOUT line %d: %0100d\n' "$i" 0
  printf 'STDERR line %d: %0100d\n' "$i" 0 >&2
done
