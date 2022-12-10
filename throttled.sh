#!/bin/bash
while true; do
    throttled=$(vcgencmd get_throttled)
    echo "$(date):$throttled" >>/home/ubuntu/throttled.log
    if [ "$throttled" != "throttled=0x0" ]; then
        echo "throttled!!!"
    fi
    sleep 0.5
done
