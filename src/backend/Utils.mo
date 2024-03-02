import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";

module {

	public func fromNatToNat8Array(len : Nat, n : Nat) : [Nat8] {
		let ith_byte = func(i : Nat) : Nat8 {
			assert (i < len);
			let shift : Nat = 8 * (len - 1 - i);
			Nat8.fromIntWrap(n / 2 ** shift);
		};
		Array.tabulate<Nat8>(len, ith_byte);
	};

	// for subaccount creation
	public func decimal_to_256_base(num : Nat) : [var Nat8] {
		let array = Array.init<Nat8>(32, 0);
		var decimal = num;
		var i = 0;

		while (decimal > 0) {
			array[31 -i] := Nat8.fromNat(decimal % 256);
			decimal := decimal / 256;
			i += 1;
		};
		return array;
	};

	// public func toSubAccount(subaccountNumber : Nat) : ?Blob {
	//     ?Blob.fromArrayMut(decimal_to_256_base(subaccountNumber));
	// };

	public func toSubAccount(subaccountNumber : Nat) : ?[Nat8] {
		?Array.freeze(decimal_to_256_base(subaccountNumber));
	};

	let hexChars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"];
	public func toHex(arr : [Nat8]) : Text {
		Text.join(
			"",
			Iter.map<Nat8, Text>(
				Iter.fromArray(arr),
				func(x : Nat8) : Text {
					let a = Nat8.toNat(x / 16);
					let b = Nat8.toNat(x % 16);
					hexChars[a] # hexChars[b];
				}
			)
		);
	};

	// Principal to Subaccount
	type Subaccount = [Nat8];

	public func principalToSubaccount(id : Principal) : Subaccount {
		let p = Blob.toArray(Principal.toBlob(id));
		Array.tabulate(
			32,
			func(i : Nat) : Nat8 {
				if (i >= p.size() + 1) 0 else if (i == 0) (Nat8.fromNat(p.size())) else (p[i - 1]);
			}
		)
		|> Blob.toArray(Blob.fromArray(_));
	};
};
