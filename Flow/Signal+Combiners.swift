//
//  Signal+Combiners.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation

/// Returns a new signal merging the values emitted from `signals`
///
///     a)---b---c------d-|
///          |   |      |
///     0)----------1------2---|
///          |   |  |   |  |
///     +--------------------+
///     | merge()            |
///     +--------------------+
///          |   |  |   |  |
///     a)---b---c--1---c--2---|
///
/// - Note: Will terminate when all `signals` have termianated or when any signal termiates with an error.
public func merge<Signals: Sequence>(_ signals: Signals) -> CoreSignal<Signals.Iterator.Element.Kind.DropWrite, Signals.Iterator.Element.Value> where Signals.Iterator.Element: SignalProvider {
    let signals = signals.map { $0.providedSignal }
    let count = signals.count
    return CoreSignal(onEventType: { callback in
        let state = StateAndCallback(state: (endCount: 0, hasPassedInitial: false), callback: callback)

        for signal in signals {
            state += signal.onEventType { eventType in
                state.lock()

                if case .initial = eventType {
                    guard !state.val.hasPassedInitial else { return state.unlock() }
                    state.val.hasPassedInitial = true
                }

                // Don't forward non error ends unless all have ended.
                if case .event(.end(nil)) = eventType {
                    state.val.endCount += 1
                    guard state.val.endCount == count else { return state.unlock() }
                }

                state.unlock()
                state.call(eventType)
            }
        }

        return state
    })
}

/// Returns a new signal combining each value from self with the latest value from the second signal.
///
///     a)---------b------c-----d--|
///                |      |     |
///     0)------1------2-----------|
///             |      |
///     +--------------------------+
///     | withLatestFrom()         |
///     +--------------------------+
///                |      |     |
///     (a,0))---(b,1)--(c,2)-(d,2)|
///
/// - Note: Will terminate when any signal terminates with an error.
public extension SignalProvider {
    func withLatestFrom<S: SignalProvider>(_ other: S) -> CoreSignal<Kind.DropWrite, (Value, S.Value)> where Kind.DropWrite == S.Kind.DropWrite {
        let signal = providedSignal
        let otherSignal = other.providedSignal
        return CoreSignal(onEventType: { callback in
            let state = StateAndCallback(state: S.Value?.none, callback: callback) // previous

            state += otherSignal.onEventType { eventType in
                switch eventType {
                case .initial(nil):
                    break
                case .initial(let val?):
                    state.protectedVal = val
                case .event(.value(let val)):
                    state.protectedVal = val
                case .event(.end(let error)):
                    return state.call(.event(.end(error)))
                }
            }

            state += signal.onEventType { eventType in
                switch eventType {
                case .initial(nil):
                    state.call(.initial(nil))
                case .initial(let val?):
                    if let otherValue = state.protectedVal {
                        state.call(.initial((val, otherValue)))
                    }
                case .event(.value(let val)):
                    if let otherValue = state.protectedVal {
                        state.call(.event(.value((val, otherValue))))
                    }
                case .event(.end(let error)):
                    state.call(.event(.end(error)))
                }
            }

            return state
        })
    }

    /// Returns a new signal combining the latest value of `self` with the provided `object` up until `object` gets deallocated.
    /// This is a convenience helper for breaking retain cycles in situations such as:
    ///
    ///     class Class {
    ///       let bag = DisposeBag()
    ///
    ///       func setupUsingWeakCapture() {
    ///         bag += someSignal.onValue { [weak self] value in
    ///           guard let `self` = self else { return }
    ///           self.handle(value)
    ///       }
    ///
    ///       func setupWithWeak() {
    ///         bag += someSignal.with(weak: self).onValue { value, `self` in
    ///           self.handle(value)
    ///       }
    ///     }
    ///
    ///     a)---------b------c-----d--|
    ///                |      |     |
    ///     +--------------------------+
    ///     | with(weak: o)            |
    ///     +--------------------------+
    ///                |      |     |
    ///     (a,o))---(b,o)--(c,o)-(d,o)|
    ///
    func with<T: AnyObject>(weak object: T) -> CoreSignal<Kind.DropWrite, (Value, T)> {
        let signal = providedSignal
        return CoreSignal(onEventType: { [weak object] callback in
            let state = StateAndCallback(state: (), callback: callback)

            guard let object = object else {
                return state
            }

            state += deallocSignal(for: object).onValue {
                state.dispose()
            }

            state += signal.onEventType { [weak object] eventType in
                guard let object = object else {
                    state.call(.event(.end))
                    return
                }

                switch eventType {
                case .initial(nil):
                    state.call(.initial(nil))
                case .initial(let value?):
                    state.call(.initial((value, object)))
                case .event(.value(let value)):
                    state.call(.event(.value((value, object))))
                case .event(.end(let error)):
                    state.call(.event(.end(error)))
                }
            }

            return state
        })
    }

