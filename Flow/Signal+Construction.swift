//
//  Signal+Construction.swift
//  Flow
//
//  Created by Måns Bernhardt on 2017-06-21.
//  Copyright © 2017 iZettle. All rights reserved.
//

import Foundation


/// Options used to customize the behaviours of constructed signals.
public struct SignalOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public extension SignalOptions {
    /// Signals constructed with `shared` will only register at most one simultaneous callback to the provided `onEvent` or `onValue`.
    /// Additional simultaneous listners will hence not register more callbacks, but will instead share the events fired by the callback that was first registered.
    /// When the last simultaneous listner is removed, the single callback will be de-registered (the `Disposable` returned from `onEvent` or `onValue` will be disposed).
    /// If a current value getter is provided such as `getValue` it will only be queried once for the first of several simultaneous listeners.
    /// Subsequent listeners will instead use the last signaled value for its current value.
    ///
    /// Shared signals are useful when the work performed when registering a callback is relatively expensive.
    /// If the work performed when registering a callback is trivial, it might be more efficient to not setup the signal to be shared.
    static let shared = SignalOptions(rawValue: 1<<0)
    
    /// Defaults to `[ .shared ]`
    static let `default`: SignalOptions = [ .shared ]
}

extension CoreSignal {
    /// An internal initializer for mapping `Event` based APIs to the underlying `EventType` based APIs.
    /// `EventType` and its APIs are an implemenation detail not currently being exposed in public APIs.
    /// Public APIs are instead working with `Event`s and "current values", typically provided through getters such as `getValue`.
    /// As signals can easly cause recursion, this initalizer also make firing of events "exclusive", that is, they will complete before another event is fired.
    /// Often it's not obvious when a recursion is caued, hence "exclusive" event handling should make it easier to reason about event callback code and in what order it is executed.
    /// Signaling of initial values (either none or a value retrieved from `getValue`) could also cause recursion, and need special handling to behave as expected.
    /// These two behaviours (exclusivity and initial recursion) can be illustrated by:
    ///
    ///     let callbacker = Callbacker<Event<Int>>()
    ///     var result = [Int]()
    ///     _ = Signal(callbacker: callbacker).start(with: 1).onValue { val in
    ///       result.append(val)
    ///       callbacker.callAll(with: .value(val + 1))
    ///       callbacker.callAll(with: .end)
    ///     }
    ///     assert(result == [1, 2])
    ///
    /// A basic implemenation of this initializer could have been e.g:
    ///
    ///     self.init(onEventType: { callback in
    ///       callback(.initial(getValue?()))
    ///       return onEvent { event in
    ///         callback(.event(event))
    ///        }
    ///      })
    ///
    /// But this would mean that we will not call `onEvent` (which will add a callback to the callbacker) until after the intital value was fired.
    /// But firing the initial value will be picked up by `start(with:)` to fire a real event casuing `onValue()` to
    /// be called with the value `1`. But when `onValue()`, on its turn, calls the callbacker, there are not yet any listeners as `onEvent` has not been called yet.
    /// Hence we will not receive any more events and `result` will be `[1]`.
    ///
    /// But even if we try to fix this by actually firing the initial value from inside `onEvent` if neccessarly, we will run into another problem.
    /// When we in `onValue()` signals `val + 1`, it will cause a recursion ending up in `onValue()` again, now with the value `2`.
    /// This will then continue forever until we blow up the stack, and code for firing the `.end` will never be reached.
    ///
    /// A solution is to make the firing "exclusive", that is, to let it finsish before potential recursive events are fired.
    /// In the example above this would mean that the recursive events from `onValue` will be queued up while `onValue` is executed,
    /// and once the firing of this initial value is done, the first queued up value `2` will fire, and while `onValue` is receiving the value `2`
    /// any new recursive events from `onValue` will be queued up as well. But then the the first `.end` is unqueued and fired, hence the signal is terminated.
    /// Thus we will get the expected result of `[1, 2]`
    ///
    /// Another, perhaps more realistic example:
    ///
    ///     let signal = ReadWriteSignal(1)
    ///     var result = 0
    ///     _ = signal.distinct().atOnce().onValue { val in
    ///       signal.value = 2
    ///       result = val
    ///     }
    ///     assert(result == 2)
    ///
    /// Without handling initial recursion or exclusivity, this would give a result equal to "1".
    /// If we just added initial recursion so `signal.value = 2` would cause a recursion and fire `2`,
    /// the result would be still be just "1", as `signal.value = 2` retuns (and result has been updated to `2`),
    /// `onValue()` with `1` will continue, and overriting the previous result of `2` with `1`.
    /// Whereas if we add exclusivity as well, `onValue()` with `1` will complete before `onValue()` with `2` is
    /// called and hence result will be the expected value of `2`
    ///
    /// This initializer also optionally implements sharing, see `SignalOptions.shared`, using the SharedState helper.
    convenience init(getValue: (() -> Value)? = nil, setValue: ((Value) -> ())? = nil, options: SignalOptions, onInternalEvent onEvent: @escaping (@escaping (Event) -> Void) -> Disposable) {
        let shared = options.contains(.shared) ? SharedState<Value>(getValue: getValue) : nil
        self.init(setValue: setValue, onEventType: { callback in
            let state = CallbackState(shared: shared, getValue: getValue, callback: callback)
            return state.runExclusiveWithState(onEvent: onEvent)
        })
    }
}

