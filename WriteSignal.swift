//
//  WriteSignal.swift
//  Flow
//
//  Created by Carl Ekman on 2018-10-02.
//  Copyright © 2018 iZettle. All rights reserved.
//

import Foundation

public typealias WriteSignal<Value> = CoreSignal<Write, Value>

public extension CoreSignal where Kind == Write {

    convenience init(willSet: @escaping (Value) -> Void = { _ in }, didSet: @escaping (Value) -> Void = { _ in }) {
        let callbacker = Callbacker<Value>()
        self.init(setValue: { val in
            willSet(val)
            callbacker.callAll(with: val)
            didSet(val)
        }, options: [], onInternalEvent: { callback in
            return callbacker.addCallback {
                callback(.value($0))
            }
        })
    }

    convenience init(setValue: @escaping (Value) -> Void) {
        let callbacker = Callbacker<Value>()
        self.init(setValue: { setValue($0); callbacker.callAll(with: $0) }, options: [], onInternalEvent: { callback in
            return callbacker.addCallback {
                callback(.value($0))
            }
        })
    }
}

public extension SignalProvider where Kind == Write {
    /// Writes a value to the signal.
    func emit(_ value: Value) -> Void {
        self.providedSignal.setter!(value)
    }

    /// Returns a new signal with no access to a current `value`.
    func plain() -> Signal<Value> {
        return Signal(self)
    }
}

public extension SignalProvider where Kind == Write, Value == Void {
    /// Writes a value of Void to the signal.
    func emit() -> Void {
        self.providedSignal.setter!(())
    }
}
