import CycleLedger "canister:cycles_ledger";
import IcpLedger "canister:icp_ledger";
import CycleReserve "canister:cycle_reserve";
import CMC "canister:cycle_minting_canister";
import USDx "canister:usdx_ledger";
import XRC "canister:exchange_rate_canister";

import Map "mo:map/Map";
import Vector "mo:vector";
import Result "mo:base/Result";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Float "mo:base/Float";
import Nat32 "mo:base/Nat32";
import Timer "mo:base/Timer";
import Utils "../Utils";

actor StablecoinMinter {
	type Result<T, E> = Result.Result<T, E>;
	type HashMap<K, V> = HashMap.HashMap<K, V>;
	type Time = Time.Time;
	type TimerId = Timer.TimerId;

	type CLBlockIndex = CycleLedger.BlockIndex;
	type IcpBlockIndex = IcpLedger.BlockIndex;
	type USDxBlockIndex = USDx.BlockIndex;

	type Account = { owner : Principal; subaccount : ?[Nat8] };
	type MintCoin = {
		#USDx;
	};
	type CyclesLedgerTransferTX = {
		fee : ?Int;
		phash : ?[Int];
		timestamp : Int;
		transaction : {
			amount : Int;
			from : [Blob];
			operation : Text;
			to : [Blob];
		};
	};

	type SubValue = {
		#Array : [Value];
		#Blob : [Nat8];
		#Int : Int;
		#Nat : Nat;
		#Nat64 : Nat64;
		#Text : Text;
	};

	type Value = {
		#Array : [Value];
		#Blob : [Nat8];
		#Int : Int;
		#Map : [(Text, Value)];
		#Nat : Nat;
		#Nat64 : Nat64;
		#Text : Text;
	};

	type NotifyError = {
		#AlreadyProcessed : { blockIndex : Nat };
		#InvalidTransaction : Text;
		#Other : { error_message : Text; error_code : Nat64 };

	};

	type NotifyMintWithCyclesLedgerTransferResult = Result<USDxBlockIndex, NotifyError>;
	type NotifyMintWithICPResult = Result<USDxBlockIndex, NotifyError>;

	type MintThroughCallError = {
		#NotEnoughCyclesAvailable : Text;
		#LedgerTransferError : Text;
	};
	type MintThroughCallResult = Result<USDxBlockIndex, MintThroughCallError>;

	type UpdateXdrUsdRateError = {
		error_time : Time;
		error : XRC.ExchangeRateError;
	};
	type UpdateXdrUsdRateResult = Result<(), UpdateXdrUsdRateError>;

	type XdrUsd = { rate : Float; timestamp : Nat64 };

	let { nhash; n64hash } = Map;

	// key = Notify cycles Ledger Tx BlockIndex ,  value = (Cycle Withdraw Tx BlockIndex, USDx mint Tx BlockIndex)
	private stable let processedMintRequestFromCylesLedgerTx = Map.new<CLBlockIndex, (CLBlockIndex, USDxBlockIndex)>();

	// key = Notify ICP Tx BlockIndex , value = (ICP to CMC Tx BlockIndex, USDx mint Tx BlockIndex)
	private stable let processedMintRequestFromIcpTx = Map.new<IcpBlockIndex, (IcpBlockIndex, USDxBlockIndex)>();

	private stable let processedMintThroughCalls = Vector.new<USDxBlockIndex>();

	private stable var xdrUsd : XdrUsd = { rate = 0; timestamp = 0 };

	let failedToUpdateXdrUsdRate = Buffer.Buffer<UpdateXdrUsdRateError>(0);

	public shared ({ caller }) func notify_mint_with_icp(icpBlockIndex : Nat64, coin : MintCoin) : async NotifyMintWithICPResult {
		trapAnonymousUser(caller);
		trapWhenXRateIsZero();

		if (Map.get(processedMintRequestFromIcpTx, n64hash, icpBlockIndex) != null) {

			let (?(_icpBlockIndex, _usdxBlockIndex)) = Map.get(processedMintRequestFromIcpTx, n64hash, icpBlockIndex) else {
				return #err(#Other({ error_message = "blockIndex not found"; error_code = 1 }));
			};
			return #err(#AlreadyProcessed { blockIndex = _usdxBlockIndex });
		};

		let validatedIcpBlockResult = await validateICPBlock(icpBlockIndex, caller);
		let txAmount : Nat64 = switch (validatedIcpBlockResult) {
			case (#ok(value)) { value };
			case (#err(error)) { return #err(error) };
		};

		// Transfer ICP to CMC Account
		let cmcPrincipal = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
		let stablecoinMinterSubaccount = Utils.principalToSubaccountBlob(Principal.fromActor(StablecoinMinter));
		let accountIdentifierCMC = Utils.accountIdentifier(cmcPrincipal, stablecoinMinterSubaccount);
		let transferArgs : IcpLedger.TransferArgs = {
			memo = 1347768404;
			amount = { e8s = txAmount - 10_000 };
			fee = { e8s = 10_000 };
			from_subaccount = null;
			to = Blob.toArray(accountIdentifierCMC);
			created_at_time = ?{ timestamp_nanos = Nat64.fromIntWrap(Time.now()) };

		};
		let icpTransferResult = await IcpLedger.transfer(transferArgs);
		let blockIndexOfIcpToCMC : Nat64 = switch (icpTransferResult) {
			case (#Ok(value)) { value };
			case (#Err(error)) {
				return #err(#Other({ error_message = "ICP Ledger Transfer Error"; error_code = 2 }));
			};
		};

		// Notify CMC to mint cycles to stablecoin minter
		let notifyTopUpArg = {
			block_index = blockIndexOfIcpToCMC;
			canister_id = Principal.fromActor(StablecoinMinter);
		};
		let notifyTopUpResult = await CMC.notify_top_up(notifyTopUpArg);
		let cyclesAmount : Nat = switch (notifyTopUpResult) {
			case (#Ok(value)) { value };
			case (#Err(error)) {
				return #err(#Other({ error_message = "CMC Notify Top Up Error"; error_code = 3 }));
			};
		};

		// After collecting minting fee in cycles send remaining cycles to reserve
		let mintFee : Nat = calculateMintFee(cyclesAmount);
		let reserveAmount : Nat = cyclesAmount - mintFee;

		Cycles.add(reserveAmount);
		let result = await CycleReserve.cycle_reserve_receive();

		// calling ICRC to mint the stablecoin
		let usdxTransferResult : USDx.TransferResult = await USDx.icrc1_transfer({
			to = { owner = caller; subaccount = null };
			fee = null;
			memo = null;
			from_subaccount = null;
			created_at_time = null;
			amount = calculateMintAmount(reserveAmount);
		});

		let usdxBlockIndex = switch (usdxTransferResult) {
			case (#Ok(value)) { value };
			case (#Err(error)) {
				return #err(#Other({ error_message = "USDx Ledger Transfer Error"; error_code = 7 }));
			};
		};

		// Then add Block index to the processedMintRequestFromICPTx
		Map.set(processedMintRequestFromIcpTx, n64hash, icpBlockIndex, (blockIndexOfIcpToCMC, usdxBlockIndex));

		#ok(usdxBlockIndex);
	};

	public shared ({ caller }) func notify_mint_with_cycles_ledger_transfer(blockIndex_ : CLBlockIndex, coin : MintCoin) : async NotifyMintWithCyclesLedgerTransferResult {
		trapAnonymousUser(caller);
		trapWhenXRateIsZero();

		if (Map.get(processedMintRequestFromCylesLedgerTx, nhash, blockIndex_) != null) {

			let (?(cyclesLedgerBlockIndex, usdxBlockIndex)) = Map.get(processedMintRequestFromCylesLedgerTx, nhash, blockIndex_) else {
				return #err(#Other({ error_message = "blockIndex not found"; error_code = 1 }));
			};
			return #err(#AlreadyProcessed { blockIndex = usdxBlockIndex });
		};

		let validatedBlockResult = await validateCyclesLedgerBlock(blockIndex_, caller);
		let (txAmount, mintTo) : (Nat, Account) = switch (validatedBlockResult) {
			case (#ok(value)) { value };
			case (#err(error)) { return #err(error) };
		};

		// Calculate mint fee , cycles ledger transaction fee, and transfer the remaining cycles to the reserve
		let mintFee : Nat = calculateMintFee(txAmount);
		let ledgerTxFee : Nat = 100_000_000; // For withdrawing cycles
		let reserveAmount : Nat = txAmount - mintFee - ledgerTxFee;

		///// transfer the cycles to the reserve and mint the stablecoin
		let withdrawArgs : CycleLedger.WithdrawArgs = {
			amount = reserveAmount;
			from_subaccount = null;
			to = Principal.fromActor(CycleReserve);
			created_at_time = ?Nat64.fromIntWrap(Time.now());
		};
		let withdrawCyclesResult = await CycleLedger.withdraw(withdrawArgs);

		let withdrawBlockIndex = switch (withdrawCyclesResult) {
			case (#Ok(value)) { value };
			case (#Err(error)) {
				return #err(#Other({ error_message = "Cycles Ledger Withdraw Error"; error_code = 2 }));
			};
		};

		// calling ICRC to mint the stablecoin
		let transferResult : USDx.TransferResult = await USDx.icrc1_transfer({
			to = mintTo;
			fee = null;
			memo = null;
			from_subaccount = null;
			created_at_time = null;
			amount = calculateMintAmount(reserveAmount);
		});

		let usdxBlockIndex = switch (transferResult) {
			case (#Ok(value)) { value };
			case (#Err(error)) {
				return #err(#Other({ error_message = "USDx Ledger Transfer Error"; error_code = 7 }));
			};
		};

		// Then add Block index to the processedMintRequestFromCylesLedger
		Map.set(processedMintRequestFromCylesLedgerTx, nhash, blockIndex_, (withdrawBlockIndex, usdxBlockIndex));

		#ok(usdxBlockIndex);
	};

	public shared ({ caller }) func mint_through_call(coin : MintCoin, account : ?Account) : async MintThroughCallResult {
		trapAnonymousUser(caller);
		trapWhenXRateIsZero();

		let cyclesAmount : Nat = Cycles.available();
		if (cyclesAmount < 1_000_000_000_000) {
			return #err(#NotEnoughCyclesAvailable(("Cycles available in call " # Nat.toText(cyclesAmount) # " is less than 1 Trillion cycles")));
		} else {
			let mintTo : Account = switch (account) {
				case (?value) { value };
				case (null) { { owner = caller; subaccount = null } };
			};

			// obtaining cycles received through function call
			let obtainedCycles = Cycles.accept(cyclesAmount);

			// After collecting minting fee in cycles send remaining cycles to reserve
			let mintFee : Nat = calculateMintFee(obtainedCycles);
			let reserveAmount : Nat = obtainedCycles - mintFee;

			Cycles.add(reserveAmount);
			let result = await CycleReserve.cycle_reserve_receive();

			// calling ICRC to mint the stablecoin
			let transferResult : USDx.TransferResult = await USDx.icrc1_transfer({
				to = mintTo;
				fee = null;
				memo = null;
				from_subaccount = null;
				created_at_time = null;
				amount = calculateMintAmount(reserveAmount);
			});

			let usdxBlockIndex = switch (transferResult) {
				case (#Ok(value)) { value };
				case (#Err(error)) {
					return #err(#LedgerTransferError("USDx Ledger Transfer Error"));
				};
			};

			// Then add Block index to the processedMintRequestFromCalls
			Vector.add(processedMintThroughCalls, usdxBlockIndex);

			#ok(usdxBlockIndex);
		};
	};

	public query func get_xdr_usd_rate() : async XdrUsd {
		xdrUsd;
	};

	public query func get_account_identitier_of_stablecoin_minter() : async (IcpLedger.AccountIdentifier, Text) {
		let accountIdentitifier = Utils.accountIdentifierDefault(Principal.fromActor(StablecoinMinter));
		(accountIdentitifier, Utils.toHex(accountIdentitifier));
	};
	public shared query ({ caller }) func caller_account_identifier() : async Text {
		let accountIdentitifier = Utils.accountIdentifier(
			Principal.fromActor(CMC),
			Utils.principalToSubaccountBlob(caller)
		);
		Utils.toHex(Blob.toArray accountIdentitifier);
	};

	////////// Private functions //////////
	private func calculateMintFee(amount : Nat) : Nat {
		let fixedFee : Nat = 1_000_000_000;
		let variableFee : Nat = (amount / 10000);
		fixedFee + variableFee;
	};

	// Calculate mint amount in 8 decimal places on the basis of xdrUsdRate and cycles (note 1 trillion cycles is equal to  1 xdr )
	private func calculateMintAmount(cycles : Nat) : Nat {
		let xdrAmount : Float = Float.fromInt cycles / 1_000_000_000_000;
		let usdAmount : Float = xdrAmount * xdrUsd.rate;
		let usdAmountIn8Decimals : Float = usdAmount * 100_000_000;

		Int.abs(Float.toInt(usdAmountIn8Decimals));
	};

	func trapAnonymousUser(caller : Principal) : () {
		if (Principal.isAnonymous(caller)) Debug.trap("Anonymous principal cannot mint");
	};
	func trapWhenXRateIsZero() : () {
		// if (xdrUsd.rate == 0) { let result = await updateXdrUsdRate() };
		if (xdrUsd.rate == 0) Debug.trap("XDR to USD rate is zero");
	};

	private func validateICPBlock(icpBlockIndex : Nat64, caller : Principal) : async Result<Nat64, NotifyError> {
		let queryBlocksResponse = await IcpLedger.query_blocks({
			start = icpBlockIndex;
			length = 1;
		});
		let blocks = queryBlocksResponse.blocks;
		if (blocks.size() == 0) {
			return #err(#InvalidTransaction("Block " #Nat64.toText(icpBlockIndex) # " not found chain_length is" # Nat64.toText(queryBlocksResponse.chain_length)));
		};
		let block = blocks[0];
		let trasaction = block.transaction;
		let { from; to; amount; /* fee; spender */ } = switch (trasaction.operation) {
			case (? #Transfer(transferTx)) { transferTx };
			case (_) {
				return #err(#InvalidTransaction("Notification transaction must be of type Transfer"));
			};
		};

		// Check "to" in TX is AccountIdentifier of Stablecoin Minter with default subaccount
		let accountIdentifierOfStablecoinMinter : IcpLedger.AccountIdentifier = Utils.accountIdentifierDefault(Principal.fromActor(StablecoinMinter));
		if (accountIdentifierOfStablecoinMinter != to) {
			return #err(#InvalidTransaction("The destination account (" # Utils.toHex(to) # ") in the transaction is not the stablecoin minter's account (#" # Utils.toHex(accountIdentifierOfStablecoinMinter) # ")"));
		};

		// Check "from" in TX is the caller principal with default subaccount
		let accountIdentifierOfCaller : IcpLedger.AccountIdentifier = Utils.accountIdentifierDefault(caller);
		if ((accountIdentifierOfCaller != from) /* and (spender == null) */) {
			return #err(#InvalidTransaction("Notifier account (" # Utils.toHex(accountIdentifierOfCaller) # ") and transaction origin account (" # Utils.toHex(from) # ") are not the same"));
		};

		// if there is spender in Tx check spender is notifying [ But they have to provide caller principal or Account to check with from]
		// if ((spender != null) and not ((accountIdentifierOfCaller == from) or (?accountIdentifierOfCaller == spender))) {
		//     return #err(#InvalidTransaction("Notifier account (" # Utils.toHex(accountIdentifierOfCaller) # ") and transaction origin account (" # Utils.toHex(from) # ") are not the same"));
		// };

		// Check memo is correct or not
		// if (trasaction.memo != 382623823) {
		//     return #err(#InvalidTransaction("Transaction memo (" #Nat64.toText(trasaction.memo) # ") is different from the expected memo for notify_mint_with_icp (382623823)"));
		// };

		// Check amount is above minimum 10_000_000 (0.1 ICP)
		if (amount.e8s < 10_000_000) {
			return #err(#InvalidTransaction("Transaction amount is less than 0.1 ICP"));
		} else {
			return #ok(amount.e8s);
		};

	};

	// public query func memo_for_mint_with_icp() : async Nat64 {
	//     382623823;
	// };

	private func validateCyclesLedgerBlock(blockIndex_ : CLBlockIndex, caller : Principal) : async Result<(Nat, Account), NotifyError> {
		let getBlocksResult = await CycleLedger.icrc3_get_blocks([{
			length = 1;
			start = blockIndex_;
		}]);

		let blocks = getBlocksResult.blocks;
		if (blocks.size() == 0) {
			return #err(#InvalidTransaction("Block " # Nat.toText(blockIndex_) # " not found log_length is" # Nat.toText(getBlocksResult.log_length)));
		};
		let block = blocks[0].block;

		let transferTx : CyclesLedgerTransferTX = switch (getCyclesLedgerTransferTX(block)) {
			case (#ok(value)) { value };
			case (#err(error)) { return #err(error) };
		};

		// check principal of stablecoin minter with to
		let transactionToPrincipal : Principal = Principal.fromBlob(transferTx.transaction.to[0]);
		let stablecoinMinterPrincipal : Principal = Principal.fromActor(StablecoinMinter);
		if (stablecoinMinterPrincipal != transactionToPrincipal) {
			return #err(
				#InvalidTransaction(
					"The cycle destination account (" # Principal.toText(transactionToPrincipal) #
					") in the transaction is not the stablecoin minter's account (#" # Principal.toText(stablecoinMinterPrincipal) # ")"
				)
			);
		};

		// check pricnipal of caller with from
		let transactionFromPrincipal : Principal = Principal.fromBlob(transferTx.transaction.from[0]);
		if (caller != transactionFromPrincipal) {
			return #err(
				#InvalidTransaction(
					"Notifier principal (" # Principal.toText(caller) #
					") and transaction origin principal (" # Principal.toText(transactionFromPrincipal) # ") are not the same"
				)
			);
		};

		// check amount is above minimum 1_000_000_000_000
		let amount : Int = transferTx.transaction.amount;
		if (amount < 1_000_000_000_000) {
			return #err(#InvalidTransaction("Transaction amount is less than 1 Trillion cycles"));
		} else {
			#ok(Int.abs(amount), getAccountFromCyclesLedgerTxFrom(transferTx.transaction.from));
		};

	};

	func getCyclesLedgerTransferTX(block_ : Value) : Result<CyclesLedgerTransferTX, NotifyError> {
		let hmap : HashMap<Text, SubValue> = Utils.formatValueOfBlock(block_);

		switch (hmap.get("op")) {
			case (? #Text "xfer") {
				let operation : Text = "xfer";
				/*
                let fee : Int = do {
                    switch (hmap.get("fee")) {
                        case (? #Int fee) { fee };
                        case (_) { 100_000_000 };
                    };
                };
                let phash : [Int] = do {
                    switch (hmap.get("phash")) {
                        case (? #Array phash) {
                            let buffer = Buffer.Buffer<Int>(0);

                            for (p in phash.vals()) {
                                let (#Int byt) = p else {
                                    return #err(#Other({ error_message = "phash is not an array of Int"; error_code = 6 }));
                                };
                                buffer.add(byt);
                            };
                            Buffer.toArray(buffer);
                        };
                        case (_) { [] };
                    };
                }; */
				let timestamp : Int = do {
					switch (hmap.get("ts")) {
						case (? #Int ts) { ts };
						case (_) {
							return #err(#InvalidTransaction "Could'nt find timestamp in transaction");
						};
					};
				};
				let amount : Int = do {
					switch (hmap.get("amt")) {
						case (? #Int amt) { amt };
						case (_) {
							return #err(#InvalidTransaction("Could'nt find amount in transaction"));
						};
					};
				};
				let from : [Blob] = do {
					switch (hmap.get("from")) {
						case (? #Array from) {
							let buffer = Buffer.Buffer<Blob>(0);
							for (account in from.vals()) {
								let (#Blob bytesArr) = account else {
									return #err(#Other({ error_message = "from is not an array of Bytes"; error_code = 4 }));
								};
								buffer.add(Blob.fromArray(bytesArr));
							};
							Buffer.toArray(buffer);
						};
						case (_) {
							return #err(#InvalidTransaction("Could'nt find from Account in transaction"));
						};
					};
				};
				let to : [Blob] = do {
					switch (hmap.get("to")) {
						case (? #Array to) {
							let buffer = Buffer.Buffer<Blob>(0);
							for (account in to.vals()) {
								let (#Blob bytesArr) = account else {
									return #err(#Other({ error_message = "to is not an array of Bytes"; error_code = 5 }));
								};
								buffer.add(Blob.fromArray(bytesArr));
							};
							Buffer.toArray(buffer);
						};
						case (_) {
							return #err(#InvalidTransaction("Could'nt find  to Account in transaction"));
						};
					};
				};

				#ok({
					fee = null;
					phash = null;
					timestamp;
					transaction = {
						amount;
						from;
						operation;
						to;
					};
				});
			};

			case (? #Text "mint") {

				#err(#InvalidTransaction("Notification transaction must be of type transfer not mint"));
			};
			case (? #Text "burn") {
				#err(#InvalidTransaction("Notification transaction must be of type transfer not burn"));
			};
			case (_) {
				#err(#InvalidTransaction("Notification transaction must be of type transfer"));
			};
		};

	};

	func getAccountFromCyclesLedgerTxFrom(from : [Blob]) : Account {
		if (from.size() == 0) {
			Debug.trap("from array is empty");
		} else if (from.size() == 1) {
			return { owner = Principal.fromBlob(from[0]); subaccount = null };
		} else {
			return { owner = Principal.fromBlob(from[0]); subaccount = ?Blob.toArray(from[1]) };
		};
	};

	system func preupgrade() : () {
		stopXrcFetchTimer();
	};
	system func postupgrade() : () {
		restartXrcFetchTimer();
	};

	// Fetch XDR/USD rate from XRC and update xdrUsd

	private func getXdrUsdRate() : async XRC.GetExchangeRateResult {
		let base_asset = { symbol = "CXDR"; class_ = #FiatCurrency };
		let quote_asset = { symbol = "USD"; class_ = #FiatCurrency };
		let timestamp = null;

		Cycles.add(10_000_000_000);
		let getExchangeRateResult = await XRC.get_exchange_rate({
			base_asset;
			quote_asset;
			timestamp;
		});
	};

	private func updateXdrUsdRate() : async UpdateXdrUsdRateResult {
		let getExchangeRateResult = await getXdrUsdRate();

		let exchangeRate : XRC.ExchangeRate = switch (getExchangeRateResult) {
			case (#Ok(value)) { value };
			case (#Err(error)) { return #err({ error_time = Time.now(); error = error }) };
		};
		let rateNat : Nat = Nat64.toNat(exchangeRate.rate);

		let decimals : Float = Float.fromInt(Nat32.toNat(exchangeRate.metadata.decimals));

		let rate : Float = Float.fromInt(rateNat) / (10 ** decimals);

		xdrUsd := { rate; timestamp = exchangeRate.timestamp };

		#ok();
	};

	private func timerUpdateXdrUsdRate() : async () {
		let updateXdrUsdRateResult = await updateXdrUsdRate();
		switch (updateXdrUsdRateResult) {
			case (#ok(value)) {};
			case (#err(error)) { failedToUpdateXdrUsdRate.add(error) };
		};
	};

	// This will automatically fetch XDR/USD in every hour
	private stable var xrcFetchTimerId : TimerId = 0;
	xrcFetchTimerId := do {
		// let currentTime = Time.now();
		let oneHourInNanoSec = 3600_000_000_000;
		let nextFetchTime = oneHourInNanoSec - (Time.now() % oneHourInNanoSec);

		Timer.setTimer(
			#nanoseconds(Int.abs nextFetchTime),
			func() : async () {
				xrcFetchTimerId := Timer.recurringTimer(#seconds 3600, timerUpdateXdrUsdRate);
				await timerUpdateXdrUsdRate();
			}
		);

	};

	private func restartXrcFetchTimer() : () {
		// let currentTime = Time.now();
		let oneHourInNanoSec = 3600_000_000_000;
		let nextFetchTime = oneHourInNanoSec - (Time.now() % oneHourInNanoSec);

		xrcFetchTimerId := Timer.setTimer(
			#nanoseconds(Int.abs nextFetchTime),
			func() : async () {
				xrcFetchTimerId := Timer.recurringTimer(#seconds 3600, timerUpdateXdrUsdRate);
				await timerUpdateXdrUsdRate();
			}
		);
	};

	private func stopXrcFetchTimer() : () {
		Timer.cancelTimer(xrcFetchTimerId);
	};

};
