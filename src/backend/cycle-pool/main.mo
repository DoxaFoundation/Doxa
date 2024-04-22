import XRC "canister:exchange_rate_canister";
import USDx "canister:usdx_ledger";
import CycleReserve "canister:cycle_reserve";
import IcpLedger "canister:icp_ledger";
import CMC "canister:cycle_minting_canister";

import StableBuffer "mo:StableBuffer/StableBuffer";
import Cycles "mo:base/ExperimentalCycles";
import Result "mo:base/Result";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Int "mo:base/Int";
import Buffer "mo:base/Buffer";
import Nat64 "mo:base/Nat64";
import Float "mo:base/Float";
import Nat32 "mo:base/Nat32";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Utils "../Utils";

actor CyclePool {
	type Operation = { #Add; #Subtract : { amount : Nat } };
	type ReserveResult = Result.Result<(), Text>;
	type Time = Time.Time;
	type TimerId = Timer.TimerId;
	type Result<O, E> = Result.Result<O, E>;

	type XdrUsd = { rate : Float; timestamp : Nat64 };

	type UpdateXdrUsdRateError = {
		error_time : Time;
		error : XRC.ExchangeRateError;
	};
	type UpdateXdrUsdRateResult = Result<(), UpdateXdrUsdRateError>;

	type CyclePoolTopUpError = {
		error_time : Time;
		error : {
			#IcpLedger : IcpLedger.TransferError;
			#CMC : CMC.NotifyError;
		};
	};

	let cyclePoolCanisterId = Principal.fromText("i7m4z-gqaaa-aaaak-qddtq-cai");
	private stable var xdrUsd : XdrUsd = { rate = 0; timestamp = 0 };

	let failedToUpdateXdrUsdRate = Buffer.Buffer<UpdateXdrUsdRateError>(0);
	private stable var usdxTotalSupply : Float = 0;

	stable let cyclesPoolTopUpFailed = StableBuffer.init<CyclePoolTopUpError>();

	public func cycle_pool_receive() : async Nat {
		Cycles.accept<system>(Cycles.available());
		// Emit event cycles received
	};

	public query func get_cycles_pool_top_up_failed() : async [CyclePoolTopUpError] {
		StableBuffer.toArray(cyclesPoolTopUpFailed);
	};
	public query func get_failed_to_update_xdr_usd_rate() : async [UpdateXdrUsdRateError] {
		Buffer.toArray(failedToUpdateXdrUsdRate);
	};

	system func preupgrade() : () {
		stopXrcFetchTimer();
		stopTotalSupplyTimer();
		stopReserveAdjustTimer();
	};

	system func postupgrade() : () {
		restartTotalSupplyTimer<system>();
		restartXrcFetchTimer<system>();
		restartReserveAdjustTimer<system>();
	};

	//////////// Fetch XDR/USD rate from XRC and update xdrUsd //////////////

	// if new = 1.4 expectedCyclesInReserve = 714,285,714,285,714   .2857142857

	//example new = 1.2 and previous = 1.3 totalsupply = 1,000
	private func mintCyclesIfNeeded(newRate : Float, previousRate : Float) : async () {
		let expectedCyclesInReserveWithNewRate__ : Float = usdxTotalSupply * (1 / newRate) * 1_000_000_000_000;
		let expectedCyclesInReserveWithNewRate = Int.abs(Float.toInt(expectedCyclesInReserveWithNewRate__));
		// 833,333,333,333,333    .3333333333

		let expectedCyclesInReserveWithPreviousRate__ : Float = usdxTotalSupply * (1 / previousRate) * 1_000_000_000_000;
		let expectedCyclesInReserveWithPreviousRate = Int.abs(Float.toInt(expectedCyclesInReserveWithPreviousRate__));
		// 769,230,769,230,769    .2307692308
		if (expectedCyclesInReserveWithNewRate > expectedCyclesInReserveWithPreviousRate) {
			let cycleInNeedToMaintainPeg : Nat = expectedCyclesInReserveWithNewRate - expectedCyclesInReserveWithPreviousRate;
			let cyclePoolBalance = Cycles.balance();
			let balanceMinusAdditionalforComputaion : Int = cyclePoolBalance - 2_000_000_000_000; // Ten trillion cycles as a buffer

			if (balanceMinusAdditionalforComputaion < cycleInNeedToMaintainPeg) {
				let cyclesToMint = cycleInNeedToMaintainPeg - balanceMinusAdditionalforComputaion;
				await topUpCyclePoolWithCycles(Int.abs(cyclesToMint));
			};
		};

	};

	private func topUpCyclePoolWithCycles(cyclesAmount : Nat) : async () {
		let cmcPrincipal = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
		let cyclePoolSubaccount = Utils.principalToSubaccountBlob(cyclePoolCanisterId);
		let accountIdentifierCMC = Utils.accountIdentifier(cmcPrincipal, cyclePoolSubaccount);

		let { data = { xdr_permyriad_per_icp : Nat64 } } = await CMC.get_icp_xdr_conversion_rate();

		let xdrPerIcp : Float = Float.fromInt(Nat64.toNat(xdr_permyriad_per_icp)) / 10_000;

		// cycle amount is  rounds up to XDR ( example 0.001 rounds up to 1 XDR)
		let xdrAmount : Float = Float.ceil(Float.fromInt(cyclesAmount) / 1_000_000_000_000);
		let icpAmount : Float = xdrAmount / xdrPerIcp;
		let icpAmountE8s : Nat64 = Nat64.fromIntWrap(Float.toInt(icpAmount * 100_000_000));

		let transferArgs : IcpLedger.TransferArgs = {
			memo = 1347768404;
			amount = { e8s = icpAmountE8s };
			fee = { e8s = 10_000 };
			from_subaccount = null;
			to = accountIdentifierCMC;
			created_at_time = ?{ timestamp_nanos = Nat64.fromIntWrap(Time.now()) };
		};

		let icpTransferResult = await IcpLedger.transfer(transferArgs);
		let blockIndexOfIcpToCMC : Nat64 = switch (icpTransferResult) {
			case (#Ok(value)) { value };
			case (#Err(error)) {
				StableBuffer.add(cyclesPoolTopUpFailed, { error_time = Time.now(); error = #IcpLedger error });
				return ();
			};
		};

		// Notify CMC to mint cycles to cycle pool
		let notifyTopUpArg = {
			block_index = blockIndexOfIcpToCMC;
			canister_id = cyclePoolCanisterId;
		};
		let notifyTopUpResult = await CMC.notify_top_up(notifyTopUpArg);
		let _mintedCycles : Nat = switch (notifyTopUpResult) {
			case (#Ok(value)) { value };
			case (#Err(error)) {
				StableBuffer.add(cyclesPoolTopUpFailed, { error_time = Time.now(); error = #CMC error });
				return ();
			};
		};
	};

	private func getXdrUsdRate() : async XRC.GetExchangeRateResult {
		let base_asset = { symbol = "CXDR"; class_ = #FiatCurrency };
		let quote_asset = { symbol = "USD"; class_ = #FiatCurrency };
		let timestamp = null;

		Cycles.add<system>(10_000_000_000);
		let _getExchangeRateResult = await XRC.get_exchange_rate({
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

		let newRate : Float = Float.fromInt(rateNat) / (10 ** decimals);

		if (newRate < xdrUsd.rate) {
			await mintCyclesIfNeeded(newRate, xdrUsd.rate);
		};

		xdrUsd := { rate = newRate; timestamp = exchangeRate.timestamp };

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

		Timer.setTimer<system>(
			#nanoseconds(Int.abs nextFetchTime),
			func() : async () {
				xrcFetchTimerId := Timer.recurringTimer<system>(#seconds 3600, timerUpdateXdrUsdRate);
				await timerUpdateXdrUsdRate();
			}
		);

	};

	private func restartXrcFetchTimer<system>() : () {
		// let currentTime = Time.now();
		let oneHourInNanoSec = 3600_000_000_000;
		let nextFetchTime = oneHourInNanoSec - (Time.now() % oneHourInNanoSec);

		xrcFetchTimerId := Timer.setTimer<system>(
			#nanoseconds(Int.abs nextFetchTime),
			func() : async () {
				xrcFetchTimerId := Timer.recurringTimer<system>(#seconds 3600, timerUpdateXdrUsdRate);
				await timerUpdateXdrUsdRate();
			}
		);
	};

	private func stopXrcFetchTimer() : () {
		Timer.cancelTimer(xrcFetchTimerId);
	};

	//////////////// Total supply of USDx //////////////////////
	private func fetchTotalSupply() : async () {
		let totalSupply = await USDx.icrc1_total_supply();
		usdxTotalSupply := Float.fromInt(totalSupply) / 100_000_000;
	};

	stable var totalSupplyTimerId : TimerId = 0;
	totalSupplyTimerId := do {
		Timer.recurringTimer<system>(#seconds 1, fetchTotalSupply);
	};

	private func restartTotalSupplyTimer<system>() : () {
		totalSupplyTimerId := Timer.recurringTimer<system>(#seconds 1, fetchTotalSupply);
	};

	private func stopTotalSupplyTimer() : () {
		Timer.cancelTimer(totalSupplyTimerId);
	};

	///////////////////////////// Adjust Cycle Reserve functions /////////////////////////////
	private func adjustCycleReserve() : async () {
		let reserveCurrentCycles = await CycleReserve.cycle_reserve_balance();
		let expectedCyclesInReserve__ : Float = usdxTotalSupply * (1 / xdrUsd.rate) * 1_000_000_000_000;
		let expectedCyclesInReserve = Int.abs(Float.toInt(expectedCyclesInReserve__));

		// 8,511,097,318,335 = 11.33606873*(1/1.331916239)*1,000,000,000,000
		//  8,511,097,318,335  > 8_499_224_797_270

		if (expectedCyclesInReserve > reserveCurrentCycles) {
			// 11,872,521,065
			Cycles.add<system>(expectedCyclesInReserve - reserveCurrentCycles);
			let _result = await CycleReserve.cycle_reserve_adjust(#Add);
		} else if (expectedCyclesInReserve < reserveCurrentCycles) {
			let amount : Nat = reserveCurrentCycles - expectedCyclesInReserve;
			let _result = await CycleReserve.cycle_reserve_adjust(#Subtract { amount });
		};
	};

	stable var reserveAdjustTimerId : TimerId = 0;
	reserveAdjustTimerId := do {
		Timer.recurringTimer<system>(#seconds 1, adjustCycleReserve);
	};

	private func restartReserveAdjustTimer<system>() : () {
		reserveAdjustTimerId := Timer.recurringTimer<system>(#seconds 1, adjustCycleReserve);
	};
	private func stopReserveAdjustTimer() : () {
		Timer.cancelTimer(reserveAdjustTimerId);
	};

};
