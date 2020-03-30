//
//  OrderedCallbacker.swift
//  Flow
//
//  Created by Måns Bernhardt on 2017-01-19.
//  Copyright © 2017 iZettle. All rights reserved.
//

import Foundation

/// OrderedCallbacker holds a list of callbacks that can be call backed ordered by a provided `OrderedValue` value
/// A callback won't be called until the previous callback's returned future has completed
/// Use `addCallback` to register a new callback and orderedValue, and dispose the returned `Disposable` to unregister.
/// - Note: Is thread safe.
public final class OrderedCallbacker<OrderedValue, CallbackValue> {
    private var callbacks: [Key: (OrderedValue, (CallbackValue) -> Future<()>)] = [:]
    private var _mutex = pthread_mutex_t()

    public init() {
        _mutex.initialize()
    }

    deinit {
        _mutex.deinitialize()
    }

    /// - Returns: True if no callbacks has been registered.
    public var isEmpty: Bool {
        _mutex.lock()
        let isEmpty = callbacks.isEmpty
        _mutex.unlock()
        return isEmpty
    }

    /// Register a callback and orderedValue to be called when `callAll` is executed.
    /// - Parameter callback: The next callback won't be called until `callback` return `Future` completes
    /// - Parameter orderedValue: The value used to order this callback
    /// - Returns: A `Disposable` to be disposed to unregister the callback.
    public func addCallback(_ callback: @escaping (CallbackValue) -> Future<()>, orderedBy orderedValue: OrderedValue) -> Disposable {
        _mutex.lock()
        defer { _mutex.unlock() }
        let key = generateKey()
        callbacks[key] = (orderedValue, callback)
        return Disposer {
            self._mutex.lock()
            self.callbacks[key] = nil
            self._mutex.unlock()
        }
    }

    /// Will call all registered callbacks with `value` in the order set by `isOrderedBefore`
    /// - Returns: A `Future` that will complete when all callbacks has been called.
    @discardableResult
    public func callAll(with value: CallbackValue, isOrderedBefore: (OrderedValue, OrderedValue) -> Bool) -> Future<()> {
        _mutex.lock()
        let sortedCallbacks = callbacks.values.sorted { isOrderedBefore($0.0, $1.0) }.map { $1 }
        _mutex.unlock()
        return sortedCallbacks.mapToFuture { $0(value) }.toVoid()
    }
}

public extension OrderedCallbacker {
    /// Register a callback and orderedValue to be called when `callAll` is executed.
    /// - Parameter orderedValue: The value used to order this callback
    /// - Returns: A `Disposable` to be disposed to unregister the callback.
    func addCallback(_ callback: @escaping (CallbackValue) -> Void, orderedBy orderedValue: OrderedValue) -> Disposable {
        return addCallback({ value -> Future<()> in callback(value); return Future() }, orderedBy: orderedValue)
    }
}

public extension OrderedCallbacker where OrderedValue: Comparable {
    /// Will call all registered callbacks with `value` in the order set by `Comparable`
    /// - Returns: A `Future` that will complete when all callbacks has been called.
    @discardableResult
    func callAll(with value: CallbackValue) -> Future<()> {
        return callAll(with: value, isOrderedBefore: <)
    }
}
