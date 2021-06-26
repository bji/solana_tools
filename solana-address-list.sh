#!/bin/bash

# Generate a yaml address list mapping vote account pubkeys and
# validator id pubkeys to the corresponding name of the validator.
# Emits the mappings as a list on stdout.
#
# Usage:
#   solana-address-list.sh [-j <json_rcp_endpoint>]
# 
#       <json_rcp_endpoint> is the URL of the RPC endpoint to query.  Default
#           is https://api.mainnet-beta.solana.com

function die ()
{
    if [ -n "$1" ]; then
        echo "$1"
    fi

    exit -1
}


function required ()
{
    which $1 1>/dev/null 2>/dev/null || die "ERROR: $1 required, but not found"
}


# Check for required programs
required solana
required base64
required jq
required curl


# Default values
RPC=https://api.mainnet-beta.solana.com


# Parse args
while [ $# -gt 0 ]; do

    case "$1" in
        -j)
            shift
            if [ $# = 0 ]; then
                die "ERROR: -j requires an argument"
            fi
            RPC=$1
        ;;
        *)
            die "ERROR: $1 is not a known argument"
        ;;
    esac
    
    shift
done


# map from validator_pubkey to name
declare -A validator_map

for word in $(solana --output=json validator-info get | \
                  jq -r '( .[] | select(.info.name != "") | .identityPubkey + "=" + ( .info.name | @base64 ))'); do
    key=$(echo "$word" | cut -d = -f 1)
    name=$(echo "$word" | cut -d = -f 2- | base64 -d)
    validator_map[$key]=$name
    echo "$key: \"$name\""
done

# map from vote_pubkey to name
for word in $(curl -s $RPC -X POST -H "Content-Type: application/json" \
                   -d '{"jsonrpc":"2.0","id":1, "method":"getVoteAccounts"}' | \
                  jq -r '.result.current | .[] | .votePubkey + "=" + .nodePubkey'); do
    key=$(echo "$word" | cut -d = -f 1)
    value=$(echo "$word" | cut -d = -f 2)
    name="${validator_map[$value]}"
    if [ -n "$name" ]; then
        echo "$key: \"$name\""
    fi
done
