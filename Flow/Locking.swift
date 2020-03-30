//
//  Locking.swift
//  Flow
//
//  Created by Måns Bernhardt on 2017-06-21.
//  Copyright © 2017 iZettle. All rights reserved.
//

import Foundation

/// A reference wrapper around a POSIX thread mutex
public final class Mutex {
    private var _mutex = pthread_mutex_t()

    public init() {
        _mutex.initialize()
    }

    deinit {
        _mutex.deinitialize()
    }

    /// Attempt to acquire the lock, blocking a thread’s execution until the lock can be acquired.
    public func lock() {
        _mutex.lock()
    }

    /// Releases a previously acquired lock.
    public func unlock() {
        _mutex.unlock()
    }
}

extension pthread_mutex_t {
    mutating func withPointer<T>(_ body: (PThreadMutex) throws -> T) rethrows -> T {
        try withUnsafeMutablePointer(to: &self, body)
    }
    
    mutating func initialize() {
        withPointer { $0.initialize() }
    }

    mutating func deinitialize() {
        withPointer { $0.deinitialize() }
    }

    mutating func lock() {
        withPointer { $0.lock() }
    }

    mutating func unlock() {
        withPointer { $0.unlock() }
    }
}

typealias PThreadMutex = UnsafeMutablePointer<pthread_mutex_t>

/// Helper methods to work directly with a Pthread mutex pointer to avoid overhead of alloction and reference counting of using the Mutex reference type.
/// - Note: You have to explicity call `initialize()` before use (typically in a class init) and `deinitialize()` when done (typically in a class deinit)
extension UnsafeMutablePointer where Pointee == pthread_mutex_t {
    func initialize() {
        var attr = pthread_mutexattr_t()
        guard pthread_mutexattr_init(&attr) == 0 else {
            preconditionFailure()
        }

        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_NORMAL)

        guard pthread_mutex_init(self, &attr) == 0 else {
            preconditionFailure()
        }
    }

    func deinitialize() {
        pthread_mutex_destroy(self)
    }

    /// Attempt to acquire the lock, blocking a thread’s execution until the lock can be acquired.
    func lock() {
        pthread_mutex_lock(self)
    }

    /// Releases a previously acquired lock.
    func unlock() {
        pthread_mutex_unlock(self)
    }

    /// Will lock `self`, call `block`, then unlock `self`
    @discardableResult
    func protect<T>(_ block: () throws -> T) rethrows -> T {
        pthread_mutex_lock(self)
        defer { pthread_mutex_unlock(self) }
        return try block()
    }
}

/// Internal helper to help manage state in stateful transforms.
final class StateAndCallback<Value, State>: Disposable {
    var callback: ((Value) -> ())?
    var val: State
    fileprivate var disposables = [Disposable]()
    private var _mutex = pthread_mutex_t()

    init(state: State, callback: @escaping (Value) -> ()) {
        val = state
        self.callback = callback
        _mutex.initialize()
    }

    deinit {
        _mutex.deinitialize()
        dispose()
    }

    var protectedVal: State {
        get { return protect { val } }
        set { protect { val = newValue } }
    }

    func lock() {
        _mutex.lock()
    }

    func unlock() {
        _mutex.unlock()
    }

    @discardableResult
    func protect<T>(_ block: () throws -> T) rethrows -> T {
        _mutex.lock()
        defer { _mutex.unlock() }
        return try block()
    }

    func dispose() {
        _mutex.lock()
        let disposables = self.disposables // make sure to make a copy in the case any call to dispose will recursivaly call us back.
        callback = nil
        exclusiveQueue = []
        self.disposables = []
        _mutex.unlock()
        for disposable in disposables { disposable.dispose() }
    }

    private var exclusiveCount = 0
    private var exclusiveQueue = [() -> ()]()

    private func releaseQueue() {
        guard exclusiveCount == 0, !exclusiveQueue.isEmpty else { return unlock() }

        let completions = exclusiveQueue
        exclusiveQueue = []

        exclusiveCount += 1
        unlock()
        for completion in completions {
            completion()
        }
        lock()
        exclusiveCount -= 1

        // While releasing, more might have been queued up, so make sure to release those as well.
        releaseQueue()
    }

    func callback(_ value: Value) {
        lock()
        guard let callback = callback else { return unlock() }
        unlock()
        callback(value)
    }

    func call<T>(_ eventType: EventType<T>) where Value == EventType<T> {
        lock()
        guard let callback = callback else { return unlock() }

        exclusiveCount += 1
        if exclusiveCount <= 1 {
            unlock()
            if case .event(.end) = eventType {
                dispose()
            }
            callback(eventType)
            lock()
        } else {
            exclusiveQueue.append {
                if case .event(.end) = eventType {
                    self.dispose()
                }

                callback(eventType)
            }
        }
        exclusiveCount -= 1
        releaseQueue()
    }
}

extension StateAndCallback where Value == () {
    convenience init(state: State) {
        self.init(state: state, callback: {})
    }
}

func +=<Value, State>(bag: StateAndCallback<Value, State>, disposable: Disposable?) {
    guard let disposable = disposable else { return }
    bag.lock()
    let hasBeenDisposed = bag.callback == nil
    if !hasBeenDisposed {
        bag.disposables.append(disposable)
    }
    bag.unlock()
    if hasBeenDisposed {
        disposable.dispose()
    }
}
