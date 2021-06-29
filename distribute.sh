#!/bin/bash


# ----------------------------------------------------------------------------
# Path configuration ---------------------------------------------------------

# Replace the following with the path to your solana bin
SOLANA_BIN=YOUR_SOLANA_BIN

SOLANA=$SOLANA_BIN/solana

DC=/usr/bin/dc

# Replace the following with a path to your validator keypair file
VALIDATOR_KEYPAIR=YOUR_VALIDATOR_KEYPAIR.json

# If you want Discord announcements, set this path
DISCORD_ANNOUNCEMENT_SH=PATH_TO_DISCORD_ANNOUNCEMENT.sh


# ----------------------------------------------------------------------------
# Account configuration ------------------------------------------------------

# Replace the following with your validator account pubkey
VALIDATOR_ACCOUNT=YOUR_VALIDATOR_ACCOUNT_PUBKEY

# Replace the following with your vote account pubkey
VOTE_ACCOUNT=YOUR_VOTE_ACCOUNT_PUBKEY

# Replace the following with the solana account to distribute excess
# validator earnings to
DISTRIBUTION_ACCOUNT=YOUR_DISTRIBUTION_ACCOUNT_PUBKEY


# ----------------------------------------------------------------------------
# Financial configuration ----------------------------------------------------

# Minimum to keep in the Validator account
VALIDATOR_TARGET=20

# Minimum SOL to transact at one time (to prevent transaction fees from being
# an excessive percentage of the transacted amount)
MIN_TRANSACTION=1

# Minimum to leave in vote account
MIN_VOTE_BALANCE=1


# ----------------------------------------------------------------------------
# Globals --------------------------------------------------------------------

# Keep track of whether or not any transactions were done and only print
# remaining balances if so
TRANSACTED=


# ----------------------------------------------------------------------------
# Functions ------------------------------------------------------------------

function msg ()
{
    echo "$@"
    if [ -n "$DISCORD_ANNOUNCEMENT_SH" ]; then
        $DISCORD_ANNOUNCEMENT_SH "$@"
        # Must slow the validator output so as not to be rate limited
        sleep 1
    fi
}


function is-less-than ()
{
    LEFT=$(echo -n $1 | tr - _)
    RIGHT=$(echo -n $2 | tr - _)
    MIN_VALUE=$($DC -e "10 k $LEFT sa $RIGHT d la <a p")

    if [ "$MIN_VALUE" = "$2" ]; then
	return 1
    else
	return 0
    fi
}


function run-solana-cmd ()
{
    msg "solana $1"

    $SOLANA $1

    TRANSACTED=1
}

    
# ----------------------------------------------------------------------------
# Compute balances -----------------------------------------------------------

msg "**__$(date)__**"

# Determine total supply in validator
VALIDATOR_TOTAL=$($SOLANA balance $VALIDATOR_ACCOUNT | awk '{ print $1 }')

# Determine total supply of the vote account, but always leave at least 1
VOTE_TOTAL=$($SOLANA balance $VOTE_ACCOUNT | awk '{ print $1 }')

msg "Validator account: $VALIDATOR_ACCOUNT"
msg "Balance: $VALIDATOR_TOTAL SOL"
msg "Vote account: $VOTE_ACCOUNT"
msg "Balance: $VOTE_TOTAL SOL"

VOTE_AVAILABLE=$($DC -e "10 k $VOTE_TOTAL $MIN_VOTE_BALANCE - p")
if is-less-than $VOTE_AVAILABLE 0; then
    VOTE_AVAILABLE=0
fi


# ----------------------------------------------------------------------------
# Compute distribution to validator account ----------------------------------

# dc is really ridiculous and expects underscore for negation -- but produces
# minus for negation
TO_VALIDATOR=$($DC -e "10 $VALIDATOR_TARGET $VALIDATOR_TOTAL - p")
if is-less-than $TO_VALIDATOR 0; then
    TO_VALIDATOR=0
elif is-less-than $VOTE_AVAILABLE $TO_VALIDATOR; then
    TO_VALIDATOR=$VOTE_AVAILABLE
fi


# ----------------------------------------------------------------------------
# Top up validator -----------------------------------------------------------

if [ $TO_VALIDATOR = 0 ]; then
  msg "Validator account does not need topping up."    
elif is-less-than $TO_VALIDATOR $MIN_TRANSACTION; then
  msg "Not enough SOL in vote account to top up validator.  Skipping distribution."
else
  msg "**Sending $TO_VALIDATOR from vote account to validator account.**"

  run-solana-cmd "withdraw-from-vote-account -k $VALIDATOR_KEYPAIR --commitment finalized $VOTE_ACCOUNT $VALIDATOR_ACCOUNT $TO_VALIDATOR"
fi


# ----------------------------------------------------------------------------
# Distribute from validator --------------------------------------------------

# Turns out that block production pays more in rewards than voting uses in
# fees so the validator account can actually accumulate SOL and needs to be
# drained as well

VALIDATOR_TOTAL=$($DC -e "10 k $VALIDATOR_TOTAL $TO_VALIDATOR + p")
TO_DISTRIBUTE=$($DC -e "10 k $VALIDATOR_TOTAL $VALIDATOR_TARGET - p")

if is-less-than $TO_DISTRIBUTE $MIN_TRANSACTION; then
  msg "Skipping payout distribution."
else
  msg "**Sending $TO_DISTRIBUTE from validator account to $DISTRIBUTION_ACCOUNT**"

  run-solana-cmd "transfer -k $VALIDATOR_KEYPAIR --commitment finalized $DISTRIBUTION_ACCOUNT $TO_DISTRIBUTE"

fi


# ----------------------------------------------------------------------------
# Compute distribution to payout accounts ------------------------------------

TO_DISTRIBUTE=$($DC -e "10 k $VOTE_AVAILABLE $TO_VALIDATOR - p")


# ----------------------------------------------------------------------------
# Distribute -----------------------------------------------------------------

if is-less-than $TO_DISTRIBUTE $MIN_TRANSACTION; then
  msg "Skipping payout distribution."
else
  msg "**Sending $TO_DISTRIBUTE from vote account to $DISTRIBUTION_ACCOUNT**"

  run-solana-cmd "withdraw-from-vote-account -k $VALIDATOR_KEYPAIR --commitment finalized $VOTE_ACCOUNT $DISTRIBUTION_ACCOUNT $TO_DISTRIBUTE"
fi


# ----------------------------------------------------------------------------
# Final status ---------------------------------------------------------------

if [ -n "$TRANSACTED" ]; then
  msg "Validator account final balance: $($SOLANA balance $VALIDATOR_ACCOUNT)"
  msg "Vote account final balance: $($SOLANA balance $VOTE_ACCOUNT)"
fi
