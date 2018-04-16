//
//  Signal+Transforms.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation


public extension SignalProvider {
    /// Returns a new signal where values are replaced with `()`, equivalent to `map { _ in }`.
    func toVoid() -> CoreSignal<Kind.DropWrite, ()> {
        return map { _ in }
    }
    
    /// Returns a new signal where the values in `values` will be immediately signaled and before any other values are signaled from `self`.
    ///
    ///     ?)---1----2----3--|
    ///          |    |    |
    ///     +----------------+
    ///     | start(with: 5) |
    ///     +----------------+
    ///          |    |    |
    ///     5----1----2----3--|
    func start(with values: Value...) -> CoreSignal<Kind, Value> {
        let signal = providedSignal
        return CoreSignal(setValue: signal.setter, onEventType: { c in
            return signal.onEventType { eventType in
                c(eventType)
                if case .initial = eventType {
                    for value in values {
                        c(.event(.value(value)))
                    }
                }
            }
        })
    }
    
    /// Returns a new signal with the added behaviour of using the `.shared` `SignalOptions`.
    /// - Note: See `SignalOptions.shared` for more info
    func shared() -> CoreSignal<Kind, Value> {
        let signal = providedSignal
        let shared = SharedState<Value>()
        
        return CoreSignal(setValue: signal.setter, onEventType: { callback in
            let key = generateKey()
            shared.lock()
            
            if shared.firstCallback == nil {
                shared.firstCallback = (key, callback)
                shared.unlock()
                
                let d = signal.onEventType { eventType in
                    if case .initial(let val?) = eventType {
                        shared.updateLast(to: val)
                    }
                    
                    shared.callAll(with: eventType)
                    
                    if case .event(.value(let val)) = eventType, Kind.isReadable {
                        shared.updateLast(to: val)
                    }
                }
                shared.lock()
                shared.disposable = d
                shared.unlock()
            } else {
                shared.remainingCallbacks[key] = callback
                let last = shared.lastReceivedValue
                shared.unlock()
                callback(.initial(last))
            }
            
            return NoLockKeyDisposer(key, shared.remove)
        })
    }

