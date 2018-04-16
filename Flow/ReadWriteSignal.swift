//
//  ReadWriteSignal.swift
//  Flow
//
//  Created by Måns Bernhardt on 2018-03-12.
//  Copyright © 2018 iZettle. All rights reserved.
//

import Foundation


/// An abstraction for observing events over time where `self` as a notion of a mutable current value.
///
/// A `ReadWriteSignal<T>` is like a `ReadSignal<T>` where the current `value` property is mutable.
///
/// - Note: Most transforms on writable signals will return a read-only or plain signal, as most transforms are not reversable or cannot guarantee to provide a current value.
/// - Note: You can demote a `ReadWriteSignal<T>` to a `ReadSignal<T>` using `readOnly()`.
/// - Note: You can demote a `ReadWriteSignal<T>` to a `Signal<T>` using `plain()`.
/// - Note: `ReadWriteSignal<Value>` is a type alias for `CoreSignal<ReadWrite, Value>` to allow sharing common functionality with the other signal types`.
public typealias ReadWriteSignal<Value> = CoreSignal<ReadWrite, Value>

public extension CoreSignal where Kind == ReadWrite {
    /// Creates a new instance with an initial `value` and where updates to `self.value` will be signaled.
    ///
    /// - Paramenter willSet: Will be called the new value, but before `self.value` is updated and the new value is being signaled.
    /// - Paramenter didSet: Will be called the new value, after `self.value` has been updated and the new value has been signaled.
    convenience init(_ value: Value, willSet: @escaping (Value) -> () = { _ in }, didSet: @escaping (Value) -> () = { _ in }) {
        var _value = value
        let callbacker = Callbacker<Value>()
        self.init(getValue: { _value }, setValue: { val in
            willSet(val)
            _value = val
            callbacker.callAll(with: val)
            didSet(val)
        }, options: [], onInternalEvent: { c in
            return callbacker.addCallback {
                c(.value($0))
            }
        })
    }
    
    /// Creates a new instance getting its current value from `getValue` and where `setValue` is called when `self.value` is updated, whereafter the new value is signaled.
    ///
    /// - Paramenter getValue: Called to get the current value.
    /// - Paramenter setValue: Called when `self.value` is updated, but before the new value is signaled.
    convenience init(getValue: @escaping () -> Value, setValue: @escaping (Value) -> ()) {
        let callbacker = Callbacker<Value>()
        self.init(getValue: getValue, setValue: { setValue($0); callbacker.callAll(with: $0) }, options: [], onInternalEvent: { c in
            return callbacker.addCallback {
                c(.value($0))
            }
        })
    }
}

public extension SignalProvider where Kind == ReadWrite {
    /// Returns a new signal with a read-only `value`.
    func readOnly() -> ReadSignal<Value> {
        return CoreSignal(self)
    }
}

public extension SignalProvider where Kind == ReadWrite {
    // The current value of `self`.
    var value: Value {
        get { return providedSignal.getter()! }
        nonmutating set { providedSignal.setter!(newValue) }
    }
}

private var propertySetterKey = false

internal extension SignalProvider {
    var setter: ((Value) -> ())? {
        return objc_getAssociatedObject(providedSignal, &propertySetterKey) as? (Value) -> ()
    }
}

internal extension CoreSignal {
    convenience init(setValue: ((Value) -> ())?, onEventType: @escaping (@escaping (EventType) -> Void) -> Disposable) {
        self.init(onEventType: onEventType)
        if let setter = setValue {
            objc_setAssociatedObject(self, &propertySetterKey, setter, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
