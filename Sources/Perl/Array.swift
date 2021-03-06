/// Provides a safe wrapper for Perl array (`AV`).
/// Performs reference counting on initialization and deinitialization.
///
/// ## Cheat Sheet
///
/// ### Array of strings
///
/// ```perl
/// my @list = ("one", "two", "three");
/// ```
///
/// ```swift
/// let list: PerlArray = ["one", "two", "three"]
/// ```
///
/// ### Array of mixed type data (PSGI response)
///
/// ```perl
/// my @response = (200, ["Content-Type" => "application/json"], ["{}"]);
/// ```
///
/// ```swift
/// let response: PerlArray = [200, ["Content-Type", "application/json"], ["{}"]]
/// ```
///
/// ### Accessing elements of the array
///
/// ```perl
/// my @list;
/// $list[0] = 10
/// push @list, 20;
/// my $first = shift @list;
/// my $second = $list[0]
/// ```
///
/// ```swift
/// let list: PerlArray = []
/// list[0] = 10
/// list.append(20)
/// let first = list.removeFirst()
/// let second = list[0]
/// ```
public final class PerlArray : PerlValue, PerlDerived {
	public typealias UnsafeValue = UnsafeAV

	/// Creates an empty Perl array.
	public convenience init() {
		self.init(perl: UnsafeInterpreter.current)
	}

	/// Creates an empty Perl array.
	public convenience init(perl: UnsafeInterpreterPointer = UnsafeInterpreter.current) {
		let av = perl.pointee.newAV()!
		self.init(noinc: av, perl: perl)
	}

	convenience init(noinc sv: UnsafeSvPointer, perl: UnsafeInterpreterPointer) throws {
		try self.init(_noinc: sv, perl: perl)
	}

	/// Initializes Perl array with elements of collection `c`.
	public convenience init<C : Collection>(_ c: C, perl: UnsafeInterpreterPointer = UnsafeInterpreter.current)
		where C.Iterator.Element : PerlSvConvertible {
		self.init(perl: perl)
		reserveCapacity(numericCast(c.count))
		for (i, v) in c.enumerated() {
			self[i] = v as? PerlScalar ?? PerlScalar(v, perl: perl)
		}
	}

	func withUnsafeAvPointer<R>(_ body: (UnsafeAvPointer, UnsafeInterpreterPointer) throws -> R) rethrows -> R {
		return try withUnsafeSvPointer { sv, perl in
			return try sv.withMemoryRebound(to: UnsafeAV.self, capacity: 1) {
				return try body($0, perl)
			}
		}
	}

	func withUnsafeCollection<R>(_ body: (UnsafeAvCollection) throws -> R) rethrows -> R {
		return try withUnsafeAvPointer {
			return try body($0.pointee.collection(perl: $1))
		}
	}

	/// A textual representation of the AV, suitable for debugging.
	public override var debugDescription: String {
		let values = map { $0.debugDescription } .joined(separator: ", ")
		return "PerlArray([\(values)])"
	}
}

//struct PerlArray: MutableCollection {
extension PerlArray : RandomAccessCollection {
	public typealias Element = PerlScalar
	public typealias Index = Int
	public typealias Iterator = IndexingIterator<PerlArray>
	public typealias Indices = CountableRange<Int>

	/// The position of the first element in a nonempty array.
	/// It is always 0 and does not respect Perl variable `$[`.
	///
	/// If the array is empty, `startIndex` is equal to `endIndex`.
	public var startIndex: Int { return 0 }

	/// The array's "past the end" position---that is, the position one greater
	/// than the last valid subscript argument.
	///
	/// If the array is empty, `endIndex` is equal to `startIndex`.
	public var endIndex: Int { return withUnsafeCollection { $0.endIndex } }

	// TODO think about accessing array beyound its lenth
	/// Accesses the element at the specified position.
	///
	/// - Parameter index: The position of the element to access. `index` must be
	///   greater than or equal to `startIndex` and less than `endIndex`.
	///
	/// - Complexity: Reading an element from an array is O(1). Writing is O(1), too.
	public subscript(i: Int) -> PerlScalar {
		get { return withUnsafeCollection { try! PerlScalar(inc: $0[i], perl: $0.perl) } }
		set {
			withUnsafeCollection { c in
				newValue.withUnsafeSvPointer { sv, _ in
					_ = c.store(i, newValue: sv)?.pointee.refcntInc()
				}
			}
		}
	}
}

