import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";

import Result "mo:base/Result";
import Text "mo:base/Text";

actor {

	// Types
	type Result = Result.Result<(), Text>;
	type Operation = {
		# Add;
		# Subtract : { amount : Nat };
	};

	let cyclePool : actor {
		cycle_pool_receive : shared () -> async Nat;
	} = actor ("i7m4z-gqaaa-aaaak-qddtq-cai");

	let stablecoinMinter : Principal = Principal.fromText("iyn2n-liaaa-aaaak-qddta-cai");

	// Ledger canister or Cycle minting canister will call this method to add cycles to the reserve
	public shared ({ caller }) func cycle_reserve_receive() : async Result {
		if (caller != stablecoinMinter) {
			#err("Unauthorized caller");
		} else {
			// accept Cycles
			let _acceptCycles = Cycles.accept<system>(Cycles.available());
			#ok();
		};

	};

	// Pool canister will call this method to adjust the reserve
	public shared ({ caller }) func cycle_reserve_adjust(operaion : Operation) : async Result {
		if (caller != Principal.fromText("i7m4z-gqaaa-aaaak-qddtq-cai")) {
			return #err("Unauthorized caller");
		};

		switch (operaion) {
			case (#Add) {
				let _acceptCycles = Cycles.accept<system>(Cycles.available());
				#ok();
			};
			case (#Subtract { amount : Nat }) {
				Cycles.add<system>(amount);
				let _subtractedCycles = await cyclePool.cycle_pool_receive();
				#ok();
			};
		};

	};

	// Get current cycle reserve balance
	public shared query func cycle_reserve_balance() : async Nat {
		Cycles.balance();
	};

};