    /// Returns a new signal combining the latest tuple value of `self` with the provided `object` up until `object` gets deallocated.
    ///
    ///     bag += combineLatest(a, b).with(weak: self).onValue { a, b, `self` in
    ///       self.handle(a, b)
    ///     }
    ///
    ///     (a,1))-----(b,1)-----(b,2)--|
    ///                  |         |    |
    ///     +---------------------------+
    ///     | with(weak: o)             |
    ///     +---------------------------+
    ///                  |        |     |
    ///     (a,1,o))--(b,1,o)--(b,2,o)--|
    ///
    /// - Note: See `with(weak:)` for more info.
    func with<T: AnyObject, A, B>(weak object: T) -> CoreSignal<Kind.DropWrite.DropWrite, (A, B, T)> where Value == (A, B) {
        return with(weak: object).map { ($0.0, $0.1, $1) }
    }

    /// Returns a new signal combining the latest tuple value of `self` with the provided `object` up until `object` gets deallocated.
    /// - Note: See `with(weak:)` for more info.
    func with<T: AnyObject, A, B, C>(weak object: T) -> CoreSignal<Kind.DropWrite.DropWrite, (A, B, C, T)> where Value == (A, B, C) {
        return with(weak: object).map { ($0.0, $0.1, $0.2, $1) }
    }

    /// Returns a new signal combining the latest tuple value of `self` with the provided `object` up until `object` gets deallocated.
    /// - Note: See `with(weak:)` for more info.
    func with<T: AnyObject, A, B, C, D>(_ object: T) -> CoreSignal<Kind.DropWrite.DropWrite, (A, B, C, D, T)> where Value == (A, B, C, D) {
        return with(weak: object).map { ($0.0, $0.1, $0.2, $0.3, $1) }
    }

    /// Returns a new signal combining the latest tuple value of `self` with the provided `object` up until `object` gets deallocated.
    /// - Note: See `with(weak:)` for more info.
    func with<T: AnyObject, A, B, C, D, E>(_ object: T) -> CoreSignal<Kind.DropWrite.DropWrite, (A, B, C, D, E, T)> where Value == (A, B, C, D, E) {
        return with(weak: object).map { ($0.0, $0.1, $0.2, $0.3, $0.4, $1) }
    }

    /// Returns a new signal combining the latest tuple value of `self` with the provided `object` up until `object` gets deallocated.
    /// - Note: See `with(weak:)` for more info.
    func with<T: AnyObject, A, B, C, D, E, F>(_ object: T) -> CoreSignal<Kind.DropWrite.DropWrite, (A, B, C, D, E, F, T)> where Value == (A, B, C, D, E, F) {
        return with(weak: object).map { ($0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $1) }
    }

    /// Returns a new signal combining the latest tuple value of `self` with the provided `object` up until `object` gets deallocated.
    /// - Note: See `with(weak:)` for more info.
    func with<T: AnyObject, A, B, C, D, E, F, G>(_ object: T) -> CoreSignal<Kind.DropWrite.DropWrite, (A, B, C, D, E, F, G, T)> where Value == (A, B, C, D, E, F, G) {
        return with(weak: object).map { ($0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $1) }
    }

    /// Returns a new signal combining the latest tuple value of `self` with the provided `object` up until `object` gets deallocated.
    /// - Note: See `with(weak:)` for more info.
    func with<T: AnyObject, A, B, C, D, E, F, G, H>(_ object: T) -> CoreSignal<Kind.DropWrite.DropWrite, (A, B, C, D, E, F, G, H, T)> where Value == (A, B, C, D, E, F, G, H) {
        return with(weak: object).map { ($0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $0.7, $1) }
    }

