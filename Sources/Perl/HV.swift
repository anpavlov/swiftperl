final class PerlHV : PerlSvCastable {
	typealias Struct = UnsafeHV
	typealias Pointer = UnsafeHvPointer
	let unsafeCollection: UnsafeHvCollection

	var pointer: Pointer { return unsafeCollection.hv }
	var perl: UnsafeInterpreterPointer { return unsafeCollection.perl }

	convenience init() {
		self.init(perl: UnsafeInterpreter.current)
	}

	init(perl: UnsafeInterpreterPointer = UnsafeInterpreter.current) {
		unsafeCollection = perl.pointee.newHV().pointee.collection(perl: perl)
	}

	init (_ p: Pointer, perl: UnsafeInterpreterPointer = UnsafeInterpreter.current) {
		unsafeCollection = p.pointee.collection(perl: perl)
		pointer.pointee.refcntInc()
	}

	deinit {
		pointer.pointee.refcntDec(perl: perl)
	}

	convenience init?(_ sv: PerlSV) throws {
		guard let hv = try UnsafeHvPointer(sv.pointer, perl: sv.perl) else { return nil }
		self.init(hv, perl: sv.perl)
	}

	convenience init<T : PerlSVConvertible>(_ dict: [String: T]) {
		self.init()
		for (k, v) in dict {
			self[k] = v as? PerlSV ?? PerlSV(v)
		}
	}

	func value<T: PerlSVConvertible>() throws -> [String: T] {
		var dict = [String: T]()
		for (k, v) in pointer.pointee.collection(perl: perl) {
			dict[k] = try T.promoteFromUnsafeSV(v, perl: perl)
		}
		return dict
	}
}

extension PerlHV: Sequence {
	typealias Key = String
	typealias Value = PerlSV
	typealias Element = (key: Key, value: Value)

	func makeIterator () -> Iterator {
		return Iterator(unsafeCollection)
	}

	struct Iterator: IteratorProtocol {
		let i: UnsafeHvCollection.Iterator

		init(_ c: UnsafeHvCollection) {
			i = c.makeIterator()
		}

		func next() -> Element? {
			guard let u = i.next() else { return nil }
			return (key: u.key, value: PerlSV(u.value, perl: i.c.perl))
		}
	}

	subscript (key: Key) -> PerlSV? {
		get {
			guard let sv = unsafeCollection[key] else { return nil }
			return PerlSV(sv, perl: unsafeCollection.perl)
		}
		set {
			if let value = newValue {
				unsafeCollection.store(key, newValue: value.pointer)?.pointee.refcntInc()
			} else {
				unsafeCollection.delete(key)
			}
		}
	}
}

extension PerlHV {
	convenience init(_ dict: [Key: Value]) {
		self.init()
		for (k, v) in dict {
			self[k] = v
		}
	}

	convenience init(_ elements: [(Key, Value)]) {
		self.init()
		for (k, v) in elements {
			self[k] = v
		}
	}
}

extension PerlHV : ExpressibleByDictionaryLiteral {
	convenience init(dictionaryLiteral elements: (Key, Value)...) {
		self.init(elements)
	}
}

// where Key == String, but it is unsupported
extension Dictionary where Value : PerlSVDefinitelyConvertible {
	init(_ hv: PerlHV) {
		self.init()
		for (k, v) in hv {
			self[k as! Key] = Value.promoteFromUnsafeSV(v.pointer, perl: hv.perl)
		}
	}
}

// where Key == String, but it is unsupported
extension Dictionary where Value : PerlSVProbablyConvertible {
	init(_ hv: PerlHV) throws {
		self.init()
		for (k, v) in hv {
			self[k as! Key] = try Value.promoteFromUnsafeSV(v.pointer, perl: hv.perl)
		}
	}
}

// where Key == String, but it is unsupported
extension Dictionary where Value : PerlSVConvertible {
	init?(_ sv: PerlSV) throws {
		guard let hv = try UnsafeHvPointer(sv.pointer, perl: sv.perl) else { return nil }
		self.init()
		for (k, v) in hv.pointee.collection(perl: sv.perl) {
			self[k as! Key] = try Value.promoteFromUnsafeSV(v, perl: sv.perl)
		}
	}
}
