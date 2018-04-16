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
        let s = StateAndCallback(state: (endCount: 0, hasPassedInitial: false), callback: callback)
        
        for signal in signals {
            s += signal.onEventType { eventType in
                s.lock()
                
                if case .initial = eventType {
                    guard !s.val.hasPassedInitial else { return s.unlock() }
                    s.val.hasPassedInitial = true
                }
                
                // Don't forward non error ends unless all have ended.
                if case .event(.end(nil)) = eventType {
                    s.val.endCount += 1
                    guard s.val.endCount == count else { return s.unlock() }
                }
                
                s.unlock()
                s.call(eventType)
            }
        }
        
        return s
    })
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
        let s = StateAndCallback(state: Array(repeating: S.Iterator.Element.Value?.none, count: signals.count), callback: callback)
        
        for i in signals.indices {
            let signal = signals[i]
            s += signal.onEventType { eventType in
                switch eventType {
                case .initial(nil) where i == 0:
                    s.call(.initial(nil))
                case .initial(nil): break
                case .initial(let val?):
                    s.lock()
                    s.val[i] = val
                    let combines = s.val.compactMap { $0 }
                    if combines.count == s.val.count {
                        s.unlock()
                        s.call(.initial(combines))
                    } else {
                        s.unlock()
                    }
                case .event(.value(let val)):
                    s.lock()
                    s.val[i] = val
                    let combines = s.val.compactMap { $0 }
                    if combines.count == s.val.count {
                        s.unlock()
                        s.call(.event(.value(combines)))
                    } else {
                        s.unlock()
                    }
                case .event(.end(let error)):
                    s.call(.event(.end(error)))
                }
            }
        }
        
        return s
    })
}

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
public func combineLatest<A: SignalProvider, B: SignalProvider>(_ a: A, _ b: B) -> CoreSignal<A.Kind.DropWrite, (A.Value, B.Value)> {
    let aSignal = a.providedSignal
    let bSignal = b.providedSignal
    return CoreSignal(onEventType: { callback in
        let s = StateAndCallback(state: (a: A.Value?.none, b: B.Value?.none), callback: callback)
        
        s += aSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil):
                s.call(.initial(nil))
            case .initial(let val?):
                s.lock()
                s.val.a = val
                if let b = s.val.b {
                    s.unlock()
                    s.call(.initial((val, b)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.a = val
                if let b = s.val.b {
                    s.unlock()
                    s.call(.event(.value((val, b))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        s += bSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                s.lock()
                s.val.b = val
                if let a = s.val.a {
                    s.unlock()
                    s.call(.initial((a, val)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.b = val
                if let a = s.val.a {
                    s.unlock()
                    s.call(.event(.value((a, val))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        return s
    })
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider>(_ a: A, _ b: B, _ c: C) -> CoreSignal<A.Kind.DropWrite, (A.Value, B.Value, C.Value)> {
    let aSignal = a.providedSignal
    let bSignal = b.providedSignal
    let cSignal = c.providedSignal
    return CoreSignal(onEventType: { callback in
        let s = StateAndCallback(state: (a: A.Value?.none, b: B.Value?.none, c: C.Value?.none), callback: callback)

        s += aSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil):
                s.call(.initial(nil))
            case .initial(let val?):
                s.lock()
                s.val.a = val
                if let b = s.val.b, let c = s.val.c {
                    s.unlock()
                    s.call(.initial((val, b, c)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.a = val
                if let b = s.val.b, let c = s.val.c {
                    s.unlock()
                    s.call(.event(.value((val, b, c))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        s += bSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                s.lock()
                s.val.b = val
                if let a = s.val.a, let c = s.val.c {
                    s.unlock()
                    s.call(.initial((a, val, c)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.b = val
                if let a = s.val.a, let c = s.val.c {
                    s.unlock()
                    s.call(.event(.value((a, val, c))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        s += cSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                s.lock()
                s.val.c = val
                if let a = s.val.a, let b = s.val.b {
                    s.unlock()
                    s.call(.initial((a, b, val)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.c = val
                if let a = s.val.a, let b = s.val.b {
                    s.unlock()
                    s.call(.event(.value((a, b, val))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        return s
    })
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D) -> CoreSignal<A.Kind.DropWrite, (A.Value, B.Value, C.Value, D.Value)> {
    let aSignal = a.providedSignal
    let bSignal = b.providedSignal
    let cSignal = c.providedSignal
    let dSignal = d.providedSignal
    
    return CoreSignal(onEventType: { callback in
        let s = StateAndCallback(state: (a: A.Value?.none, b: B.Value?.none, c: C.Value?.none, d: D.Value?.none), callback: callback)
        
        s += aSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil):
                s.call(.initial(nil))
            case .initial(let val?):
                s.lock()
                s.val.a = val
                if let b = s.val.b, let c = s.val.c, let d = s.val.d {
                    s.unlock()
                    s.call(.initial((val, b, c, d)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.a = val
                if let b = s.val.b, let c = s.val.c, let d = s.val.d {
                    s.unlock()
                    s.call(.event(.value((val, b, c, d))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        s += bSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                s.lock()
                s.val.b = val
                if let a = s.val.a, let c = s.val.c, let d = s.val.d {
                    s.unlock()
                    s.call(.initial((a, val, c, d)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.b = val
                if let a = s.val.a, let c = s.val.c, let d = s.val.d {
                    s.unlock()
                    s.call(.event(.value((a, val, c, d))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        s += cSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                s.lock()
                s.val.c = val
                if let a = s.val.a, let b = s.val.b, let d = s.val.d {
                    s.unlock()
                    s.call(.initial((a, b, val, d)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.c = val
                if let a = s.val.a, let b = s.val.b, let d = s.val.d {
                    s.unlock()
                    s.call(.event(.value((a, b, val, d))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        s += dSignal.onEventType { eventType in
            switch eventType {
            case .initial(nil): break
            case .initial(let val?):
                s.lock()
                s.val.d = val
                if let a = s.val.a, let b = s.val.b, let c = s.val.c {
                    s.unlock()
                    s.call(.initial((a, b, c, val)))
                } else {
                    s.unlock()
                }
            case .event(.value(let val)):
                s.lock()
                s.val.d = val
                if let a = s.val.a, let b = s.val.b, let c = s.val.c {
                    s.unlock()
                    s.call(.event(.value((a, b, c, val))))
                } else {
                    s.unlock()
                }
            case .event(.end(let error)):
                s.call(.event(.end(error)))
            }
        }
        
        return s
    })
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value)> {
    return combineLatest(combineLatest(a, b, c), combineLatest(d, e)).map {
        let ((a, b, c), (d, e)) = $0
        return (a, b, c, d, e)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f)).map {
        let ((a, b, c, d), (e, f)) = $0
        return (a, b, c, d, e, f)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g)).map {
        let ((a, b, c, d), (e, f, g)) = $0
        return (a, b, c, d, e, f, g)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h)).map {
        let ((a, b, c, d), (e, f, g, h)) = $0
        return (a, b, c, d, e, f, g, h)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g), combineLatest(h, i)).map {
        let ((a, b, c, d), (e, f, g), (h, i)) = $0
        return (a, b, c, d, e, f, g, h, i)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j)) = $0
        return (a, b, c, d, e, f, g, h, i, j)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider, K :SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J, _ k: K) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value, K.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j, k)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j, k)) = $0
        return (a, b, c, d, e, f, g, h, i, j, k)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider, K: SignalProvider, L: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J, _ k: K, _ l: L) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value, K.Value, L.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j, k, l)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j, k, l)) = $0
        return (a, b, c, d, e, f, g, h, i, j, k, l)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider, K: SignalProvider, L: SignalProvider, M: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J, _ k: K, _ l: L, _ m: M) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value, K.Value, L.Value, M.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j, k), combineLatest(l, m)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j, k), (l, m)) = $0
        return (a, b, c, d, e, f, g, h, i, j, k, l, m)
    }
}

/// Returns a new signal combining the latest values from the provided signals
/// - Note: See `combineLatest(_:, _:)` for more info.
public func combineLatest<A: SignalProvider, B: SignalProvider, C: SignalProvider, D: SignalProvider, E: SignalProvider, F: SignalProvider, G: SignalProvider, H: SignalProvider, I: SignalProvider, J: SignalProvider, K: SignalProvider, L: SignalProvider, M: SignalProvider, N: SignalProvider>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J, _ k: K, _ l: L, _ m: M, _ n: N) -> CoreSignal<A.Kind.DropWrite.DropWrite.DropWrite, (A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value, K.Value, L.Value, M.Value, N.Value)> {
    return combineLatest(combineLatest(a, b, c, d), combineLatest(e, f, g, h), combineLatest(i, j, k, l), combineLatest(m, n)).map {
        let ((a, b, c, d), (e, f, g, h), (i, j, k, l), (m, n)) = $0
        return (a, b, c, d, e, f, g, h, i, j, k, l, m, n)
    }
}