    /// Returns a new signal combining the latest tuple value of `self` with the provided `object` up until `object` gets deallocated.
    /// - Note: See `with(weak:)` for more info.
    func with<T: AnyObject, A, B, C, D, E, F, G, H, I>(_ object: T) -> CoreSignal<Kind.DropWrite.DropWrite, (A, B, C, D, E, F, G, H, I, T)> where Value == (A, B, C, D, E, F, G, H, I) {
        return with(weak: object).map { ($0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $0.7, $0.8, $1) }
    }
}

/// Returns a new signal signaling the provided `object` every time `self` signals, up until `object` gets deallocated.
///
///     bag += button.with(weak: self).onValue { `self` in
///         self.handleButton()
///     }
///
///     ())-----()-----()--|
///             |      |   |
///     +------------------+
///     | with(weak: o)    |
///     +------------------+
///             |      |   |
///     o)------o------o---|
///
/// - Note: See `with(weak:)` for more info.
public extension SignalProvider where Value == () {
    func with<T: AnyObject>(weak object: T) -> CoreSignal<Kind.DropWrite.DropWrite, T> {
        return with(weak: object).map { $1 }
    }
}

/// Returns a new signal merging the values emitted from `signals`
///
///     a)---b---c------d-|
///          |   |      |
///     0)----------1------2---|
///          |   |  |   |  |
///     +--------------------+
///     | merge()            |
///     +--------------------+
///          |   |  |   |  |
///     a)---b---c--1---c--2---|
///
/// - Note: Will terminate when all `signals` have termianated or when any signal termiates with an error.
public func merge<S: SignalProvider>(_ signals: S...) -> CoreSignal<S.Kind.DropWrite, S.Value> {
    return merge(signals)
}

/// Returns a new signal combining the latest values from the provided signals
public func combineLatest<S: Sequence>(_ signals: S) -> CoreSignal<S.Iterator.Element.Kind.DropWrite, [S.Iterator.Element.Value]> where S.Iterator.Element: SignalProvider {
    let signals = signals.map { $0.providedSignal }
    guard !signals.isEmpty else {
        return CoreSignal(onEventType: { callback in
            callback(.initial([]))
            return NilDisposer()
        })
    }

    return CoreSignal(onEventType: { callback in
        let state = StateAndCallback(state: Array(repeating: S.Iterator.Element.Value?.none, count: signals.count), callback: callback)

        for i in signals.indices {
            let signal = signals[i]
            state += signal.onEventType { eventType in
                switch eventType {
                case .initial(nil) where i == 0:
                    state.call(.initial(nil))
                case .initial(nil): break
                case .initial(let val?):
                    state.lock()
                    state.val[i] = val
                    let combines = state.val.compactMap { $0 }
                    if combines.count == state.val.count {
                        state.unlock()
                        state.call(.initial(combines))
                    } else {
                        state.unlock()
                    }
                case .event(.value(let val)):
                    state.lock()
                    state.val[i] = val
                    let combines = state.val.compactMap { $0 }
                    if combines.count == state.val.count {
                        state.unlock()
                        state.call(.event(.value(combines)))
                    } else {
                        state.unlock()
                    }
                case .event(.end(let error)):
                    state.call(.event(.end(error)))
                }
            }
        }

        return state
    })
}

// swiftlint:disable identifier_name

