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
        return map(on: .none) { _ in }
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
        return CoreSignal(setValue: signal.setter, onEventType: { callback in
            return signal.onEventType { eventType in
                callback(eventType)
                if case .initial = eventType {
                    for value in values {
                        callback(.event(.value(value)))
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

        return CoreSignal(setValue: signal.setter, onEventType: { (callback: (@escaping (EventType) -> Void)) -> Disposable in
            let key = generateKey()
            shared.lock()

            if shared.firstCallback == nil {
                shared.firstCallback = (key, callback)
                shared.unlock()

                let disposable = signal.onEventType { eventType in
                    switch eventType {
                    case .initial(let val?),
                         .event(.value(let val)) where Kind.isReadable:
                        shared.updateLast(to: val)
                    default: break
                    }

                    shared.callAll(with: eventType)
                }
                shared.lock()
                shared.disposable = disposable
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
        return CoreSignal(onEventType: { callback in
            signal.onEventType(on: scheduler) { eventType in
                switch eventType {
                case .initial:
                    callback(.initial(nil))
                case .event(.value(let value)):
                    transform(value).map { callback(.event(.value($0))) }
                case let .event(.end(error)):
                    callback(.event(.end(error)))
                }
            }
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
        return CoreSignal(onEventType: { callback in
            signal.onEventType(on: scheduler) { eventType in
                switch eventType {
                case .initial(nil): callback(.initial(nil))
                case .initial(let val?): callback(.initial(scheduler.sync { transform(val) }))
                case .event(.value(let val)): callback(.event(.value(transform(val))))
                case .event(.end(let error)): callback(.event(.end(error)))
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
        return FiniteSignal(onEventType: { callback in
            signal.onEventType(on: scheduler) { eventType in
                switch eventType {
                case .initial: callback(.initial(nil))
                case .event(.value(let val)):
                    do {
                        callback(.event(.value(try scheduler.sync { try transform(val) })))
                    } catch {
                        callback(.event(.end(error)))
                    }
                case .event(.end(let error)):
                    callback(.event(.end(error)))
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
        return compactMap(on: scheduler) { value in
            predicate(value) ? value : nil
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
            let state = StateAndCallback(state: Disposable?.none, callback: callback)

            state += signal.onEventType { eventType in
                state.protectedVal?.dispose()
                guard case .event(.value) = eventType else {
                    state.call(eventType)
                    return
                }

                state.protectedVal = Signal(after: delay).onValue {
                    state.call(eventType)
                }
            }
            return state
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
            let state = StateAndCallback(state: (last: Value?.none, timer: Disposable?.none, setupTimer: (() -> Void)?.none), callback: callback)

            state += signal.onEventType { eventType in
                switch eventType {
                case .initial, .event(.end):
                    state.call(eventType)
                case .event(.value(let value)):
                    state.lock()
                    if state.val.timer == nil {
                        state.unlock()
                        state.callback(.event(.value(value)))

                        let setupTimer: () -> Void = recursive { setupTimer in
                            state.protectedVal.timer = disposableAsync(after: interval) {
                                state.lock()
                                state.val.timer?.dispose()
                                state.val.timer = nil
                                guard let last = state.val.last else {
                                    state.val.setupTimer = nil
                                    return state.unlock()
                                }

                                state.val.last = nil
                                state.unlock()

                                state.callback(.event(.value(last)))
                                setupTimer()
                            }
                        }
                        setupTimer()
                        state.protectedVal.setupTimer = setupTimer // Hold on to reference
                    } else {
                        state.val.last = value
                        state.unlock()
                    }
                }
            }

            return state
        })
    }

    /// Performs an action on an event. This introduces side effects in a chain of composed
    /// signals without triggering a subscription.
    func atValue(on scheduler: Scheduler = .current, _ callback: @escaping (Value) -> ()) -> CoreSignal<Kind, Value> {
        let signal = providedSignal
        return CoreSignal(setValue: signal.setter, onEventType: { typeCallback in
            return signal.onEventType(on: scheduler) { eventType in
                if case .event(.value(let value)) = eventType {
                    callback(value)
                }
                typeCallback(eventType)
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
            let state = StateAndCallback(state: Value?.none, callback: callback) // previous

            return signal.onEventType { eventType in
                switch eventType {
                case .initial(nil):
                    state.call(.initial(nil))
                case .initial(let val?):
                    state.lock()
                    state.val = val
                    state.unlock()
                    state.call(.initial(nil))
                case .event(.value(let val)):
                    state.lock()
                    if let prev = state.val {
                        state.val = val
                        state.unlock()
                        state.call(.event(.value((prev, val))))
                    } else {
                        state.val = val
                        state.unlock()
                    }
                case .event(.end(let error)):
                    return state.call(.event(.end(error)))
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
        return reduce([]) { accumulator, value in accumulator + [value] }
    }

    /// Returns a new signal forwarding the result of `combine(initial, value)` where `initial` is updated to the latest result.
    ///
    ///     ----1---2-------3-------4----------|
    ///         |   |       |       |
    ///     +----------------------------------+
    ///     | reduce(0, combine: +) - plain    |
    ///     +----------------------------------+
    ///         |   |       |       |
    ///     ----1---3-------6-------10---------|
    ///
    ///     1)--2---3-------4-------5----------|
    ///         |   |       |       |
    ///     +----------------------------------+
    ///     | reduce(0, combine: +) - readable |
    ///     +----------------------------------+
    ///         |   |       |       |
    ///     1)--3---6-------10------15---------|
    func reduce<T>(on scheduler: Scheduler = .current, _ initial: T, combine: @escaping (T, Value) -> T) -> CoreSignal<Kind.PotentiallyRead, T> {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            let state = StateAndCallback(state: initial, callback: callback)
            state += signal.onEventType { eventType in
                switch eventType {
                case .initial(nil):
                    state.call(.initial(initial))
                case .initial(let val?):
                    state.lock()
                    let initial = combine(state.val, val)
                    state.val = initial
                    state.unlock()
                    state.call(.initial(initial))
                case .event(.value(let val)):
                    state.lock()
                    let initial = combine(state.val, val)
                    state.val = initial
                    state.unlock()
                    state.call(.event(.value(initial)))
                case .event(.end(let error)):
                    state.call(.event(.end(error)))
                }
            }
            return state
        })
    }

    /// Returns a new signal returning boolean values where `true` means that at least one value so far has satisfied the given predicate.
    ///
    ///     -------1---3-------2-------1-----|
    ///            |   |       |       |
    ///     +--------------------------------+
    ///     | contains(where: { $0.isEven }) |
    ///     +--------------------------------+
    ///            |   |       |       |
    ///     -------f---f-------t-------t-----|
    ///
    ///     1)-----3---5-------2-------7-----|
    ///            |   |       |       |
    ///     +--------------------------------+
    ///     | contains(where: { $0.isEven }) |
    ///     +--------------------------------+
    ///            |   |       |       |
    ///     f)-----f---f-------t-------t-----|
    func contains(on scheduler: Scheduler = .current, where predicate: @escaping (Value) -> Bool) -> CoreSignal<Kind.PotentiallyRead, Bool> {
        return reduce(on: scheduler, false, combine: { $0 || predicate($1) })
    }

    /// Returns a new signal returning boolean values where `true` means that at all values so far have satisfied the given predicate.
    ///
    ///     -------2---4-------1-------6-------|
    ///            |   |       |       |
    ///     +----------------------------------+
    ///     | allSatisfy(where: { $0.isEven }) |
    ///     +----------------------------------+
    ///            |   |       |       |
    ///     -------t---t-------f-------f-------|
    ///
    ///     0)-----2---4-------1-------6-------|
    ///            |   |       |       |
    ///     +----------------------------------+
    ///     | allSatisfy(where: { $0.isEven }) |
    ///     +----------------------------------+
    ///            |   |       |       |
    ///     t)-----t---t-------f-------f-------|
    func allSatisfy(on scheduler: Scheduler = .current, where predicate: @escaping (Value) -> Bool) -> CoreSignal<Kind.PotentiallyRead, Bool> {
        return reduce(on: scheduler, true, combine: { $0 && predicate($1) })
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
            let state = StateAndCallback(state: -1, callback: callback)
            state += signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    state.call(.initial(nil))
                case .event(.value(let val)):
                    let count: Int = state.protect { state.val += 1; return state.val }
                    state.call(.event(.value((count, val))))
                case .event(.end(let error)):
                    state.call(.event(.end(error)))
                }
            }
            return state
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
            let state = StateAndCallback(state: (), callback: callback)

            state += signal.onEventType { eventType in
                if case .event(.value(let val)) = eventType {
                    guard predicate(val) else {
                        state.call(.event(.end))
                        return
                    }
                }
                state.call(eventType)
            }

            return state
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
            let state = StateAndCallback(state: 0, callback: callback)

            state += signal.onEventType { type in
                state.lock()

                if case .event(.value) = type {
                    state.val += 1
                }

                guard state.val <= count else { return state.unlock() }

                let isDone = state.val >= count

                state.unlock()

                state.call(type)

                guard isDone else { return }

                state.call(.event(.end))
            }

            return state
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
            let state = StateAndCallback(state: false, callback: callback)

            state += signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    state.call(.initial(nil))
                case .event(.value(let val)):
                    state.lock()
                    guard state.val || predicate(val) else {
                        return state.unlock()
                    }
                    state.val = true
                    state.unlock()
                    state.call(.event(.value(val)))
                case .event(.end(let error)):
                    state.call(.event(.end(error)))
                }
            }
            return state
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
            let state = StateAndCallback(state: 0, callback: callback)

            state += signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    state.call(.initial(nil))
                case .event(.value(let val)):
                    state.lock()
                    state.val += 1
                    guard state.val > count else {
                        return state.unlock()
                    }
                    state.unlock()
                    state.call(.event(.value(val)))
                case .event(.end(let error)):
                    state.call(.event(.end(error)))
                }
            }
            return state
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
            let state = StateAndCallback(state: Value?.none, callback: callback)

            state += signal.onEventType(on: scheduler) { eventType in
                if case .initial = eventType {
                    state.call(eventType)
                }

                if let val = eventType.value {
                    state.lock()
                    if !Kind.isReadable, state.val == nil {
                        state.val = val
                        state.unlock()
                        state.call(.event(.value(val)))
                    } else if let prev = state.val {
                        state.val = val
                        state.unlock()
                        guard !isSame(prev, val) else { return }
                        state.call(.event(.value(val)))
                    } else {
                        state.val = val
                        state.unlock()
                    }
                } else if case .event(.end) = eventType {
                    state.call(eventType)
                }
            }
            return state
        })
    }

    /// Returns a new signal holding values while `readSignal` is false
    /// - Note: At most one value is hold at a time and released when `readSignal` becomes true.
    func wait(until readSignal: ReadSignal<Bool>) -> Signal<Value> {
        let signal = providedSignal
        return Signal(onValue: { callback in
            let state = StateAndCallback(state: Value?.none, callback: callback)

            state += signal.filter(on: .none) { _ in !readSignal.value }.onValue {
                state.protectedVal = $0
            }

            state += signal.filter(on: .none) { _ in readSignal.value }.atValue { _ in
                state.protectedVal = nil
            }.onValue(state.callback)

            state += readSignal.distinct().filter { $0 }.compactMap(on: .none) { _ in
                state.protectedVal
            }.atValue(on: .none) { _ in state.protectedVal = nil }.onValue(on: .none, state.callback)

            return state
        })
    }
}

public extension SignalProvider where Kind == Plain {
    /// Returns a new signal forwarding the values from the signal returned from `transform`.
    ///
    ///     ---a--------b------------
    ///        |        |
    ///     +-------------------------+
    ///     | flatMapLatest()         |
    ///     +-------------------------+
    ///     ---s1-------s2-----------|
    ///        |        |
    ///     -----1---2-----1---2--3--|
    ///
    /// - Note: If `self` signals a value, any a previous signal returned from `transform` will be disposed.
    /// - Note: If the signal returned from `transform` is terminated, the returned signal will terminated as well.
    func flatMapLatest<K, T>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> CoreSignal<K, T>) -> CoreSignal<K.DropReadWrite, T> {
        return _flatMapLatest(on: scheduler, transform)
    }
}

public extension SignalProvider where Kind == Finite {
    /// Returns a new signal forwarding the values from the signal returned from `transform`.
    ///
    ///     ---a--------b------------|
    ///        |        |
    ///     +-------------------------+
    ///     | flatMapLatest           |
    ///     +-------------------------+
    ///     ---s1-------s2-----------|
    ///        |        |
    ///     -----1---2-----1---2--3--|
    ///
    ///
    /// - Note: If `self` signals a value, any a previous signal returned from `transform` will be disposed.
    /// - Note: If either `self` of the signal returned from `transform` are terminated, the returned signal will terminated as well.
    func flatMapLatest<K, T>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> CoreSignal<K, T>) -> FiniteSignal<T> {
        return _flatMapLatest(on: scheduler, transform)
    }
}

public extension SignalProvider where Kind.DropWrite == Read {
    /// Returns a new signal forwarding the values from the signal returned from `transform`.
    ///
    ///     0)--------a---------b-------
    ///               |         |
    ///     +----------------------------+
    ///     | flatMapLatest()            |
    ///     +----------------------------+
    ///     s0)-------s1--------s2------|
    ///               |         |
    ///     0)--1--2--0--1--2---0--1--2-|
    ///
    /// - Note: If `self` signals a value, any a previous signal returned from `transform` will be disposed.
    /// - Note: If the signal returned from `transform` is terminated, the returned signal will terminated as well.
    func flatMapLatest<K, T>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> CoreSignal<K, T>) -> CoreSignal<K, T> {
        return _flatMapLatest(on: scheduler, transform)
    }
}

private extension SignalProvider {
    func _flatMapLatest<KI, T, KO>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> CoreSignal<KI, T>) -> CoreSignal<KO, T> {
        let signal = providedSignal

        let mutex = Mutex()
        var setter: ((T) -> ())?
        func setValue(_ value: T) {
            mutex.lock()
            let setValue = setter ?? transform(signal.getter()!).setter!
            mutex.unlock()
            setValue(value)
        }

        return CoreSignal(setValue: setValue, onEventType: { callback in
            let latestBag = DisposeBag()
            let bag = DisposeBag(latestBag)
            bag += {
                mutex.lock()
                setter = nil
                mutex.unlock()
            }

            bag += signal.onEventType(on: scheduler) { eventType in
                switch eventType {
                case .initial(nil):
                    callback(.initial(nil))
                case .initial(let val?):
                    let signal = scheduler.sync { transform(val) }
                    mutex.lock()
                    setter = signal.setter
                    mutex.unlock()
                    latestBag += signal.onEventType(callback)
                case let .event(.value(val)):
                    let isFirstEvent = latestBag.isEmpty
                    latestBag.dispose()
                    let signal = transform(val)
                    mutex.lock()
                    setter = signal.setter
                    mutex.unlock()
                    latestBag += signal.onEventType { eventType in
                        switch eventType {
                        case .initial(let val?) where KO.isReadable:
                            if isFirstEvent {
                                callback(eventType) // Just forward first initial
                            } else {
                                callback(.event(.value(val))) // Pass upcoming initials as values
                            }
                        case .initial:
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
}

public extension SignalProvider where Kind == Finite {
    /// Returns a new signal where `callback` will be called for signaled events.
    func atEvent(on scheduler: Scheduler = .current, _ callback: @escaping (Event<Value>) -> ()) -> FiniteSignal<Value> {
        let signal = providedSignal
        return FiniteSignal(setValue: signal.setter, onEventType: { typeCallback in
            return signal.onEventType(on: scheduler) { eventType in
                if case .event(let event) = eventType {
                    callback(event)
                }
                typeCallback(eventType)
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
        return CoreSignal(setValue: signal.setter, onEventType: { callback in
            signal.onEventType { eventType in
                callback(eventType)
                if case .initial(let val?) = eventType {
                    callback(.event(.value(val)))
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

public extension SignalProvider where Kind == ReadWrite, Value == Bool {
    /// Will update `value` to `!value´.
    func toggle() {
        return value = !value
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
            let state = StateAndCallback(state: [Value](), callback: callback)

            return signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    state.call(.initial(nil))
                case .event(.value(let val)):
                    state.protectedVal.append(val)
                case .event(.end(let error)):
                    state.call(.event(.value(state.protectedVal)))
                    state.call(.event(.end(error)))
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
        }, onEventType: { callback in
            signal.map { $0[keyPath: keyPath] }.onEventType(callback)
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
        }, onEventType: { callback in
            signal.map { $0[keyPath: keyPath] ?? defaultValue() }.onEventType(callback)
        })
    }
}
