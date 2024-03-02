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

import icpLedger "canister:icp-ledger";
import CMC "canister:cycle-minting-canister";

import Binary "mo:encoding.mo/Binary";

actor IcpToCycle {

	public func transfer_to_cmc() : async icpLedger.Icrc1TransferResult {
		let principal : Principal = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");

		// var sub = Array.init<Nat8>(32, 0);
		// sub[0] := 1;
		// let subaccount = ?Array.freeze(sub);

		// let subaccount = Utils.toSubAccount(1);

		let account : icpLedger.Account = {
			owner = principal;
			subaccount = ?Utils.principalToSubaccount(Principal.fromActor(IcpToCycle));
		};

		// let memo : [Nat8] = Utils.fromNatToNat8Array(4, 1347768404);
		let memo : [Nat8] = Binary.BigEndian.fromNat64(1347768404);
		// let memo : [Nat8] = Binary.LittleEndian.fromNat64(1347768404);

		let arg : icpLedger.TransferArg = {

			to = account;
			fee = ?10000;
			memo = ?memo;
			from_subaccount = null;

			// from_subaccount = Utils.toSubAccount(1);

			created_at_time = ?Nat64.fromIntWrap(Time.now());
			amount = 10_000_000; //.01 icp

		};

		await icpLedger.icrc1_transfer(arg);
	};

	public func cmc_account(sub : Nat) : async Text {
		let subaccount = Utils.toSubAccount(sub);

		let account = {
			owner = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
			subaccount = subaccount;
		};

		let accountIdentifierofThis = await icpLedger.account_identifier(account);

		Utils.toHex(accountIdentifierofThis);

	};

	public func icp_account_of_actor(sub : Nat) : async Text {

		// var sub = Array.init<Nat8>(32, 0);
		// sub[0] := 1;
		// let subaccount = ?Array.freeze(sub);

		let subaccount = Utils.toSubAccount(sub);

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

		let arg : CMC.NotifyTopUpArg = {
			block_index = block;
			canister_id = actorsPrincipal;
		};

		await CMC.notify_top_up(arg);
	};

	public func get_icp_xdr_conversion_rate() : async CyclesMinter.IcpXdrConversionRateResponse {
		await CMC.get_icp_xdr_conversion_rate();
	};

	public func notify_mint_cycles(blockIndex : Nat) : async CMC.NotifyMintCyclesResult {

		await CMC.notify_mint_cycles({
			block_index = Nat64.fromNat(blockIndex);
			deposit_memo = ?Binary.BigEndian.fromNat64(1347768404);
			to_subaccount = null;
		});

	};

};
