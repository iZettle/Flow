//
//  ReadSignal.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-01-29.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation

/// An abstraction for observing events over time where `self` as a notion of a readonly current value.
///
/// A `ReadSignal<T>` is like a `Signal<T>` with the addition of a readonly current value.
/// This value could be accessed using the `value` property, but more common is to use the `atOnce()` transform:
///
///     let readSignal = ...
///     // Start listening for values
///     let disposable = signal.atOnce().onValue { value in
///       // will be called at once with the current value and then every time signal is signaling a new value
///     }
///     ...
///     disposable.dispose() // Stop listening for values
///
/// - Note: Several transforms on readable signals will return a plain or finite signal, as these transforms cannot guarantee to provide a current value.
/// - Note: Most transformations combining several signals require all the signals to be either plain, finite or readable. This means that you sometimes have to add or remove readability and finiteness when combining several signals of different types.
/// - Note: You can promote a `ReadSignal<T>` to a `ReadWriteSignal<T>` using `writable()`.
/// - Note: You can demote a `ReadSignal<T>` to a `Signal<T>` using `plain()`.
/// - Note: `Signal<Value>` is a type alias for `CoreSignal<Read, Value>` to allow sharing common functionality with the other signal types.
public typealias ReadSignal<Value> = CoreSignal<Read, Value>

public extension CoreSignal where Kind == Read {
    /// Creates a new instance that will call `onValue` with a callback to signal values until the returned `Disposable` is being disposed.
    ///
    /// - Paramenter getValue: Called to get the current value.
    convenience init(getValue: @escaping () -> Value, options: SignalOptions = .default, onValue: @escaping (@escaping (Value) -> Void) -> Disposable) {
        self.init(getValue: getValue, options: options, onInternalEvent: { c in
            onValue { c(.value($0)) }
        })
    }

    /// Creates a new instance that will call `onValue` with a callback to signal values until the returned `Disposable` is being disposed.
    /// - Parameter value: An auto closure that will be evaluated every time a current value is asked for.
    convenience init(capturing value: @autoclosure @escaping () -> Value, options: SignalOptions = .default, onValue: @escaping (@escaping (Value) -> Void) -> Disposable) {
        self.init(getValue: value, options: options, onValue: onValue)
    }
    
    /// Creates a new instance that will use the provided `callbacker` to register listeners.
    ///
    ///     let callbacker = ...
    ///     var value == ....
    ///     let signal = ReadSignal(getValue: { value }, callbacker: callbacker)
    ///     ...
    //      value = ...
    ///     callbacker.callAll(with: value) // Will signal `value` to all signal's listeners.
    ///
    /// - Paramenter getValue: Called to get the current value.
    convenience init(getValue: @escaping () -> Value, callbacker: Callbacker<Value>) {
        self.init(getValue: getValue, options: [], onValue: callbacker.addCallback)
    }

    /// Creates a new instance that will use the provided `callbacker` to register listeners.
    ///
    ///     let callbacker = ...
    ///     var value == ....
    ///     let signal = ReadSignal(capturing: value, callbacker: callbacker)
    ///     ...
    //      value = ...
    ///     callbacker.callAll(with: value) // Will signal `value` to all signal's listeners.
    ///
    /// - Parameter value: An auto closure that will be evaluated every time a current value is asked for.
    convenience init(capturing value: @autoclosure @escaping () -> Value, callbacker: Callbacker<Value>) {
        self.init(getValue: value, callbacker: callbacker)
    }
    
    /// Creates a new instance that will never signal any values and will have a constant current `value`.
    convenience init(_ value: Value) {
        self.init(onEventType: { callback in
            callback(.initial(value))
            return NilDisposer()
        })
    }
}

public extension CoreSignal where Kind.DropWrite == Read {
    /// Creates a new instance dropping any write access from `signal`.
    convenience init<S: SignalProvider>(_ signal: S) where S.Value == Value, S.Kind.DropWrite == Read {
        self.init(onEventType: signal.providedSignal.onEventType)
    }
}

public extension SignalProvider where Kind.DropWrite == Read {
    // The current value of `self`.
    var value: Value {
        return providedSignal.getter()!
    }
    
    /// Returns a new signal with no access to a current `value`.
    func plain() -> Signal<Value> {
        return Signal(self)
    }
}

public extension SignalProvider where Kind == Read {
    /// Returns a new signal with write access to the current `value`.
    /// - Parameter signalOnSet: Should a change through `setValue` be signaled (default false).
    /// - Parameter setValue: Closure called when `value` is updated,
    func writable(signalOnSet: Bool = false, setValue: @escaping (Value) -> ()) -> ReadWriteSignal<Value> {
        let signal = providedSignal
        guard signalOnSet else {
            return ReadWriteSignal(setValue: setValue, onEventType: signal.onEventType)
        }
        let callbacker = Callbacker<EventType<Value>>()
        return ReadWriteSignal<Value>(setValue: { setValue($0); callbacker.callAll(with: .event(.value($0))) }, onEventType: { c in
            let bag = DisposeBag()
            bag += callbacker.addCallback(c)
            bag += signal.onEventType(c)
            return bag
        })
    }
}

internal extension CoreSignal {
    func getter() -> Value? {
        var value: Value? = nil
        if Kind.isReadable {
            // To get the current value we start listening on events and captures the value in `.initial`.
            onEventType { eventType in
                if case .initial(let val?) = eventType {
                    value = val
                }
            }.dispose() // Dispose at once to immediatly free up resources.
            assert(value != nil, "A signal that has a current value must return a non nil value")
        }
        return value
    }
}
