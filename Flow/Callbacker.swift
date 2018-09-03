//
//  Callbacker.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-02-10.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation

/// Callbacker holds a list of callbacks that can be called by `callAll`
/// Use `addCallback` to register a new callback, and dispose the returned `Disposable` to unregister.
/// - Note: Is thread safe.
public final class Callbacker<Value> {
    // Adding special treatment of the single callback case improves performance about 4 times in release builds
    private enum Callbacks {
        case none
        case single(Key, (Value) -> Void)
        case multiple([Key: (Value) -> Void])
    }

    private var callbacks = Callbacks.none
    private var _mutex = pthread_mutex_t()
    private var mutex: PThreadMutex { return PThreadMutex(&_mutex) }

    public init() {
        mutex.initialize()
    }

    deinit {
        mutex.deinitialize()
    }

    /// - Returns: True if no callbacks has been registered.
    public var isEmpty: Bool {
        mutex.lock()
        defer { mutex.unlock() }

        switch callbacks {
        case .none: return true
        case .single: return false
        case .multiple(let completions): return completions.isEmpty
        }
    }

    /// Register a callback to be called when `callAll` is executed.
    /// - Returns: A `Disposable` to be disposed to unregister the callback.
    public func addCallback(_ callback: @escaping (Value) -> Void) -> Disposable {
        mutex.lock()
        defer { mutex.unlock() }

        let key = generateKey()

        switch callbacks {
        case .none:
            callbacks = .single(key, callback)
        case .single(let singleKey, let completion):
            callbacks = .multiple([singleKey: completion, key: callback])
        case .multiple(var completions):
            callbacks = .none // let go of reference to cs to allow modification to not cause copy-on-write
            completions[key] = callback
            callbacks = .multiple(completions)
        }

        return NoLockKeyDisposer(key) { key in
            self.mutex.lock()
            defer { self.mutex.unlock() }

            switch self.callbacks {
            case .single(let singleKey, _) where singleKey == key:
                self.callbacks = .none
            case  .none, .single:
                break // trying to remove the key a second time (NoLockKeyDisposer can be called more than once)
            case .multiple(var completions):
                self.callbacks = .none // let go of reference to cs to allow modification to not cause copy-on-write
                completions.removeValue(forKey: key)
                // Not worth going back to single if we are back to one callback as we don't won't to be the cost of allocating another dictionary.
                self.callbacks = .multiple(completions)
            }
        }
    }

    /// Will call all registered callbacks with `value`
    public func callAll(with value: Value) {
        mutex.lock()
        let callbacks = self.callbacks
        mutex.unlock()

        switch callbacks {
        case .none: break
        case .single(_, let completion):
            completion(value)
        case .multiple(let completions):
            for (_, completion) in completions { completion(value) }
        }
    }
}

public extension Callbacker where Value == () {
    /// Will call all registered callbacks with `value`
    public func callAll() {
        callAll(with: ())
    }
}

extension Callbacker: SignalProvider {
    public var providedSignal: Signal<Value> {
        return Signal(callbacker: self)
    }
}