/// Helper to implement the state to handle signal's initial recursion and exclusivity.
private final class CallbackState<Value>: Disposable {
    var callback: ((EventType<Value>) -> Void)?
    var shouldCallInitial = true
    var hasTerminated = false
    var getValue: (() -> Value)?
    private var exclusiveCount = 0
    private var eventQueue = [Event<Value>]()
    
    private var shared: SharedState<Value>?
    let sharedKey: Key

    private var _mutex = pthread_mutex_t()
    private var mutex: PThreadMutex { return PThreadMutex(&_mutex) }
    
    init(shared: SharedState<Value>? = nil, getValue: (() -> Value)?, callback: @escaping (EventType<Value>) -> Void) {
        self.shared = shared
        self.sharedKey = shared == nil ? 0 : generateKey()
        self.getValue = getValue
        self.callback = callback
        mutex.initialize()
    }

    deinit {
        mutex.deinitialize()
        shared?.remove(key: sharedKey)
    }
    
    func lock() {
        mutex.lock()
    }
    
    func unlock() {
        mutex.unlock()
    }
    
    // For efficiency `Self` could also also behave as a `NoLockKeyDisposer``, saving us an allocation for each listener.
    func dispose() {
        lock()

        if let shared = shared {
            // Make sure to not clear up if we have other listeners
            guard shared.firstCallback?.key != sharedKey else {
                unlock()
                shared.remove(key: sharedKey)
                return
            }
            
            self.shared = nil
             // Release references, as we might be a disposable that outlives the signal
            getValue = nil
            eventQueue = []
            unlock()
            shared.remove(key: sharedKey)
        } else {
            unlock()
        }
    }

    func handleEventExclusiveWithState(_ event: Event<Value>) {
        lock()
        guard let callback = callback else { // Not already disposed?
            return unlock()
        }

        if shouldCallInitial {
            if case .end = event {
                hasTerminated = true
            }
            
            /// If we get immediate events before completing the `onEvent` call, make sure to inject the initial value before the first event.
            shouldCallInitial = false
            
            beginExclusivity()
            let getValue = self.getValue
            unlock()
            callback(.initial(getValue?()))
            lock()
        } else {
            beginExclusivity()
        }

        if isImmediate {
            unlock()
            call(with: event)
        } else { // We have a recursion, let's queue up the callback.
            eventQueue.append(event)
            unlock()
        }
        
        endExclusivity()
    }
    
    private func call(with event: Event<Value>) {
        if let shared = shared {
            if case .value(let value) = event, getValue != nil {
                shared.updateLast(to: value)
            }
            shared.callAll(with: .event(event))
        } else {
            lock()

            guard let callback = callback else { // No already diposed?
                return unlock()
            }
            
            unlock()

            callback(.event(event))
        }
        
        if case .end = event {
            dispose()
        }
    }
    
