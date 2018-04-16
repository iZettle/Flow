//
//  FiniteSignal.swift
//  Flow
//
//  Created by Måns Bernhardt on 2018-03-29.
//  Copyright © 2018 iZettle. All rights reserved.
//

import Foundation


/// An abstraction for observing values over time where the signal can terminate
///
/// A finite signal allows observing events over time by registering of a callback:
///
///     let signal = ...
///     // Start listening for events
///     let disposable = signal.onEvent { event in
///       // will be called every time signal is signaling a new event
///     }
///     ...
///     disposable.dispose() // Stop listening for events
///
/// An event is represented by the type `Event<T>` that can either be a `.value` or an `.end` (optionally with an error).
/// Once a finite signal is terminated with an `.end` event it won't signal any more events and any resources will be disposed.
///
/// - Note: You can convert a `FiniteSignal<T>` to a `Signal<T>` using `plain()`.
/// - Note: `FiniteSignal<Value>` is a type alias for `CoreSignal<Finite, Value>` to allow sharing common functionality with the other signal types.
/// - Note: Most transformations combining several signals require all the signals to be either plain, finite or readable. This means that you sometimes have to add or remove readability and finiteness when combining several signals of different types.
public typealias FiniteSignal<Value> = CoreSignal<Finite, Value>

public extension CoreSignal where Kind == Finite {
    /// Creates a new instance that will call `onEvent` with a callback to signal events until the returned `Disposable` is being disposed.
    convenience init(options: SignalOptions = .default, onEvent: @escaping (@escaping (Event) -> Void) -> Disposable) {
        self.init(options: options, onInternalEvent: onEvent)
    }
    
    /// Creates a new instance that will use the provided `callbacker` to register listeners.
    ///
    ///     let callbacker = ...
    ///     let signal = Signal(callbacker: callbacker)
    ///     ...
    ///     callbacker.callAll(with: event) // Will signal `event` to all signal's listeners.
    convenience init(callbacker: Callbacker<Event>) {
        self.init(options: [], onInternalEvent: { c in
            return callbacker.addCallback(c)
        })
    }
    
    /// Creates a new instance that will never signal any events.
    convenience init() {
        self.init(onEventType: { callback in
            callback(.initial(nil))
            return NilDisposer()
        })
    }
    
    /// Creates a new instance wrapping `signal`.
    convenience init<S: SignalProvider>(_ signal: S) where S.Value == Value {
        let signal = signal.providedSignal
        self.init(onEventType: { callback in
            signal.onEventType { eventType in
                if case .initial = eventType {
                    callback(.initial(nil))
                } else {
                    callback(eventType)
                }
            }
        })
    }
}

public extension SignalProvider where Kind == Finite {
    /// Returns a new plain signal that will forward any values signaled by `self` until it terminates.
    func plain() -> Signal<Value> {
        return Signal(self)
    }
}


