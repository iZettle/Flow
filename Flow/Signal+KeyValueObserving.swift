//
//  Signal+KeyValueObserving.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-01-08.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation


// https://github.com/apple/swift/blob/master/stdlib/public/SDK/Foundation/NSObject.swift
public extension _KeyValueCodingAndObserving {
    /// Returns a signal observing the property at `keyPath` of `self` using key value observing (KVO).
    func signal<T>(for keyPath: KeyPath<Self, T>) -> ReadSignal<T> {
        return ReadSignal(object: self, keyPath: keyPath)
    }

    /// Returns a signal observing the property at `keyPath` of `self` using key value observing (KVO).
    func signal<T>(for keyPath: WritableKeyPath<Self, T>) -> ReadWriteSignal<T> {
        return ReadWriteSignal(object: self, keyPath: keyPath)
    }
}

public extension CoreSignal where Kind == Read {
    /// Creates a new instance observing the property at `keyPath` of `object` using key value observing (KVO).
    convenience init<O: _KeyValueCodingAndObserving>(object: O, keyPath: KeyPath<O, Value>) {
        self.init(getValue: { object[keyPath: keyPath] }, options: .shared, onInternalEvent: { c in
            let token = object.observe(keyPath, options: .new) { _, change in
                c(.value(object[keyPath: keyPath]))
            }
            return Disposer { _ = token } // Hold on to reference
        })
    }
}

public extension CoreSignal where Kind == ReadWrite {
    /// Creates a new instance observing the property at `keyPath` of `object` using key value observing (KVO).
    convenience init<O: _KeyValueCodingAndObserving>(object: O, keyPath: WritableKeyPath<O, Value>) {
        var o = object
        self.init(getValue: { object[keyPath: keyPath] }, setValue: { o[keyPath: keyPath] = $0 }, options: .shared, onInternalEvent: { c in
            let token = object.observe(keyPath, options: .new) { _, _ in
                c(.value(object[keyPath: keyPath]))
            }
            return Disposer { _ = token } // Hold on to reference
        })
    }
}

