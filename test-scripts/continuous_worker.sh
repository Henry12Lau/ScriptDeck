#!/bin/zsh
# 1. Continuous running worker (stops cleanly on SIGTERM)
trap 'exit 0' TERM INT
while true; do
  /bin/sleep 1
done