    func runExclusiveWithState(onEvent: @escaping (@escaping (Event<Value>) -> Void) -> Disposable) -> Disposable {
        guard let callback = callback else {
            return NilDisposer()
        }
        shared?.lock()

        let disposable: Disposable
        
        // If shared and we already have listener we shuold not skip listening.
        if shared?.firstCallback == nil {
            shared?.firstCallback = (sharedKey, callback)
            shared?.unlock()

            let d = onEvent(handleEventExclusiveWithState)
            
            if let shared = shared {
                shared.lock()
                shared.disposable = d
                shared.unlock()
                disposable = self
            } else {
                disposable = d
            }
            
            if hasTerminated { // If terminated before returning from `onEvent`, make sure to dispose().
                unlock()
                disposable.dispose()
            } else if shouldCallInitial { // If we never called initial from within `onEvent` call it now.
                shouldCallInitial = false
                beginExclusivity()
                unlock()
                callback(.initial(getValue?()))
                endExclusivity()
            }
        } else if let shared = shared {
            shared.remainingCallbacks[sharedKey] = callback
            disposable = self
            shared.unlock()

            beginExclusivity()
            unlock()
            callback(.initial(shared.initial))
            endExclusivity()
        } else {
            fatalError("We could impossibly end up here")
        }
        
        return disposable
    }
    
    var isImmediate: Bool {
        return exclusiveCount <= 1
    }
    
    private func releaseQueue() {
        guard exclusiveCount == 0, !eventQueue.isEmpty else { return unlock() }
        
        let events = eventQueue
        eventQueue = []
        
        exclusiveCount += 1
        unlock()
        for event in events {
            call(with: event)
        }
        lock()
        exclusiveCount -= 1
        
        // While releasing, more might have been queued up, so make sure to release those as well.
        releaseQueue()
    }
    
    func beginExclusivity() {
        exclusiveCount += 1
    }
    
    func endExclusivity() {
        lock()
        exclusiveCount -= 1
        releaseQueue()
    }
}

/// Helper to implement sharing of a single `onEvent` if more than one listner, see `SignalOption.shared`
final class SharedState<Value> {
    private let getValue: (() -> Value)?
    private var _mutex = pthread_mutex_t()
    private var mutex: PThreadMutex { return PThreadMutex(&_mutex) }

    typealias Callback = (EventType<Value>) -> Void
    var firstCallback: (key: Key, value: Callback)? = nil
    var remainingCallbacks = [Key: Callback]()
    var lastReceivedValue: Value? = nil
    var disposable: Disposable?

    init(getValue: (() -> Value)? = nil) {
        self.getValue = getValue
        mutex.initialize()
    }
    
    deinit {
        mutex.deinitialize()
    }
    
    func lock() {
        mutex.lock()
    }
    
    func unlock() {
        mutex.unlock()
    }

    func remove(key: Key) {
        lock()
        if firstCallback?.key == key {
            firstCallback = remainingCallbacks.first
            if let key = firstCallback?.key {
                remainingCallbacks[key] = nil
                unlock()
            } else {
                let d = disposable
                lastReceivedValue = nil
                disposable = nil
                unlock()
                d?.dispose()
            }
        } else {
            remainingCallbacks[key] = nil
            unlock()
        }
    }

    var initial: Value? {
        guard let getValue = getValue else { return nil }
        lock()
        
        if let last = lastReceivedValue {
            unlock()
            return last
        }
        
        unlock()
        let value = getValue() // Don't hold lock while calling out.
        lock()
        
        defer {
            unlock()
        }
        lastReceivedValue = value
        return lastReceivedValue!
    }

    func updateLast(to value: Value) {
        lock()
        lastReceivedValue = value
        unlock()
    }

    func callAll(with eventType: EventType<Value>) {
        lock()
        let first = self.firstCallback
        let callbacks = self.remainingCallbacks
        unlock()

        if let (key, c) = first {
            if case .event(.end) = eventType {
                remove(key: key)
            }
            c(eventType)
        }

        for (key, c) in callbacks {
            if case .event(.end) = eventType {
                remove(key: key)
            }
            c(eventType)
        }
    }
}

