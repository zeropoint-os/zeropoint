#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

_log_notice "Generating Memorable Hostname"

ADJECTIVES=(lantea praclarush ida dakara celestis sahal kheb velaneth norvaleth solkarush elenaris dracalon taloren asparush)
NOUNS=(taonas kaleth doran velas norin selan karoth lunas peron astra nareth luneth velon)

ADJ=${ADJECTIVES[$RANDOM % ${#ADJECTIVES[@]}]}
mark "adjective-selected"

NOUN=${NOUNS[$RANDOM % ${#NOUNS[@]}]}
mark "noun-selected"

HOSTNAME="zeropoint-$ADJ-$NOUN"
_log_notice "Generated hostname: $HOSTNAME"

echo "$HOSTNAME" > /etc/hostname
_log_notice "Updated /etc/hostname"
mark "hostname-file-updated"

# Apply the hostname change immediately
hostname "$HOSTNAME"
_log_notice "Applied hostname to running system"
mark "hostname-applied"

# Update /etc/hosts - add 127.0.1.1 entry if it doesn't exist, or update it if it does
if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
else
    echo -e "127.0.1.1\t$HOSTNAME" >> /etc/hosts
fi
_log_notice "Updated /etc/hosts"
mark "hosts-file-updated"

mark_done

_log_notice "Memorable Hostname Set"
