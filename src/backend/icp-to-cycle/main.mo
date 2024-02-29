import LedgerCanister "Ledger";
import CanisterIds "CanisterIds";
import CyclesMinter "CyclesMinter";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";

actor IcpToCycle {
	let cmc : CyclesMinter.Cmc = actor ("CanisterIds.CYCLES_MINTING_CANISTER");
	let ledger : LedgerCanister.Self = actor ("CanisterIds.LEDGER_CANISTER");

	public func transfer_to_cmc() : async LedgerCanister.Result {
		let principal : Principal = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");

		var sub = Array.init<Nat8>(32, 0);
		sub[0] := 1;
		let subaccount = Array.freeze(sub);

		let account : LedgerCanister.Account = { owner = principal; subaccount = ?subaccount };

		let memo : [Nat8] = [Nat8.fromNat(1347764804)];

		let arg : LedgerCanister.TransferArg = {

			to = account;
			fee = ?10000;
			memo = ?memo;
			from_subaccount = null;
			created_at_time = ?Nat64.fromIntWrap(Time.now());
			amount = 10_000_000; //.01 icp

		};

		await ledger.icrc1_transfer(arg);
	};

	public func balance() : async Nat {
		let actorsPrincipal : Principal = Principal.fromActor(IcpToCycle);

		var sub = Array.init<Nat8>(32, 0);
		sub[0] := 1;
		let subaccount = Array.freeze(sub);

		let account = {
			owner = actorsPrincipal;
			subaccount = ?subaccount;
		};
		await ledger.icrc1_balance_of(account);
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