/// Returns a new signal combining the latest values from the provided signals
///
///     ---a---b-------c------------|
///        |   |       |            |
///     ----------1----------2--------->
///        |   |  |    |     |      |
///     +-----------------------------+
///     | combineLatest() - plain     |
///     +-----------------------------+
///               |    |     |      |
///     ----------b1---c1----c2-----|
///
///     a)---b---------c-------------|
///          |         |             |
///     0)---------1---------2---------->
///          |     |   |     |       |
///     +------------------------------+
///     | combineLatest() - readable   |
///     +------------------------------+
///          |    |    |     |       |
///     a0)--b0---b1---c1----c2------|
///
/// - Note: If `a` and `b` both have sources their current values will be used as initial values.
public func combineLatest<A: SignalProvider, B: SignalProvider>(_ a: A, _ b: B) -> CoreSignal<A.Kind.DropWrite, (A.Value, B.Value)> where B.Kind.DropWrite == A.Kind.DropWrite {
    let aSignal = a.providedSignal
    let bSignal = b.providedSignal
    return CoreSignal(onEventType: { callback in
        let state = StateAndCallback(state: (a: A.Value?.none, b: B.Value?.none), callback: callback)

        state += aSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil):
                state.call(.initial(nil))
            case .initial(let val?):
                state.lock()
                state.val.a = val
                if let b = state.val.b {
                    state.unlock()
                    state.call(.initial((val, b)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.a = val
                if let b = state.val.b {
                    state.unlock()
                    state.call(.event(.value((val, b))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        state += bSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                state.lock()
                state.val.b = val
                if let a = state.val.a {
                    state.unlock()
                    state.call(.initial((a, val)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.b = val
                if let a = state.val.a {
                    state.unlock()
                    state.call(.event(.value((a, val))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        return state
    })
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider>(_ a: A, _ b: B, _ c: C) -> CoreSignal<A.Kind.DropWrite, (A.Value, B.Value, C.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite {
    let aSignal = a.providedSignal
    let bSignal = b.providedSignal
    let cSignal = c.providedSignal
    return CoreSignal(onEventType: { callback in
        let state = StateAndCallback(state: (a: A.Value?.none, b: B.Value?.none, c: C.Value?.none), callback: callback)

        state += aSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil):
                state.call(.initial(nil))
            case .initial(let val?):
                state.lock()
                state.val.a = val
                if let b = state.val.b, let c = state.val.c {
                    state.unlock()
                    state.call(.initial((val, b, c)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.a = val
                if let b = state.val.b, let c = state.val.c {
                    state.unlock()
                    state.call(.event(.value((val, b, c))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        state += bSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                state.lock()
                state.val.b = val
                if let a = state.val.a, let c = state.val.c {
                    state.unlock()
                    state.call(.initial((a, val, c)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.b = val
                if let a = state.val.a, let c = state.val.c {
                    state.unlock()
                    state.call(.event(.value((a, val, c))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        state += cSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                state.lock()
                state.val.c = val
                if let a = state.val.a, let b = state.val.b {
                    state.unlock()
                    state.call(.initial((a, b, val)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.c = val
                if let a = state.val.a, let b = state.val.b {
                    state.unlock()
                    state.call(.event(.value((a, b, val))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        return state
    })
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D) -> CoreSignal<A.Kind.DropWrite, (A.Value, B.Value, C.Value, D.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite {
    let aSignal = a.providedSignal
    let bSignal = b.providedSignal
    let cSignal = c.providedSignal
    let dSignal = d.providedSignal

    return CoreSignal(onEventType: { callback in
        let state = StateAndCallback(state: (a: A.Value?.none, b: B.Value?.none, c: C.Value?.none, d: D.Value?.none), callback: callback)

        state += aSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil):
                state.call(.initial(nil))
            case .initial(let val?):
                state.lock()
                state.val.a = val
                if let b = state.val.b, let c = state.val.c, let d = state.val.d {
                    state.unlock()
                    state.call(.initial((val, b, c, d)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.a = val
                if let b = state.val.b, let c = state.val.c, let d = state.val.d {
                    state.unlock()
                    state.call(.event(.value((val, b, c, d))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        state += bSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                state.lock()
                state.val.b = val
                if let a = state.val.a, let c = state.val.c, let d = state.val.d {
                    state.unlock()
                    state.call(.initial((a, val, c, d)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.b = val
                if let a = state.val.a, let c = state.val.c, let d = state.val.d {
                    state.unlock()
                    state.call(.event(.value((a, val, c, d))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        state += cSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                state.lock()
                state.val.c = val
                if let a = state.val.a, let b = state.val.b, let d = state.val.d {
                    state.unlock()
                    state.call(.initial((a, b, val, d)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.c = val
                if let a = state.val.a, let b = state.val.b, let d = state.val.d {
                    state.unlock()
                    state.call(.event(.value((a, b, val, d))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        state += dSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                state.lock()
                state.val.d = val
                if let a = state.val.a, let b = state.val.b, let c = state.val.c {
                    state.unlock()
                    state.call(.initial((a, b, c, val)))
                } else {
                    state.unlock()
                }
            case .event(.value(let val)):
                state.lock()
                state.val.d = val
                if let a = state.val.a, let b = state.val.b, let c = state.val.c {
                    state.unlock()
                    state.call(.event(.value((a, b, c, val))))
                } else {
                    state.unlock()
                }
            case .event(.end(let error)):
                state.call(.event(.end(error)))
            }
        }

        return state
    })
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c), combineLatest(d, e)).map {
        let ((a, b, c), (d, e)) = $0
        return (a, b, c, d, e)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f)).map {
        let ((a, b, c, d), (e, f)) = $0
        return (a, b, c, d, e, f)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite, G.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g)).map {
        let ((a, b, c, d), (e, f, g)) = $0
        return (a, b, c, d, e, f, g)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite, G.Kind.DropWrite == A.Kind.DropWrite, H.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h)).map {
        let ((a, b, c, d), (e, f, g, h)) = $0
        return (a, b, c, d, e, f, g, h)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite, G.Kind.DropWrite == A.Kind.DropWrite, H.Kind.DropWrite == A.Kind.DropWrite, I.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g), combineLatest(h, i)).map {
        let ((a, b, c, d), (e, f, g), (h, i)) = $0
        return (a, b, c, d, e, f, g, h, i)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite, G.Kind.DropWrite == A.Kind.DropWrite, H.Kind.DropWrite == A.Kind.DropWrite, I.Kind.DropWrite == A.Kind.DropWrite, J.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j)) = $0
        return (a, b, c, d, e, f, g, h, i, j)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider, K: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J, _ k: K) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value, K.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite, G.Kind.DropWrite == A.Kind.DropWrite, H.Kind.DropWrite == A.Kind.DropWrite, I.Kind.DropWrite == A.Kind.DropWrite, J.Kind.DropWrite == A.Kind.DropWrite, K.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j, k)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j, k)) = $0
        return (a, b, c, d, e, f, g, h, i, j, k)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider, K: SignalProvider, L: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J, _ k: K, _ l: L) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value, K.Value, L.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite, G.Kind.DropWrite == A.Kind.DropWrite, H.Kind.DropWrite == A.Kind.DropWrite, I.Kind.DropWrite == A.Kind.DropWrite, J.Kind.DropWrite == A.Kind.DropWrite, K.Kind.DropWrite == A.Kind.DropWrite, L.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j, k, l)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j, k, l)) = $0
        return (a, b, c, d, e, f, g, h, i, j, k, l)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider, K: SignalProvider, L: SignalProvider, M: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J, _ k: K, _ l: L, _ m: M) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value, K.Value, L.Value, M.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite, G.Kind.DropWrite == A.Kind.DropWrite, H.Kind.DropWrite == A.Kind.DropWrite, I.Kind.DropWrite == A.Kind.DropWrite, J.Kind.DropWrite == A.Kind.DropWrite, K.Kind.DropWrite == A.Kind.DropWrite, L.Kind.DropWrite == A.Kind.DropWrite, M.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j, k), combineLatest(l, m)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j, k), (l, m)) = $0
        return (a, b, c, d, e, f, g, h, i, j, k, l, m)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider, K: SignalProvider, L: SignalProvider, M: SignalProvider, N: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J, _ k: K, _ l: L, _ m: M, _ n: N) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value, K.Value, L.Value, M.Value, N.Value)> where B.Kind.DropWrite == A.Kind.DropWrite, C.Kind.DropWrite == A.Kind.DropWrite, D.Kind.DropWrite == A.Kind.DropWrite, E.Kind.DropWrite == A.Kind.DropWrite, F.Kind.DropWrite == A.Kind.DropWrite, G.Kind.DropWrite == A.Kind.DropWrite, H.Kind.DropWrite == A.Kind.DropWrite, I.Kind.DropWrite == A.Kind.DropWrite, J.Kind.DropWrite == A.Kind.DropWrite, K.Kind.DropWrite == A.Kind.DropWrite, L.Kind.DropWrite == A.Kind.DropWrite, M.Kind.DropWrite == A.Kind.DropWrite, N.Kind.DropWrite == A.Kind.DropWrite {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j, k, l), combineLatest(m, n)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j, k, l), (m, n)) = $0
        return (a, b, c, d, e, f, g, h, i, j, k, l, m, n)
    }
}