    /// Returns a new signal transforming values using `transform` unless `transform` returns nil where the value will be discarded.
    ///
    ///     0)---1----2----3----4-----|
    ///          |    |    |    |
    ///     +-------------------------------------------+
    ///     | compactMap { v in v.isOdd() ? nil : v*2 } |
    ///     +-------------------------------------------+
    ///               |         |
    ///     ----------4---------8-----|
    func compactMap<T>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> T?) -> CoreSignal<Kind.DropReadWrite, T> {
        let signal = providedSignal
        return CoreSignal(onEventType: { c in
            signal.onEventType(on: scheduler) { eventType in
                switch eventType {
                case .initial:
                    c(.initial(nil))
                case .event(.value(let v)):
                    transform(v).map { c(.event(.value($0))) }
                case let .event(.end(error)):
                    c(.event(.end(error)))
                }
            }
        })
    }

    /// Returns a new signal forwarding the values from the signal returned from `transform`.
    ///
    ///     ---a--------b------------|
    ///        |        |
    ///     +-------------------------+
    ///     | flatMapLatest() - plain |
    ///     +-------------------------+
    ///     ---s1-------s2-----------|
    ///        |        |
    ///     -----1---2-----1---2--3--|
    ///
    ///     0)--------a---------b----------|
    ///               |         |
    ///     +----------------------------+
    ///     | flatMapLatest() - readable |
    ///     +----------------------------+
    ///     s0)-------s1--------s2---------|
    ///               |         |
    ///     0)--1--2--0--1--2---0--1--2----|
    ///
    /// - Note: If `self` signals a value, any a previous signal returned from `transform` will be disposed.
    /// - Note: If `self` and `other` are both readable their current values will be used as initial values.
    /// - Note: If either `self` of the signal returned from `transform` are terminated, the returned signal will terminated as well.
    func flatMapLatest<K, T>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> CoreSignal<K, T>) -> CoreSignal<Kind.DropWrite, T> where K.DropWrite == Kind.DropWrite {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            let latestBag = DisposeBag()
            let bag = DisposeBag(latestBag)
            bag += signal.onEventType(on: scheduler) { eventType in
                switch eventType {
                case .initial(nil):
                    callback(.initial(nil))
                case .initial(let val?):
                    latestBag += scheduler.sync { transform(val) }.onEventType(callback)
                case let .event(.value(val)):
                    let isFirstEvent = latestBag.isEmpty
                    latestBag.dispose()
                    latestBag += transform(val).onEventType { eventType in
                        switch eventType {
                        case .initial(let val?):
                            if isFirstEvent {
                                callback(eventType) // Just forward first initial
                            } else {
                                callback(.event(.value(val))) // Pass upcoming initials as values
                            }
                        case .initial(nil):
                            break
                        case .event:
                            callback(eventType)
                        }
                    }
                case .event(.end(let error)):
                    callback(.event(.end(error)))
                }
            }
            
            return bag
        })
    }

    /// Returns a new signal transforming values using `transform`
    ///
    ///     1)---2----3----4----|
    ///          |    |    |
    ///     +--------------------+
    ///     | map { v in v*2 }   |
    ///     +--------------------+
    ///          |    |    |
    ///     2)---4----6----8----|
    func map<T>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> T) -> CoreSignal<Kind.DropWrite, T> {
        let signal = providedSignal
        return CoreSignal(onEventType: { c in
            signal.onEventType(on: scheduler) { eventType in
                switch eventType {
                case .initial(nil): c(.initial(nil))
                case .initial(let val?): c(.initial(scheduler.sync { transform(val) }))
                case .event(.value(let val)): c(.event(.value(transform(val))))
                case .event(.end(let error)): c(.event(.end(error)))
                }
            }
        })
    }
    
    /// Returns a new signal transforming values using `transform`
    ///
    ///     1)---2----3----throw--->
    ///          |    |    |
    ///     +--------------------+
    ///     | map { v in v*2 }   |
    ///     +--------------------+
    ///          |    |    |
    ///     2)---4----6----|
    ///
    /// - Note: If `transform` throws an error, the signal will be terminated
    func map<T>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) throws -> T) -> FiniteSignal<T> {
        let signal = providedSignal
        return FiniteSignal(onEventType: { c in
            signal.onEventType(on: scheduler) { eventType in
                switch eventType {
                case .initial: c(.initial(nil))
                case .event(.value(let val)):
                    do {
                        c(.event(.value(try scheduler.sync { try transform(val) })))
                    } catch {
                        c(.event(.end(error)))
                    }
                case .event(.end(let error)):
                    c(.event(.end(error)))
                }
            }
        })
    }
    
    /// Returns a new signal transforming values using `keyPath`, equivalent to `map { $0[keyPath: keyPath] }`
    subscript<T>(keyPath: KeyPath<Value, T>) -> CoreSignal<Kind.DropWrite, T> {
        return map { $0[keyPath: keyPath] }
    }
    
    /// Returns a new signal where values evaluated false by `predicate` will be discarded.
    ///
    ///     0)---1----2----3---|
    ///          |    |    |
    ///     +---------------------------+
    ///     | filter { v in v.isOdd() } |
    ///     +---------------------------+
    ///          |         |
    ///     -----1---------3---|
    func filter(on scheduler: Scheduler = .current, predicate: @escaping (Value) -> Bool) -> CoreSignal<Kind.DropReadWrite, Value> {
        return compactMap(on: scheduler) { v in
            predicate(v) ? v : nil
        }
    }
    
    /// Returns a new signal where values are delayed by `delay` or discared if a new value is receieved before the delay has finished.
    ///
    ///     0)---1-----2-3-----4-5-6------|
    ///          |     | |     | | |
    ///     +--------------------------+
    ///     | debounce(2)              |
    ///     +--------------------------+
    ///            |      |         |
    ///     0)-----1------3---------6-----|
    ///
    /// - Parameter delay: The time to delay events. A delay of zero will still delay events. However, passing a nil value will not delay events and treat `debounce` as a no-op.
    func debounce(_ delay: TimeInterval?) -> CoreSignal<Kind, Value> {
        let signal = providedSignal

        guard let delay = delay else { return signal }
        precondition(delay >= 0)

        return CoreSignal(setValue: signal.setter, onEventType: { callback in
            let s = StateAndCallback(state: Disposable?.none, callback: callback)
            
            s += signal.onEventType { eventType in
                s.protectedVal?.dispose()
                guard case .event(.value) = eventType else {
                    s.call(eventType)
                    return
                }
                
                s.protectedVal = Signal(after: delay).onValue {
                    s.call(eventType)
                }
            }
            return s
        })
    }
    
    /// Returns a new signal where the last value of any subsequent values signaled within `interval` from the first value will be delayed and signaled at the `interval`s end.
    ///
    ///     0)---1--2---3-4----------6-7-----|
    ///          |  |   | |          | |
    ///     +-------------------------------+
    ///     | throttle(5)                   |
    ///     +-------------------------------+
    ///          |    |    |         |    |
    ///     0)---1----2----4---------6----7--|
    ///
    /// - Note: If more than `interval` is passed between two values, the latter value will become the first value in a new sequence.
    ///
    /// - Parameter interval: The time interval to wait between new values. An interval of zero will still delay values. However, passing a nil value will treat `throttle` as a no-op.
    func throttle(_ interval: TimeInterval?) -> CoreSignal<Kind, Value> {
        guard let interval = interval else { return providedSignal }
        precondition(interval >= 0)

        let signal = providedSignal
        return CoreSignal(setValue: signal.setter, onEventType: { callback in
            let s = StateAndCallback(state: (last: Value?.none, timer: Disposable?.none, setupTimer: (() -> Void)?.none), callback: callback)

            s += signal.onEventType { eventType in
                switch eventType {
                case .initial, .event(.end):
                    s.call(eventType)
                case .event(.value(let value)):
                    s.lock()
                    if s.val.timer == nil {
                        s.unlock()
                        s.callback(.event(.value(value)))
                        
                        let setupTimer: () -> Void = recursive { setupTimer in
                            s.protectedVal.timer = disposableAsync(after: interval) {
                                s.lock()
                                s.val.timer?.dispose()
                                s.val.timer = nil
                                guard let last = s.val.last else {
                                    s.val.setupTimer = nil
                                    return s.unlock()
                                }
                                
                                s.val.last = nil
                                s.unlock()
                                
                                s.callback(.event(.value(last)))
                                setupTimer()
                            }
                        }
                        setupTimer()
                        s.protectedVal.setupTimer = setupTimer // Hold on to reference
                    } else {
                        s.val.last = value
                        s.unlock()
                    }
                }
            }

            return s
        })
    }

    /// Performs an action on an event. This introduces side effects in a chain of composed
    /// signals without triggering a subscription.
    func atValue(on scheduler: Scheduler = .current, _ callback: @escaping (Value) -> ()) -> CoreSignal<Kind, Value> {
        let signal = providedSignal
        return CoreSignal(setValue: signal.setter, onEventType: { c in
            return signal.onEventType(on: scheduler) { eventType in
                if case .event(.value(let value)) = eventType {
                    callback(value)
                }
                c(eventType)
            }
        })
    }

    /// Returns a new signal with the two latest values.
    ///
    ///     ---1---2-------3-------4----|
    ///        |   |       |       |    |
    ///     +-----------------------------+
    ///     | latestTwo() - plain         |
    ///     +-----------------------------+
    ///            |       |       |    |
    ///     -----(1,2)---(2,3)---(3,4)--|
    ///
    ///     1)-----2-------3-------4----|
    ///            |       |       |    |
    ///     +-----------------------------+
    ///     | latestTwo() - readable      |
    ///     +-----------------------------+
    ///            |       |       |    |
    ///     -----(1,2)---(2,3)---(3,4)--|
    ///
    /// - Note: If `self` is readable its current value will be used as an initial value.
    func latestTwo() -> CoreSignal<Kind.DropReadWrite, (Value, Value)> {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            let s = StateAndCallback(state: Value?.none, callback: callback) // previous
            
            return signal.onEventType { eventType in
                switch eventType {
                case .initial(nil):
                    s.call(.initial(nil))
                case .initial(let val?):
                    s.lock()
                    s.val = val
                    s.unlock()
                    s.call(.initial(nil))
                case .event(.value(let val)):
                    s.lock()
                    if let prev = s.val {
                        s.val = val
                        s.unlock()
                        s.call(.event(.value((prev, val))))
                    } else {
                        s.val = val
                        s.unlock()
                    }
                case .event(.end(let error)):
                    return s.call(.event(.end(error)))
                }
            }
        })
    }
    
    /// Returns a new signal that for each value emits an array of all values received so far.
    ///
    ///     ?)--1---2-------3--------4----------|
    ///         |   |       |        |
    ///     +------------------------+
    ///     | buffer()               |
    ///     +------------------------+
    ///         |   |       |        |
    ///     []--[1]--[1,2]--[1,2,3]--[1,2,3,4]--|
    func buffer() -> CoreSignal<Kind.PotentiallyRead, [Value]> {
        return reduce([]) { a, v in a + [v] }
    }
    
    /// Returns a new signal forwarding the result of `combine(initial, value)` where `initial` is updated to the latest result.
    ///
    ///     ?)--1---2-------3-------4----|
    ///         |   |       |       |
    ///     +------------------------+
    ///     | reduce(0, combine: +)  |
    ///     +------------------------+
    ///         |   |       |       |
    ///     0)--1---3-------6-------10---|
    func reduce<T>(on scheduler: Scheduler = .current, _ initial: T, combine: @escaping (T, Value) -> T) -> CoreSignal<Kind.PotentiallyRead, T> {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            let s = StateAndCallback(state: initial, callback: callback)
            s += signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    s.call(.initial(initial))
                case let .event(.value(val)):
                    s.lock()
                    let initial = combine(s.val, val)
                    s.val = initial
                    s.unlock()
                    s.call(.event(.value(initial)))
                case let .event(.end(e)):
                    s.call(.event(.end(e)))
                }
            }
            return s
        })
    }
    
    /// Returns a new signal returning pairs of count (starting from 0) and value
    ///     ?)---a----b----c----|
    ///          |    |    |
    ///     +-----------------+
    ///     | enumerate()     |
    ///     +-----------------+
    ///          |    |    |
    ///     -----0a---1b---2c---|
    func enumerate() -> CoreSignal<Kind.DropReadWrite, (Int, Value)> {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            let s = StateAndCallback(state: -1, callback: callback)
            s += signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    s.call(.initial(nil))
                case let .event(.value(val)):
                    let count: Int = s.protect { s.val += 1; return s.val }
                    s.call(.event(.value((count, val))))
                case let .event(.end(e)):
                    s.call(.event(.end(e)))
                }
            }
            return s
        })
    }
    
    /// Returns a new signal forwarding values while `predicate` is true, whereafter the signal is terminated.
    ///
    ///     0)---1----2----3----4--->
    ///          |    |    |    |
    ///     +---------------------+
    ///     | take { v in v < 3 } |
    ///     +---------------------+
    ///          |    |
    ///     0)---1----2|
    func take(while predicate: @escaping (Value) -> Bool) -> FiniteSignal<Value> {
        let signal = providedSignal
        return FiniteSignal(setValue: signal.setter, onEventType: { callback in
            let s = StateAndCallback(state: (), callback: callback)

            s += signal.onEventType { eventType in
                if case .event(.value(let val)) = eventType {
                    guard predicate(val) else {
                        s.call(.event(.end))
                        return
                    }
                }
                s.call(eventType)
            }

            return s
        })
    }
    
    /// Returns a new signal returning the first 'count' values, whereafter the signal is terminated.
    ///
    ///     0)---1----2----3----4--->
    ///          |    |    |    |
    ///     +-------------------+
    ///     | take(first: 2)    |
    ///     +-------------------+
    ///          |    |
    ///     0)---1----2|
    func take(first count: Int) -> FiniteSignal<Value> {
        precondition(count >= 0)
        let signal = providedSignal
        return FiniteSignal(setValue: signal.setter, onEventType: { callback in
            let s = StateAndCallback(state: 0, callback: callback)
            
            s += signal.onEventType { type in
                s.lock()

                if case .event(.value) = type {
                    s.val += 1
                }
                
                guard s.val <= count else { return s.unlock() }

                let isDone = s.val >= count
                
                s.unlock()
                
                s.call(type)
                
                guard isDone else { return }

                s.call(.event(.end))
            }

            return s
        })
    }
    
    /// Returns a new signal discarding values until `predicate` is false, whereafter all values are forwarded.
    ///
    ///     0)---1----2----3----4---|
    ///          |    |    |    |
    ///     +---------------------+
    ///     | skip { v in v < 3 } |
    ///     +---------------------+
    ///                    |    |
    ///     0)-------------3----4---|
    func skip(on scheduler: Scheduler = .current, until predicate: @escaping (Value) -> Bool) -> CoreSignal<Kind.DropReadWrite, Value> {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            let s = StateAndCallback(state: false, callback: callback)
            
            s += signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    s.call(.initial(nil))
                case let .event(.value(val)):
                    s.lock()
                    guard s.val || predicate(val) else {
                        return s.unlock()
                    }
                    s.val = true
                    s.unlock()
                    s.call(.event(.value(val)))
                case let .event(.end(e)):
                    s.call(.event(.end(e)))
                }
            }
            return s
        })
    }
    
    /// Returns a new signal discarding the first 'count' values.
    ///
    ///     ?)---1---2---3---4---|
    ///          |   |   |   |
    ///     +-------------------+
    ///     | skip(first: 2)    |
    ///     +-------------------+
    ///                  |   |
    ///     -------------3---4---|
    func skip(first count: Int) -> CoreSignal<Kind.DropReadWrite, Value> {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            let s = StateAndCallback(state: 0, callback: callback)
            
            s += signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    s.call(.initial(nil))
                case let .event(.value(val)):
                    s.lock()
                    s.val += 1
                    guard s.val > count else {
                        return s.unlock()
                    }
                    s.unlock()
                    s.call(.event(.value(val)))
                case let .event(.end(e)):
                    s.call(.event(.end(e)))
                }
            }
            return s
        })
    }
    
    /// Returns a new signal discarding values if comparing the same with the preceeding value using `isSame`.
    ///
    ///     ---1---2---2---2---3---4---|
    ///        |   |   |   |   |   |
    ///      +-----------------------+
    ///      | distinct() - plain    |
    ///      +-----------------------+
    ///        |   |           |   |
    ///     ---1---2-----------3---4---|
    ///
    ///     1)-1---2---2---2---3---4---|
    ///        |   |   |   |   |   |
    ///      +-----------------------+
    ///      | distinct() - readable |
    ///      +-----------------------+
    ///            |           |   |
    ///     -------2-----------3---4---|
    ///
    /// - Note: If `self` is readable, its current value is considered as well.
    func distinct(on scheduler: Scheduler = .current, _ isSame: @escaping (Value, Value) -> Bool) -> CoreSignal<Kind, Value> {
        let signal = providedSignal
        return CoreSignal(setValue: { newValue in
            let val = signal.getter()!
            let isSame = scheduler.sync { isSame(newValue, val) }
            guard !isSame else { return }
            signal.setter!(newValue)
        }, onEventType: { callback in
            let s = StateAndCallback(state: Value?.none, callback: callback)

            s += signal.onEventType(on: scheduler) { eventType in
                if case .initial = eventType {
                    s.call(eventType)
                }
                
                if let val = eventType.value {
                    s.lock()
                    if !Kind.isReadable, s.val == nil {
                        s.val = val
                        s.unlock()
                        s.call(.event(.value(val)))
                    } else if let prev = s.val {
                        s.val = val
                        s.unlock()
                        guard !isSame(prev, val) else { return }
                        s.call(.event(.value(val)))
                    } else {
                        s.val = val
                        s.unlock()
                    }
                } else if case .event(.end) = eventType {
                    s.call(eventType)
                }
            }
            return s
        })
    }

    /// Returns a new signal holding values while `readSignal` is false
    /// - Note: At most one value is hold at a time and released when `readSignal` becomes true.
    func wait(until readSignal: ReadSignal<Bool>) -> Signal<Value> {
        let signal = providedSignal
        return Signal { callback in
            let s = StateAndCallback(state: Value?.none, callback: callback)
            
            s += signal.filter(on: .none) { _ in !readSignal.value }.onValue {
                s.protectedVal = $0
            }
            
            s += signal.filter(on: .none) { _ in readSignal.value }.atValue { _ in
                s.protectedVal = nil
            }.onValue(s.callback)
            
            s += readSignal.distinct().filter { $0 }.compactMap(on: .none) { _ in
                s.protectedVal
            }.atValue(on: .none) { _ in s.protectedVal = nil }.onValue(on: .none, s.callback)
            
            return s
        }
    }
}

