
#Pull Internet Identity as a dependencies from the mainnet and deploy locally.
dfx deps pull
dfx deps init --argument '(null)' internet-identity
dfx deps init exchange_rate_canister
dfx deps deploy 

########################################################################################
########################### Deploy local ICP ledger canister ###########################
########################################################################################

if ! dfx identity list | grep -q minter; then
    # If minter is not found, run the command
    dfx identity new minter
fi

export MINTER_ACCOUNT_ID=$(dfx ledger account-id --identity minter)
export DEFAULT_ACCOUNT_ID=$(dfx ledger account-id --identity default)

dfx deploy icp_ledger --specified-id ryjl3-tyaaa-aaaaa-aaaba-cai --argument "
  (variant {
    Init = record {
      minting_account = \"$MINTER_ACCOUNT_ID\";
      initial_values = vec {
        record {
          \"$DEFAULT_ACCOUNT_ID\";
          record {
            e8s = 10_000_000_000 : nat64;
          };
        };
      };
      send_whitelist = vec {};
      transfer_fee = opt record {
        e8s = 10_000 : nat64;
      };
      token_symbol = opt \"LICP\";
      token_name = opt \"Local ICP\";
    }
  })
"
######################################################################################
######################################################################################

#Deploy Cycle minting canister locally
dfx deploy cycle_minting_canister --specified-id rkp4c-7iaaa-aaaaa-aaaca-cai  --argument '(
  opt record { 
      ledger_canister_id = opt principal "ryjl3-tyaaa-aaaaa-aaaba-cai";
      governance_canister_id = opt principal "rrkah-fqaaa-aaaaa-aaaaq-cai";
      last_purged_notification = null;
      exchange_rate_canister = opt variant { 
        Set = principal "uf6dk-hyaaa-aaaaq-qaaaq-cai"
      };
      cycles_ledger_canister_id = opt principal "um5iw-rqaaa-aaaaq-qaaba-cai"; 
  })'

#################### Cycles Ledger Local ####################
dfx deploy cycles_ledger --specified-id um5iw-rqaaa-aaaaq-qaaba-cai --argument '(
  variant { Init= record { max_blocks_per_request = 1; index_id = null }}
)'

#Deploy Reserve Canister
dfx deploy cycle_reserve --with-cycles 1_000_000

# Creating Local USDx Ledger before deploying stablecoin_minter (stablecoin_minter is a dependency of usdx_ledger)
dfx canister create usdx_ledger --specified-id irorr-5aaaa-aaaak-qddsq-cai

# Creating Local stablecoin_minter , root_canister before deploying usdx_ledger (These are minteraccount and archivecontroller for usdx_ledger)
dfx canister create stablecoin_minter --specified-id iyn2n-liaaa-aaaak-qddta-cai
dfx canister create root_canister --specified-id iwpxf-qyaaa-aaaak-qddsa-cai

# Deploy USDx Ledger Locally
./scripts/deploy-local-usdx.sh


dfx canister create cycle_pool --specified-id i7m4z-gqaaa-aaaak-qddtq-cai
dfx deploy cycle_pool --argument '(principal "i7m4z-gqaaa-aaaak-qddtq-cai")'

dfx deploy stablecoin_minter

dfx deploy root_canister


