//
//  Signal+Listeners.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation


public extension SignalProvider {
    /// Start listening on values via the provided `callback`.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func onValue(on scheduler: Scheduler = .current, _ callback: @escaping (Value) -> Void) -> Disposable {
        return providedSignal.onEventType(on: scheduler) { eventType in
            guard case .event(.value(let val)) = eventType else { return }
            callback(val)
        }
    }
    
    /// Start listening on values via the provided `callback` and dispose the disposable previously returned from the `callback` when a new value is signaled.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func onValueDisposePrevious(on scheduler: Scheduler = .current, _ callback: @escaping (Value) -> Disposable?) -> Disposable {
        let bag = DisposeBag()
        let subBag = bag.innerBag()
        bag += onValue(on: scheduler) { value in
            subBag.dispose()
            subBag += callback(value)
        }
        return bag
    }
}

public extension SignalProvider where Kind == Finite {
    /// Start listening on events via the provided `callback`.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func onEvent(on scheduler: Scheduler = .current, _ callback: @escaping (Event<Value>) -> Void) -> Disposable {
        return providedSignal.onEventType(on: scheduler) { eventType in
            guard case .event(let event) = eventType else { return }
            callback(event)
        }
    }
    
    /// Wait for an end event and call `callback`.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func onEnd(on scheduler: Scheduler = .current, _ callback: @escaping () -> Void) -> Disposable {
        return onEvent(on: scheduler) { $0.isEnd ? callback() : () }
    }
    
    /// Wait for an error event and call `callback` with that error.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func onError(on scheduler: Scheduler = .current, _ callback: @escaping (Error) -> Void) -> Disposable {
        return onEvent(on: scheduler) { $0.error.map(callback) }
    }
}

public extension SignalProvider {
    /// Wait for the first value and call `callback` with that value.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    /// - Note: equivalent to `take(first: 1).onValue(callback)`
    func onFirstValue(on scheduler: Scheduler = .current, _ callback: @escaping (Value) -> Void) -> Disposable {
        return take(first: 1).onValue(on: scheduler, callback)
    }
}

public extension SignalProvider {
    /// Start listening on values via the provided `setValue`.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    /// - Note: equivalent to `onValue(setValue)`
    func bindTo(on scheduler: Scheduler = .current, _ setValue: @escaping (Value) -> ()) -> Disposable {
        return onValue(on: scheduler, setValue)
    }
    
    /// Start listening on values and update `signal`'s value with the latest signaled value.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func bindTo<WriteSignal: SignalProvider>(_ signal: WriteSignal) -> Disposable where WriteSignal.Value == Value, WriteSignal.Kind == ReadWrite {
        return onValue { signal.providedSignal.value = $0 }
    }
    
    /// Start listening on values and update the value at the `keyPath` of `value`.
    ///
    ///     bindTo(button, \.isEnabled)
    ///
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func bindTo<T>(on scheduler: Scheduler = .current, _ value: T, _ keyPath: ReferenceWritableKeyPath<T, Value>) -> Disposable {
        return onValue(on: scheduler) {
            value[keyPath: keyPath] = $0
        }
    }
}

public extension SignalProvider where Kind == ReadWrite {
    /// Start listening on values for both `self` and `signal` and update each other's value with the latest signaled value.
    /// - Parameter isSame: Are two values the same. Used to avoid infinite recursion.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func bidirectionallyBindTo<WriteSignal: SignalProvider>(_ signal: WriteSignal, isSame: @escaping (Value, Value) -> Bool) -> Disposable where WriteSignal.Value == Value, WriteSignal.Kind == ReadWrite {
        let bag = DisposeBag()
        
        // Use `distinct()` to avoid infinite recursion
        /// Make `self` and `signal` plain to allow `distinct()` to not filter out intitial values, such as `atOnce()`.
        bag += Signal(self).distinct(isSame).bindTo(signal)
        bag += Signal(signal).distinct(isSame).bindTo(self)
        
        return bag
    }
}

public extension SignalProvider where Kind == ReadWrite, Value: Equatable {
    /// Start listening on values for both `self` and `signal` and update each other's value with the latest signaled value.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    /// - Note: Infinite recursion is avoided by comparing equality with the previous value.
    func bidirectionallyBindTo<P: SignalProvider>(_ property: P) -> Disposable where P.Value == Value, P.Kind == ReadWrite {
        return bidirectionallyBindTo(property, isSame: ==)
    }
}

public extension SignalProvider where Value == () {
    /// Start listening on values and toggle `signal`'s value for every recieved event.
    /// - Returns: A disposable that will stop listening on values when being disposed.
    func toggle<P: SignalProvider>(_ signal: P) -> Disposable where P.Value == Bool, P.Kind == ReadWrite {
        let signal = signal.providedSignal
        return onValue { signal.value = !signal.value }
    }
}
