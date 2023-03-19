#!/bin/bash

while true; do
    python3.10 whisperer.py $@
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        break
    else
        echo "Program exited with non-zero error code ($exit_code). Restarting..."
        sleep 1
    fi
done
