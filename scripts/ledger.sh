#!/usr/bin/env bash

# The archive controller
dfx identity new archive_controller

export ARCHIVE_CONTROLLER=$(dfx identity get-principal --identity archive_controller)

# canister id of stable coin minter as minting account
export MINTER_ACCOUNT=$(dfx canister id stablecoin_minter)

TOKEN_NAME="DoxaDollar"
TOKEN_SYMBOL="DD"

PRE_MINTED_TOKENS=0
TRANSFER_FEE=1_000

TRIGGER_THRESHOLD=2000
NUM_OF_BLOCK_TO_ARCHIVE=1000
CYCLE_FOR_ARCHIVE_CREATION=10000000000000
FEATURE_FLAGS=true

dfx deploy icrc1_ledger  --argument "(variant {Init = 
record {
     token_symbol = \"${TOKEN_SYMBOL}\";
     token_name = \"${TOKEN_NAME}\";
     minting_account = record { owner = principal \"${MINTER_ACCOUNT}\" };
     transfer_fee = ${TRANSFER_FEE};
     metadata = vec {};
     feature_flags = opt record{icrc2 = ${FEATURE_FLAGS}};
     initial_balances = vec { record { record { owner = principal \"${MINTER_ACCOUNT}\"; }; ${PRE_MINTED_TOKENS}; }; };
     archive_options = record {
         num_blocks_to_archive = ${NUM_OF_BLOCK_TO_ARCHIVE};
         trigger_threshold = ${TRIGGER_THRESHOLD};
         controller_id = principal \"${ARCHIVE_CONTROLLER}\";
         cycles_for_archive_creation = opt ${CYCLE_FOR_ARCHIVE_CREATION};
     };
 }
})"