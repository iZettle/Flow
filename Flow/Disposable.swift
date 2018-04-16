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
    private var mutex: PThreadMutex { return PThreadMutex(&_mutex) }

    /// Pass a closure to be called when being disposed
    public init(_ disposer: @escaping () -> () = {}) {
        self.disposer = disposer
        mutex.initialize()
    }
    
    deinit {
        dispose()
        mutex.deinitialize()
    }
    
    public func dispose() {
        mutex.lock()
        let d = disposer
        disposer = nil
        mutex.unlock()
        d?()
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
    private var mutex: PThreadMutex { return PThreadMutex(&_mutex) }

    /// Create an empty instance
    public init() {
        self.disposables = []
        mutex.initialize()
    }

    /// Create an instance already containing `disposables`
    public init<S: Sequence>(_ disposables: S) where S.Iterator.Element == Disposable {
        self.disposables = Array(disposables)
        mutex.initialize()
    }

    /// Create an instance already containing `disposables`
    public init(_ disposables: Disposable...) {
        self.disposables = disposables
        mutex.initialize()
    }

    deinit {
        dispose()
        mutex.deinitialize()
    }
    
    /// Returns true if there is currently no disposables to dispose.
    public var isEmpty: Bool {
        return mutex.protect { disposables.isEmpty }
    }
    
    public func dispose() {
        mutex.lock()
        let ds = disposables // make sure to make a copy in the case any call to dispose will recursivaly call us back.
        disposables = []
        mutex.unlock()
        for d in ds { d.dispose() }
    }
    
    /// Add `disposable` to `self`
    public func add(_ disposable: Disposable) {
        mutex.lock()
        defer { mutex.unlock() }
        disposables.append(disposable)
    }
}

public extension DisposeBag {
    /// Creates a new bag, adds it to self, and returns it
    public func innerBag() -> DisposeBag {
        let bag = DisposeBag()
        add(bag)
        return bag
    }
}

public func +=(disposeBag: DisposeBag, disposable: Disposable?) {
    if let d = disposable {
        disposeBag.add(d)
    }
}

public func +=(disposeBag: DisposeBag, disposer: @escaping () -> Void) {
    disposeBag.add(Disposer(disposer))
}

public func +=(disposeBag: DisposeBag?, disposable: Disposable?) {
    if let d = disposable {
        disposeBag?.add(d)
    }
}

public func +=(disposeBag: DisposeBag?, disposer: @escaping () -> Void) {
    disposeBag?.add(Disposer(disposer))
}

public extension Disposable {
    /// Returns a future that will complete after `timeout`. Once completed or canceled, `self` will be disposed.
    @discardableResult
    func dispose(on scheduler: Scheduler = .current, after timeout: TimeInterval) -> Future<()> {
        return Future().delay(by: timeout).always(on: scheduler, self.dispose)
    }
}

public func +=<T>(disposeBag: DisposeBag, future: Future<T>) {
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


