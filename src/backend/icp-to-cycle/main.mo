// import LedgerCanister "Ledger";
import CanisterIds "CanisterIds";
import CyclesMinter "CyclesMinter";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Utils "../Utils";

// import icpLedger "ic:ryjl3-tyaaa-aaaaa-aaaba-cai";
import icpLedger "canister:icp-ledger";

actor IcpToCycle {
	let cmc : CyclesMinter.Cmc = actor (CanisterIds.CYCLES_MINTING_CANISTER);
	// let ledger : LedgerCanister.Self = actor (CanisterIds.LEDGER_CANISTER);

	public func transfer_to_cmc() : async icpLedger.Icrc1TransferResult {
		let principal : Principal = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");

		// var sub = Array.init<Nat8>(32, 0);
		// sub[0] := 1;
		// let subaccount = ?Array.freeze(sub);

		let subaccount = Utils.toSubAccount(1);

		let account : icpLedger.Account = { owner = principal; subaccount };

		let memo : [Nat8] = Utils.fromNatToNat8Array(10, 1347764804);

		let arg : icpLedger.TransferArg = {

			to = account;
			fee = ?10000;
			memo = ?memo;
			// from_subaccount = null;

			from_subaccount = Utils.toSubAccount(1);

			created_at_time = ?Nat64.fromIntWrap(Time.now());
			amount = 10_000_000; //.01 icp

		};

		await icpLedger.icrc1_transfer(arg);
	};

	public func icp_account_of_actor() : async Text {

		// var sub = Array.init<Nat8>(32, 0);
		// sub[0] := 1;
		// let subaccount = ?Array.freeze(sub);

		let subaccount = Utils.toSubAccount(1);

		let account = {
			owner = Principal.fromActor(IcpToCycle);
			subaccount = subaccount;
		};

		let accountIdentifierofThis = await icpLedger.account_identifier(account);

		Utils.toHex(accountIdentifierofThis);

	};

	public func balance() : async Nat {
		let actorsPrincipal : Principal = Principal.fromActor(IcpToCycle);

		// var sub = Array.init<Nat8>(32, 0);
		// sub[0] := 1;
		// let subaccount = ?Array.freeze(sub);

		let subaccount = Utils.toSubAccount(1);

		let account = {
			owner = actorsPrincipal;
			subaccount = subaccount;
		};
		await icpLedger.icrc1_balance_of(account);
	};

	public func notify_top_up(block : CyclesMinter.BlockIndex) : async CyclesMinter.NotifyTopUpResult {
		let actorsPrincipal : Principal = Principal.fromActor(IcpToCycle);

		let arg : CyclesMinter.NotifyTopUpArg = {
			block_index = block;
			canister_id = actorsPrincipal;
		};

		await cmc.notify_top_up(arg);
	};

	public func get_icp_xdr_conversion_rate() : async CyclesMinter.IcpXdrConversionRateResponse {
		await cmc.get_icp_xdr_conversion_rate();
	};

};
