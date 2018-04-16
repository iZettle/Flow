//
//  Enablable.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation


/// Whether the conforming object can be enabled and disabled.
public protocol Enablable: class {
    var isEnabled: Bool { get set }
}

public extension Enablable {
    /// Will disable `self` and return a disposable that will upon disposal revert to the value set before calling disable.
    func disable() -> Disposable {
        let prev = isEnabled
        isEnabled = false
        return Disposer { self.isEnabled = prev }
    }
}

public extension SignalProvider where Kind == ReadWrite, Value == Bool {
    /// Will disable `self` and return a disposable that will upon disposal revert to the value set before calling disable.
    func disable() -> Disposable {
        let prev = self.value
        self.value = false
        return Disposer { self.value = prev }
    }
}

/// Whether the conforming class has event listeners.
public protocol HasEventListeners: class {
    /// Boolean value indicating whether the instance has event listeners.
    var hasEventListeners: Bool { get }
}

/// Whether the conforming object supports auto enabling.
public protocol AutoEnablable: Enablable {
    /// Boolean value indicating whether the instance should be automatically enabled while having listeners
    var enablesAutomatically: Bool { get set }
}

// Default `AutoEnablable` conformance for `HasEventListeners`s
public extension AutoEnablable where Self: HasEventListeners {
    var enablesAutomatically: Bool {
        get {
            return objc_getAssociatedObject(self, &enablesAutomaticallyKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &enablesAutomaticallyKey, newValue ? true : nil, .OBJC_ASSOCIATION_RETAIN)
            updateAutomaticEnabling()
        }
    }
    
    func updateAutomaticEnabling() {
        if enablesAutomatically {
            isEnabled = hasEventListeners
        }
    }
}

private var enablesAutomaticallyKey = false

