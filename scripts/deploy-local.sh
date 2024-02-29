
#Pull Internet Identity as a dependencies from the mainnet and deploy locally.
dfx deps pull
dfx deps init --argument '(null)' internet-identity
dfx deps deploy

#Deploy Backend Canister
dfx deploy cycle-reserve --specified-id br5f7-7uaaa-aaaaa-qaaca-cai
dfx deploy test-cycle-pool --specified-id bw4dl-smaaa-aaaaa-qaacq-cai