public extension SignalProvider where Kind == Finite {
    /// Returns a new signal where `callback` will be called for signaled events.
    func atEvent(on scheduler: Scheduler = .current, _ callback: @escaping (Event<Value>) -> ()) -> FiniteSignal<Value> {
        let signal = providedSignal
        return FiniteSignal(setValue: signal.setter, onEventType: { c in
            return signal.onEventType(on: scheduler) { eventType in
                if case .event(let event) = eventType {
                    callback(event)
                }
                c(eventType)
            }
        })
    }
    
    /// Returns a new signal where `callback` will be called when `self` terminates.
    func atEnd(on scheduler: Scheduler = .current, _ callback: @escaping () -> ()) -> FiniteSignal<Value> {
        return atEvent(on: scheduler) { $0.isEnd ? callback() : () }
    }
    
    /// Returns a new signal where `callback` will be called when `self` terminates with an error.
    func atError(on scheduler: Scheduler = .current, _ callback: @escaping (Error) -> ()) -> FiniteSignal<Value> {
        return atEvent(on: scheduler) { $0.error.map(callback) }
    }
}

public extension SignalProvider where Kind.DropWrite == Read {
    /// Returns a new signal where the current value of `self` will be immediately signaled and before any other values from `self`.
    ///
    ///     1)---2----3----4--|
    ///          |    |    |
    ///     +----------------+
    ///     | atOnce()       |
    ///     +----------------+
    ///          |    |    |
    ///     1----2----3----4--|
    func atOnce() -> CoreSignal<Kind, Value> {
        let signal = providedSignal
        return CoreSignal(setValue: signal.setter, onEventType: { c in
            signal.onEventType { eventType in
                c(eventType)
                if case .initial(let val?) = eventType {
                    c(.event(.value(val)))
                }
            }
        })
    }
}

