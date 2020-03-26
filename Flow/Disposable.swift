//
//  Disposable.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-02-22.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation

/// Something that is `Disposable` will free up what is hold on to when `dispose` is called
/// When the instance of a `Disposable` is deinitialized it should dispose it self.
/// This means the conforming types often are classes calling `dispose` from `deinit`
public protocol Disposable {
    /// Will dispose its content
    func dispose()
}

/// A low-const instance of Disposable not holding anything to dispose.
public struct NilDisposer: Disposable {
    public init() {}
    public func dispose() {}
}

/// Holds a single dispose callback that is guaranteed to be called only once.
/// - Note: Will release the dispose closure at dispose
/// - Note: Will dispose itself when deallocated
/// - Note: Is thread safe and reentrant (dispose callback could call itself)
public final class Disposer: Disposable {
    private var disposer: (() -> ())?
    private var _mutex = pthread_mutex_t()
    private func withMutex<T>(_ body: (PThreadMutex) throws -> T) rethrows -> T {
        try withUnsafeMutablePointer(to: &_mutex, body)
    }

    /// Pass a closure to be called when being disposed
    public init(_ disposer: @escaping () -> () = {}) {
        self.disposer = disposer
        withMutex { $0.initialize() }
    }

    deinit {
        dispose()
        withMutex { $0.deinitialize() }
    }

    public func dispose() {
        withMutex { $0.lock() }
        let disposer = self.disposer
        self.disposer = nil
        withMutex { $0.unlock() }
        disposer?()
    }
}

/// Holds one to many `Disposable` that will be disposed when `dispose` is called.
/// - Note: Will dispose itself when deallocated
/// - Note: Is thread safe and reentrant (dispose callback could call itself)
/// - Note: Dispose will remove all disposable after beeing dispose.
/// - Note: New disposables could be added after a disposal.
public final class DisposeBag: Disposable {
    private var disposables: [Disposable]
    private var _mutex = pthread_mutex_t()
    private func withMutex<T>(_ body: (PThreadMutex) throws -> T) rethrows -> T {
        try withUnsafeMutablePointer(to: &_mutex, body)
    }

    /// Create an empty instance
    public init() {
        self.disposables = []
        withMutex { $0.initialize() }
    }

    /// Create an instance already containing `disposables`
    public init<S: Sequence>(_ disposables: S) where S.Iterator.Element == Disposable {
        self.disposables = Array(disposables)
        withMutex { $0.initialize() }
    }

    /// Create an instance already containing `disposables`
    public init(_ disposables: Disposable...) {
        self.disposables = disposables
        withMutex { $0.initialize() }
    }

    deinit {
        dispose()
        withMutex { $0.deinitialize() }
    }

    /// Returns true if there is currently no disposables to dispose.
    public var isEmpty: Bool {
        return withMutex { $0.protect { disposables.isEmpty } }
    }

    public func dispose() {
        withMutex { $0.lock() }
        let disposables = self.disposables // make sure to make a copy in the case any call to dispose will recursivaly call us back.
        self.disposables = []
        withMutex { $0.unlock() }
        for disposable in disposables { disposable.dispose() }
    }

    /// Add `disposable` to `self`
    public func add(_ disposable: Disposable) {
        withMutex { $0.lock() }
        defer { withMutex { $0.unlock() } }
        disposables.append(disposable)
    }
}

public extension DisposeBag {
    /// Creates a new bag, adds it to self, and returns it
    func innerBag() -> DisposeBag {
        let bag = DisposeBag()
        add(bag)
        return bag
    }

    /// Will hold a reference to `object` until self is disposed.
    ///
    ///     bag.hold(delegate)
    func hold(_ object: AnyObject...) {
        self += { _ = object }
    }
}

public func += (disposeBag: DisposeBag, disposable: Disposable?) {
    if let disposable = disposable {
        disposeBag.add(disposable)
    }
}

public func += (disposeBag: DisposeBag, disposer: @escaping () -> Void) {
    disposeBag.add(Disposer(disposer))
}

public func += (disposeBag: DisposeBag?, disposable: Disposable?) {
    if let disposable = disposable {
        disposeBag?.add(disposable)
    }
}

public func += (disposeBag: DisposeBag?, disposer: @escaping () -> Void) {
    disposeBag?.add(Disposer(disposer))
}

public extension Disposable {
    /// Returns a future that will complete after `timeout`. Once completed or canceled, `self` will be disposed.
    @discardableResult
    func dispose(on scheduler: Scheduler = .current, after timeout: TimeInterval) -> Future<()> {
        return Future().delay(by: timeout).always(on: scheduler, self.dispose)
    }
}

public func +=<T> (disposeBag: DisposeBag, future: Future<T>) {
    disposeBag += future.disposable
}

/// Internal lower cost implementation of Disposer where we don't need to capture the key and can guarantee thread-safty yourself.
final class NoLockKeyDisposer: Disposable {
    let value: Key
    let disposer: (Key) -> ()

    init(_ value: Key, _ disposer: @escaping (Key) -> ()) {
        self.value = value
        self.disposer = disposer
    }

    // No guarantee that disposer is not called more than once as we won't nil the callback after being called (we need a lock for that)
    func dispose() {
        disposer(value)
    }

    deinit {
        dispose()
    }
}