extension PerlArray {
	/// Creates a Perl array from a Swift array of `PerlScalar`s.
	public convenience init(_ array: [Element]) {
		self.init()
		for (i, v) in array.enumerated() {
			self[i] = v
		}
	}
}

extension PerlArray {
	func extend(to count: Int) {
		withUnsafeCollection { $0.extend(to: count) }
	}

	func extend(by count: Int) {
		extend(to: self.count + count)
	}

	/// Reserves enough space to store the specified number of elements.
	///
	/// If you are adding a known number of elements to an array, use this method
	/// to avoid multiple reallocations. For performance reasons, the newly allocated
	/// storage may be larger than the requested capacity.
	///
	/// - Parameter minimumCapacity: The requested number of elements to store.
	///
	/// - Complexity: O(*n*), where *n* is the count of the array.
	public func reserveCapacity(_ minimumCapacity: Int) {
		extend(to: minimumCapacity)
	}

	/// Adds a new element at the end of the array.
	///
	/// Use this method to append a single element to the end of an array.
	///
	/// Because arrays increase their allocated capacity using an exponential
	/// strategy, appending a single element to an array is an O(1) operation
	/// when averaged over many calls to the `append(_:)` method. When an array
	/// has additional capacity, appending an element is O(1). When an array
	/// needs to reallocate storage before appending, appending is O(*n*),
	/// where *n* is the length of the array.
	///
	/// - Parameter sv: The element to append to the array.
	///
	/// - Complexity: Amortized O(1) over many additions.
	public func append(_ sv: Element) {
		withUnsafeCollection { c in
			sv.withUnsafeSvPointer { sv, _ in
				c.append(sv.pointee.refcntInc())
			}
		}
	}

	// TODO - SeeAlso: `popFirst()`
	/// Removes and returns the first element of the array.
	///
	/// The array can be empty. In this case undefined `PerlScalar` is returned.
	///
	/// - Returns: The first element of the array.
	///
	/// - Complexity: O(1)
	public func removeFirst() -> Element {
		return withUnsafeCollection { try! PerlScalar(noinc: $0.removeFirst(), perl: $0.perl) }
	}
}

extension PerlArray: ExpressibleByArrayLiteral {
	/// Creates Perl array from the given array literal.
	///
	/// Do not call this initializer directly. It is used by the compiler
	/// when you use an array literal. Instead, create a new array by using an
	/// array literal as its value. To do this, enclose a comma-separated list of
	/// values in square brackets. For example:
	///
	/// ```swift
	/// let array: PerlArray = [200, "OK"]
	/// ```
	///
	/// - Parameter elements: A variadic list of elements of the new array.
	public convenience init (arrayLiteral elements: Element...) {
		self.init(elements)
	}
}

extension Array where Element : PerlSvConvertible {
	/// Creates an array from the Perl array.
	///
	/// - Parameter av: Perl array with elements compatible with `Element`.
	///   If some of elements cannot be converted to `Element` then
	///   an error is thrown.
	///
	/// - Complexity: O(*n*), where *n* is the count of the array.
	public init(_ av: PerlArray) throws {
		self = try av.withUnsafeCollection { uc in
			try uc.map { try Element.fromUnsafeSvPointer($0, perl: uc.perl) }
		}
	}

	// TODO something with this constructor. It either shouldn't use autoDeref,
	// because PerlScalar cannot contain AV, or should take PerlValue as an argument.
	public init?(_ sv: PerlScalar) throws {
		defer { _fixLifetime(sv) }
		let (usv, perl) = sv.withUnsafeSvPointer { $0 }
		guard let av = try UnsafeAvPointer(autoDeref: usv, perl: perl) else { return nil }
		self = try av.pointee.collection(perl: perl).map { try Element.fromUnsafeSvPointer($0, perl: perl) }
	}
}
