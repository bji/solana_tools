#!/bin/sh

# Prints the leader and idle times in slots (and estimated time duration) of a validator
# Usage: validator-idle-time <VALIDATOR_IDENTITY> [<SECONDS_PER_SLOT>]
#   <SECONDS_PER_SLOT> is optional, if not provided, 0.55 is used

if [ $# -lt 1 -o $# -gt 2 ]; then
    echo "Usage: validator-idle-time <VALIDATOR_IDENTITY> [<SECONDS_PER_SLOT>]"
    echo "    <SECONDS_PER_SLOT> is optional, if not provided, 0.55 is used"
    exit -1
fi

VALIDATOR_IDENTITY=$1

if [ -n "$2" ]; then
    SECONDS_PER_SLOT=$2
else
    SECONDS_PER_SLOT=0.55
fi

function duration ()
{
    local T=${1%.*}
    local F=$(echo "$1 $T - p" | dc)
    local D=$((T/60/60/24))
    local H=$((T/60/60%24))
    local M=$((T/60%60))
    local S=$((T%60))
    
    (($D > 0)) && printf '%d day%s ' $D $((($D > 1)) && echo s)
    (($H > 0)) && printf '%d hour%s ' $H $((($H > 1)) && echo s)
    (($M > 0)) && printf '%d minute%s ' $M $((($M > 1)) && echo s)

    S=$(echo "$S $F + p" | dc)
    printf '%0.2f seconds' $S
}


EPOCH=$(solana epoch-info | grep ^Epoch: | awk '{ print $2 }')

SLOT=$(($EPOCH*432000-1))

FIRST_LEADER_SLOT=

solana leader-schedule --no-address-labels | grep $VALIDATOR_IDENTITY | awk '{ print $1 }' |
    while read NEXT_SLOT; do
        if [ $NEXT_SLOT -eq $((SLOT+1)) ]; then
            if [ -z "$FIRST_LEADER_SLOT" ]; then
                FIRST_LEADER_SLOT=$SLOT
            fi
            SLOT=$NEXT_SLOT
        else
            if [ -n "$FIRST_LEADER_SLOT" ]; then
                SLOTS=$(($SLOT-$FIRST_LEADER_SLOT+1))
                SECS=$(echo "$SECONDS_PER_SLOT $SLOTS * p" | dc)
                printf "Lead    $FIRST_LEADER_SLOT-$SLOT  %-12s $(duration $SECS)\n" "$SLOTS slots"
                FIRST_LEADER_SLOT=
            fi
            SLOTS=$(($NEXT_SLOT-$SLOT-1))
            SECS=$(echo "$SECONDS_PER_SLOT $SLOTS * p" | dc)
            printf "        $(($SLOT+1))-$(($NEXT_SLOT-1))  %-12s $(duration $SECS)\n" "$SLOTS slots"
            SLOT=$NEXT_SLOT
        fi
    done