public extension SignalProvider where Kind == Plain, Value == () {
    /// Returns a new signal where the current the value `()` will be immediately signaled and before any other values from `self`, equivalent to `start(with: ())`
    func atOnce() -> Signal<Value> {
        return start(with: ())
    }
}


public extension SignalProvider where Kind == Finite, Value == () {
    /// Returns a new signal where the current the value `()` will be immediately signaled and before any other values from `self`, equivalent to `start(with: ())`
    func atOnce() -> FiniteSignal<Value> {
        return start(with: ())
    }
}

public extension SignalProvider where Value == Bool {
    /// Returns a new signal negating values
    func negate() -> CoreSignal<Kind.DropWrite, Bool> {
        return map(on: .none, !)
    }
}

public extension SignalProvider where Value: Equatable {
    /// Returns a new signal discarding values if comparing the same with the preceeding value.
    ///
    ///     ---1---2---2---2---3---4---|
    ///        |   |   |   |   |   |
    ///      +-----------------------+
    ///      | distinct() - plain    |
    ///      +-----------------------+
    ///        |   |           |   |
    ///     ---1---2-----------3---4---|
    ///
    ///     1)-1---2---2---2---3---4---|
    ///        |   |   |   |   |   |
    ///      +-----------------------+
    ///      | distinct() - readable |
    ///      +-----------------------+
    ///            |           |   |
    ///     -------2-----------3---4---|
    ///
    /// - Note: If `self` is readable, its current value is considered as well.
    func distinct(on scheduler: Scheduler = .current) -> CoreSignal<Kind, Value> {
        return distinct(on: scheduler) { $0 == $1 }
    }
}

