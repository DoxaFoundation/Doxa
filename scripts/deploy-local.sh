
#Pull Internet Identity as a dependencies from the mainnet and deploy locally.
dfx deps pull
dfx deps init --argument '(null)' internet-identity
dfx deps deploy

########################### Deploy local ICP ledger canister ###########################
if ! dfx identity list | grep -q minter; then
    # If minter is not found, run the command
    dfx identity new minter
fi

export MINTER_ACCOUNT_ID=$(dfx ledger account-id --identity minter)
export DEFAULT_ACCOUNT_ID=$(dfx ledger account-id --identity default)

dfx deploy --specified-id ryjl3-tyaaa-aaaaa-aaaba-cai icp-ledger --argument "
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

#Deploy Backend Canister
dfx deploy cycle-reserve --specified-id br5f7-7uaaa-aaaaa-qaaca-cai
dfx deploy test-cycle-pool --specified-id bw4dl-smaaa-aaaaa-qaacq-cai
