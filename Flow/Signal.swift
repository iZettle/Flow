//
//  Signal.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-01-29.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation


/// An abstraction for observing values over time
///
/// A signal allows observing values over time by registering of a callback:
///
///     let signal = ...
///     // Start listening for values
///     let disposable = signal.onValue { value in
///       // will be called every time signal is signaling a new value
///     }
///     ...
///     disposable.dispose() // Stop listening for events
///
/// Transformations
/// ---------------
///
/// It is often useful to perform transforms on signals, such as mapping the values. Every time such a transform is
/// performed a new signal representing this transform is returned. This means you could chain several transforms after
/// each other.
///
///     let newSignal = signal.filter { $0 > 0 }.map { $0 * 2 }
///
///
/// Scheduling
/// ----------
///
/// For most `Signal` APIs accepting a callback closure, there is a defaulted `scheduler` parameter you could pass as well used to schedule
/// the provided callback closure. By default this scheduler is set to the current scheduler used when calling the API.
///
///     signal.map { /* Will be called back on the current scheduler at the time `map` was called. */ }
///     signal.map(on: .main) { /* Will be called back on the main queue no matter from where `map` was called.  */ }
///
/// - Note: You can promote a `Signal<T>` to a `ReadSignal<T>` using `readable()`.
/// - Note: You can convert a `Signal<T>` to a `FiniteSignal<T> using `finite()`.
/// - Note: `Signal<Value>` is a type alias for `CoreSignal<Plain, Value>` to allow sharing common functionality with the other signal types.
/// - Note: It seldom makes sense to provide a concurrent scheduler for signal transforms as it might change the order of events.
public typealias Signal<Value> = CoreSignal<Plain, Value>

public extension CoreSignal where Kind == Plain {
    /// Creates a new instance that will call `onValue` with a callback to signal values until the returned `Disposable` is being disposed.
    ///
    ///     extension NotificationCenter {
    ///       func signal(forName name: Notification.Name?, object: Any? = nil) -> Signal<Notification> {
    ///         return Signal { callback in
    ///           let observer = self.addObserver(forName: name, object: object, queue: nil, using: callback)
    ///           return Disposer {
    ///             self.removeObserver(observer)
    ///           }
    ///         }
    ///       }
    ///     }
    convenience init(options: SignalOptions = .default, onValue: @escaping (@escaping (Value) -> Void) -> Disposable) {
        self.init(options: options, onInternalEvent: { c in
            onValue { c(.value($0)) }
        })
    }
    
    /// Creates a new instance that will use the provided `callbacker` to register listeners.
    ///
    ///     let callbacker = ...
    ///     let signal = Signal(callbacker: callbacker)
    ///     ...
    ///     callbacker.callAll(with: value) // Will signal `value` to all signal's listeners.
    convenience init(callbacker: Callbacker<Value>) {
        self.init(options: [], onInternalEvent: { c in
            return callbacker.addCallback { c(.value($0)) }
        })
    }
    
    /// Creates a new instance dropping any read or write access from `signal`.
    convenience init<S: SignalProvider>(_ signal: S) where S.Value == Value {
        let signal = signal.providedSignal
        self.init(onEventType: { callback in
            signal.onEventType { eventType in
                switch eventType {
                case .initial:
                    callback(.initial(nil))
                case .event(.value):
                    callback(eventType)
                case .event(.end):
                    break
                }
            }
        })
    }
    
    /// Creates a new instance that will immediately signal `value`.
    convenience init(just value: Value) {
        self.init(onEventType: { callback in
            callback(.initial(nil))
            callback(.event(.value(value)))
            return NilDisposer()
        })
    }
    
    /// Creates a new instance that will never signal any events.
    convenience init() {
        self.init(onEventType: { callback in
            callback(.initial(nil))
            return NilDisposer()
        })
    }
}

public extension SignalProvider where Kind == Plain {
    /// Returns a new readable signal evaluating `getValue()` for its current value.
    func readable(getValue: @escaping () -> Value) -> ReadSignal<Value> {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            signal.onEventType { eventType in
                if case .initial = eventType {
                    callback(.initial(getValue()))
                } else {
                    callback(eventType)
                }
            }
        })
    }
    
    /// Returns a new readable signal capturing `value` as it current value.
    /// - Parameter value: An auto closure that will be evaluated every time a current value is asked for.
    func readable(capturing value: @autoclosure @escaping () -> Value) -> ReadSignal<Value> {
        return readable(getValue: value)
    }
    
    /// Returns a new readable signal using `initial` as it current value, unless the signal has listeners, where the last signaled value will be used instead.
    func readable(initial: Value) -> ReadSignal<Value> {
        let signal = providedSignal
        let s = StateAndCallback(state: (last: initial, refCount: 0))
        
        return CoreSignal(onEventType: { callback in
            let bag = DisposeBag()
            s.protect { s.val.refCount += 1 }
            
            bag += signal.onEventType { eventType in
                if case .initial = eventType {
                    callback(.initial(s.protectedVal.last))
                } else {
                    if case .event(.value(let val)) = eventType {
                        s.protectedVal.last = val
                    }
                    callback(eventType)
                }
            }
            
            bag += {
                s.protect {
                    s.val.refCount -= 1
                    if s.val.refCount == 0 { // Reset last if we no longer have any active listeners
                        s.val.last = initial
                    }
                }
            }
            
            return bag
        })
    }
}

public extension SignalProvider where Kind == Plain, Value == () {
    /// Returns a new readable signal with the current value of ()
    func readable() -> ReadSignal<Value> {
        let signal = providedSignal
        return CoreSignal(onEventType: { callback in
            signal.onEventType { eventType in
                if case .initial = eventType {
                    callback(.initial(()))
                } else {
                    callback(eventType)
                }
            }
        })
    }
}

/// Returns `self` converted to a finite signal that will never terminate.
public extension SignalProvider where Kind.DropReadWrite == Plain {
    func finite() -> FiniteSignal<Value> {
        return FiniteSignal(self)
    }
}


