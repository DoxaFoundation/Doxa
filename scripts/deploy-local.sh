
#Pull Internet Identity as a dependencies from the mainnet and deploy locally.
dfx deps pull
dfx deps init --argument '(null)' internet-identity
dfx deps deploy

#Deploy Backend Canister
dfx deploy backend
