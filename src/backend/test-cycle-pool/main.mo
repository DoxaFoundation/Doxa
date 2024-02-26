import Cycles "mo:base/ExperimentalCycles";
import Result "mo:base/Result";

actor {
	type Operation = { #Add; #Subtract : { amount : Nat } };
	type ReserveResult = Result.Result<(), Text>;

	let cycleReserve : actor {
		cycle_reserve_adjust : shared Operation -> async ReserveResult;
		cycle_reserve_balance : shared () -> async Nat;
		cycle_reserve_mint : shared () -> async ();
	} = actor ("br5f7-7uaaa-aaaaa-qaaca-cai");

	public func cycle_pool_receive() : async Nat {
		Cycles.accept(Cycles.available());

		// Emit event cycles received
	};

	// private
	public func add_cycles_to_reserve(cycles : Nat) : async Nat {

		Cycles.add(cycles);
		let result = await cycleReserve.cycle_reserve_adjust(#Add);

		await cycleReserve.cycle_reserve_balance();
	};

	public func subtract_cycles_to_reserve(amount : Nat) : async Nat {
		let result = await cycleReserve.cycle_reserve_adjust(#Subtract { amount });

		await cycleReserve.cycle_reserve_balance();
	};
};
