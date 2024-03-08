import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
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
	} = actor ("bw4dl-smaaa-aaaaa-qaacq-cai");

	let stablecoinMinter : actor {} = actor ("bd3sg-teaaa-aaaaa-qaaba-cai");

	// Ledger canister or Cycle minting canister will call this method to add cycles to the reserve
	public shared ({ caller }) func cycle_reserve_receive() : async Result {
		if (caller != Principal.fromActor(stablecoinMinter)) {
			#err("Unauthorized caller");
		} else {
			let acceptCycles = Cycles.accept(Cycles.available());
			#ok();
		};

	};

	// Pool canister will call this method to adjust the reserve
	public shared ({ caller }) func cycle_reserve_adjust(operaion : Operation) : async Result {
		if (caller != Principal.fromActor(cyclePool)) {
			return #err("Unauthorized caller");
		};

		switch (operaion) {
			case (#Add) {
				let acceptCycles = Cycles.accept(Cycles.available());
				#ok();
			};
			case (#Subtract { amount : Nat }) {
				Cycles.add(amount);
				let subtractedCycles = await cyclePool.cycle_pool_receive();
				#ok();
			};
		};

	};

	// Get current cycle reserve balance
	public shared func cycle_reserve_balance() : async Nat {
		let balance = Cycles.balance();
	};

};
