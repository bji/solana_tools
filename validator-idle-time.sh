#!/bin/bash

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

EPOCH_DETAILS=$(solana epoch-info)

EPOCH_CURRENT_SLOT=$(echo "$EPOCH_DETAILS" | grep ^Slot: | awk '{ print $2 }')
EPOCH_COMPLETED_SLOTS=$(echo "$EPOCH_DETAILS" | grep "^Epoch Completed Slots:" | awk '{ print $4 }' | cut -d '/' -f 1)
EPOCH_SLOT_COUNT=$(echo "$EPOCH_DETAILS" | grep "^Epoch Completed Slots:" | awk '{ print $4 }' | cut -d '/' -f 2)

EPOCH_FIRST_SLOT=$(($EPOCH_CURRENT_SLOT-$EPOCH_COMPLETED_SLOTS))
EPOCH_LAST_SLOT=$(($EPOCH_FIRST_SLOT+$EPOCH_SLOT_COUNT-1))

FIRST_LEADER_SLOT=
PREVIOUS_LEADER_SLOT=

function show_leader_range ()
{
    if [ -n "$PREVIOUS_LEADER_SLOT" ]; then
	SLOTS=$(($PREVIOUS_LEADER_SLOT-$FIRST_LEADER_SLOT+1))
	SECS=$(echo "$SECONDS_PER_SLOT $SLOTS * p" | dc)
	printf "Lead    $FIRST_LEADER_SLOT-$PREVIOUS_LEADER_SLOT  %-12s $(duration $SECS)\n" "$SLOTS slots"
    fi
}    

function show_non_leader_range ()
{
    if [ -z "$PREVIOUS_LEADER_SLOT" ]; then
	# No previous leader slot, so we're looking at the very first range of
	# non-leader slots of the epoch
	FIRST_NON_LEADER_SLOT=$EPOCH_FIRST_SLOT
    else
	# There was a previous leader slot group, so the non-leader slots
	# immediately follow it
	FIRST_NON_LEADER_SLOT=$(($PREVIOUS_LEADER_SLOT+1))
    fi
    SLOTS=$(($NEXT_LEADER_SLOT-$FIRST_NON_LEADER_SLOT))
    if [ $SLOTS -gt 0 ]; then
	SECS=$(echo "$SECONDS_PER_SLOT $SLOTS * p" | dc)
	printf "        $FIRST_NON_LEADER_SLOT-$(($NEXT_LEADER_SLOT-1))  %-12s $(duration $SECS)\n" "$SLOTS slots"
    fi
}

for NEXT_LEADER_SLOT in $(solana leader-schedule --no-address-labels | grep $VALIDATOR_IDENTITY | awk '{ print $1 }'); do
    # If there was a previous leader slot and the current leader slot is right after it,
    # then continue building the current leader slot range
    if [ -n "$PREVIOUS_LEADER_SLOT" -a \
	    $NEXT_LEADER_SLOT -eq $(($PREVIOUS_LEADER_SLOT+1)) ]; then
	PREVIOUS_LEADER_SLOT=$NEXT_LEADER_SLOT
	# Else this is a new leader slot range
    else
	# Maybe there was a previous leader slot range; if so, show it
	show_leader_range
	
	# Maybe there was a previous non-leader slot range; if so, show it
	show_non_leader_range
	
	# Beginning new leader slot range
	FIRST_LEADER_SLOT=$NEXT_LEADER_SLOT
	PREVIOUS_LEADER_SLOT=$NEXT_LEADER_SLOT
    fi
done

# Show the last leader range.
show_leader_range

# Show the last non-leader range.  Pretend that there is a leader slot immediately
# following the end of epoch
NEXT_LEADER_SLOT=$(($EPOCH_LAST_SLOT+1))

show_non_leader_range