public extension SignalProvider where Kind == Finite {
    /// Returns a new finite signal collecting all values up to `self`'s termination.
    ///
    ///     ---1---2---3---|
    ///        |   |   |   |
    ///      +---------------+
    ///      | collect()     |
    ///      +---------------+
    ///                    |
    ///     ---------------[1, 2, 3]|
    func collect() -> FiniteSignal<[Value]> {
        let signal = providedSignal
        return FiniteSignal(onEventType: { callback in
            let s = StateAndCallback(state: [Value](), callback: callback)
            
            return signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    s.call(.initial(nil))
                case let .event(.value(val)):
                    s.protectedVal.append(val)
                case let .event(.end(e)):
                    s.call(.event(.value(s.protectedVal)))
                    s.call(.event(.end(e)))
                }
            }
        })
    }
}

public extension SignalProvider where Kind == ReadWrite {
    /// Returns a new signal transforming values using `keyPath`
    subscript<T>(keyPath: WritableKeyPath<Value, T>) -> ReadWriteSignal<T> {
        let signal = providedSignal
        return ReadWriteSignal<T>(setValue: {
            // signal.value[keyPath: keyPath] = $0 // For some reason this does not work yet when keypaths using subscripts
            var val = signal.value
            val[keyPath: keyPath] = $0
            signal.value = val
        }, onEventType: { c in
            signal.map { $0[keyPath: keyPath] }.onEventType(c)
        })
    }
    
    /// Returns a new signal transforming values using `keyPath` where `defaultValue` is used if a value is nil.
    subscript<T>(keyPath: WritableKeyPath<Value, T?>, default defaultValue: @escaping @autoclosure () -> T) -> ReadWriteSignal<T> {
        let signal = providedSignal
        return ReadWriteSignal<T>(setValue: {
            // signal.value[keyPath: keyPath] = $0 // For some reason this does not work yet when keypaths using subscripts
            var val = signal.value
            val[keyPath: keyPath] = $0
            signal.value = val
        }, onEventType: { c in
            signal.map { $0[keyPath: keyPath] ?? defaultValue() }.onEventType(c)
        })
    }
}

