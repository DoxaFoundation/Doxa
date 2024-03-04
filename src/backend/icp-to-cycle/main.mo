// import LedgerCanister "Ledger";
import CanisterIds "CanisterIds";
import CyclesMinter "CyclesMinter";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import Utils "../Utils";

import icpLedger "canister:icp_ledger";
import CMC "canister:cycle_minting_canister";

import Binary "mo:encoding.mo/Binary";

actor IcpToCycle {

	public func transfer_to_cmc() : async icpLedger.TransferResult {
		let principal : Principal = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");

		// var sub = Array.init<Nat8>(32, 0);
		// sub[0] := 1;
		// let subaccount = ?Array.freeze(sub);

		// let subaccount = Utils.toSubAccount(1);

		// let account : icpLedger.Account = {
		//     owner = principal;
		//     subaccount = ?Utils.principalToSubaccount(Principal.fromActor(IcpToCycle));
		// };

		let accountIdentifier = Utils.accountIdentifier(principal, Utils.principalToSubaccountBlob(Principal.fromActor(IcpToCycle)));

		// let memo : [Nat8] = Utils.fromNatToNat8Array(4, 1347768404);
		// let memo : [Nat8] = Binary.BigEndian.fromNat64(1347768404);
		// let memo : [Nat8] = Binary.LittleEndian.fromNat64(1347768404);

		let arg : icpLedger.TransferArgs = {

			// to = await icpLedger.account_identifier(account);
			to = Blob.toArray(accountIdentifier);
			fee = { e8s = 10_000 };
			memo = 1347768404;
			from_subaccount = null;
			created_at_time = ?{ timestamp_nanos = Nat64.fromIntWrap(Time.now()) };
			amount = { e8s = 10_000_000 }; //.01 icp

		};

		await icpLedger.transfer(arg);
	};

	public func cmc_account(sub : Nat) : async Text {
		let subaccount = ?Utils.toSubAccount(sub);

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

		let subaccount = ?Utils.toSubAccount(sub);

		let account = {
			owner = Principal.fromActor(IcpToCycle);
			subaccount = subaccount;
		};

		let accountIdentifierofThis = await icpLedger.account_identifier(account);

		Utils.toHex(accountIdentifierofThis);

	};

	public func accountIdentifierTest(sub : Nat) : async Text {

		Utils.toHex(Blob.toArray(Utils.accountIdentifier(Principal.fromActor(IcpToCycle), Blob.fromArray(Utils.toSubAccount(sub)))));
	};

	public func balance() : async Nat {
		let actorsPrincipal : Principal = Principal.fromActor(IcpToCycle);

		// var sub = Array.init<Nat8>(32, 0);
		// sub[0] := 1;
		// let subaccount = ?Array.freeze(sub);

		let subaccount = ?Utils.toSubAccount(1);

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

	///////////////////////////

	public func notify_mint_cycles(blockIndex : Nat) : async CMC.NotifyMintCyclesResult {

		await CMC.notify_mint_cycles({
			block_index = Nat64.fromNat(blockIndex);
			deposit_memo = ?Binary.BigEndian.fromNat64(1347768404);
			to_subaccount = null;
		});

	};

	public shared ({ caller }) func getICPTransferAccount() : async Text {
		let account : icpLedger.Account = {
			owner = Principal.fromText "rkp4c-7iaaa-aaaaa-aaaca-cai";
			subaccount = ?Utils.principalToSubaccount(caller);
		};

		Utils.toHex(await icpLedger.account_identifier(account));
	};

	public shared ({ caller }) func getICPTransferAccount2() : async Text {

		let account = {
			owner = Principal.fromText "rkp4c-7iaaa-aaaaa-aaaca-cai";
			subaccount = ?Utils.toSubAccount(0);
		};

		Utils.toHex(await icpLedger.account_identifier(account));
	};

};

/*
Compare method one and two
---one---
1 ICP = 13.19 USD
0.0001 ICP = 0.001319 USD
1 USD = 0.75304061 XDR
1 XDR = 1 trillion cycles
0.001319 USD = 0.00099324879911 XDR

0.0001 ICP = 993_248_799.11 cycles
One ICP transaction cost  990 million cycles


---two---
Cycle withdraw function on cycle ledger cost



record {
  max_blocks_per_request : nat64;
  index_id : opt principal;
};

record { max_blocks_per_request = 1; index_id = null };
*/
