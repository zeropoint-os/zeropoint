#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

logger -t zeropoint-hostname "=== Generating Memorable Hostname ==="

ADJECTIVES=(lantea praclarush ida dakara celestis sahal kheb velaneth norvaleth solkarush elenaris dracalon taloren asparush)
NOUNS=(taonas kaleth doran velas norin selan karoth lunas peron astra nareth luneth velon)

ADJ=${ADJECTIVES[$RANDOM % ${#ADJECTIVES[@]}]}
mark "adjective-selected"

NOUN=${NOUNS[$RANDOM % ${#NOUNS[@]}]}
mark "noun-selected"

HOSTNAME="zeropoint-$ADJ-$NOUN"
logger -t zeropoint-hostname "Generated hostname: $HOSTNAME"

echo "$HOSTNAME" > /etc/hostname
logger -t zeropoint-hostname "Updated /etc/hostname"
mark "hostname-file-updated"

# Apply the hostname change immediately
hostname "$HOSTNAME"
logger -t zeropoint-hostname "Applied hostname to running system"
mark "hostname-applied"

# Update /etc/hosts - add 127.0.1.1 entry if it doesn't exist, or update it if it does
if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
else
    echo -e "127.0.1.1\t$HOSTNAME" >> /etc/hosts
fi
logger -t zeropoint-hostname "Updated /etc/hosts"
mark "hosts-file-updated"

mark_done

logger -t zeropoint-hostname "=== Memorable Hostname Set ==="
