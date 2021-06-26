#!/bin/bash

# Read standard input, replace all occurrences of any Solana validator
# vote account pubkey or validator id pubkey with the validator name

# Cache this information in a file that can be re-used so that the data
# does not have to be loaded again

# Usage:
#   solana-dekey.sh [-j <json_rcp_endpoint>] [-c <cache_file>] < input
#
#       <json_rcp_endpoint> is the URL of the RPC endpoint to query.  Only
#           used if the cache file is not present and data must be fetched
#           from RPC.  Defaults is https://api.mainnet-beta.solana.com
#
#       <cache_file> is the name of the cache file to use to store vote
#           account info.  It will be re-used if it is present, otherwise
#           it will be re-generated.  Default is ./solana-dekey.cache


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


function make_string ()
{
    str="$1"
    len=$2

    for i in $(seq 1 $(($len - ${#str}))); do
        str+="\\ "
    done

    echo "$str"
}


# Check for required programs
required solana
required base64
required jq
required curl


# map from vote_pubkey to name
declare -A vote_map


# map from validator_pubkey to name
declare -A validator_map


function load_cache ()
{
    local cache_file=$1
    local reading_validator_map=false
    
    while read key; do
        keylen=$(echo -n "$key" | wc -c)
        if [ "$reading_validator_map" = "true" ]; then
            read value
            name=${vote_map[$value]}
            if [ -n "$name" ]; then
                validator_map[$key]=$(make_string "$name" $keylen)
            fi
        elif [ "$key" = "-" ]; then
            reading_validator_map=true
        else
            read value
            name=$(echo -n "$value" | base64 -d -)
            vote_map[$key]=$(make_string "$name" $keylen)
        fi
    done < "$cache_file"
}


function build_cache ()
{
    local cache_file=$1
    local rcp=$2

    # Load validator info, which maps vote account pubkey to name
    # The easiest way to do this is with the solana command, which
    # knows how to read and parse validator info program data

    for word in $(solana --output=json validator-info get | \
                      jq -r '( .[] | select(.info.name != "") | .identityPubkey + " " + ( .info.name | @base64 ))'); do
        echo "$word"
    done > $cache_file

    echo "-" >> $cache_file

    # Load a validator account to vote account mapping.  This is best
    # achieved with curl
    for word in $(curl -s $RPC -X POST -H "Content-Type: application/json" \
                       -d '{"jsonrpc":"2.0","id":1, "method":"getVoteAccounts"}' | \
                      jq -r '.result.current | .[] | .nodePubkey + "=" + .votePubkey'); do
        key=$(echo "$word" | cut -d = -f 2)
        value=$(echo "$word" | cut -d = -f 1)
        echo "$key" >> $cache_file
        echo "$value" >> $cache_file
    done
}


# Default values
RPC=https://api.mainnet-beta.solana.com
CACHE_FILE=./solana-dekey.cache

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
        -c)
            shift
            if [ $# = 0 ]; then
                die "ERROR: -c requires an argument"
            fi
            CACHE_FILE=$1
        ;;
        *)
            die "ERROR: $1 is not a known argument"
        ;;
    esac
    
    shift
done


if [ \! -e "$CACHE_FILE" ]; then
    build_cache "$CACHE_FILE" "$RPC"
fi
load_cache "$CACHE_FILE"


# Now compose a sed command to do the substitution
sed_cmd="sed"

for key in ${!vote_map[@]}; do
    # Sanitize name for sed
    value=$(echo -n "${vote_map[$key]}" | sed -e 's/[\/&]/\\&/g')
    sed_cmd+=" -e \"s/${key}/${value}/g\""
done

for key in ${!validator_map[@]}; do
    # Sanitize name for sed
    value=$(echo -n "${validator_map[$key]}" | sed -e 's/[\/&]/\\&/g')
    sed_cmd+=" -e \"s/${key}/${value}/g\""
done

eval $sed_cmd
