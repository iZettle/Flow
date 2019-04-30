//
//  Delegate.swift
//  Flow
//
//  Created by Måns Bernhardt on 2017-01-16.
//  Copyright © 2017 iZettle. All rights reserved.
//

import Foundation

/// Helper to manage the life time of a delegate `(Arg) -> Ret`.
public final class Delegate<Arg, Ret> {
    private var callbackAndDisposable: (callback: (Arg) -> Ret, disposable: Disposable)?
    private let onSet: (@escaping (Arg) -> Ret) -> Disposable

    /// Creates a new instance.
    /// - Parameter onSet: When `set()` is called with a new callback, `onSet` will be called with the same callback
    ///   and the `Disposable` returned from `onSet` will be hold on to and not disposed until the callback is unset.
    public init(onSet: @escaping (@escaping (Arg) -> Ret) -> Disposable = { _ in NilDisposer() }) {
        self.onSet = onSet
    }

    /// Sets the callback to be called when calling `call()` on `self`.
    /// - Returns: A disposable that will unset the callback once being disposed.
    /// - Note: If a callback was already set, it will be unset before the new callback is set.
    public func set(_ callback: @escaping (Arg) -> Ret) -> Disposable {
        callbackAndDisposable?.disposable.dispose()

        let bag = DisposeBag()
        bag += onSet(callback)
        bag += { self.callbackAndDisposable = nil }

        callbackAndDisposable = (callback, bag)

        return bag
    }

    /// Is a callback currently set?
    public var isSet: Bool {
        return callbackAndDisposable != nil
    }

    /// Call any currently set callback with `arg` and return the result, or return nil if no callback is set.
    public func call(_ arg: Arg) -> Ret? {
        return callbackAndDisposable?.callback(arg)
    }
}

public extension Delegate {
    /// Sets the callback to be called when calling `call()` where the provided `object` will be passed to
    /// the callback as well. The provided `object` will be weakly held and the returned Disposable
    /// will be disposed when the `object` is deallocated.
    /// This is a convenience helper for breaking retain cycles in situations such as:
    ///
    ///     class Class {
    ///       let bag = DisposeBag()
    ///
    ///       func setupUsingWeakCapture() {
    ///         bag += someDelegate.set { [weak self] value in
    ///           guard let `self` = self else { return ?? }
    ///           return self.handle(value)
    ///         }
    ///       }
    ///
    ///       func setupWithWeak() {
    ///         bag += someDelegate.set(withWeak: self) { value, `self` in
    ///           return self.handle(value)
    ///         }
    ///       }
    ///     }
    /// - Returns: A disposable that will unset the callback once being disposed.
    /// - Note: If a callback was already set, it will be unset before the new callback is set.
    func set<T: AnyObject>(withWeak object: T, callback: @escaping (Arg, T) -> Ret) -> Disposable {
        let bag = DisposeBag()

        bag += deallocSignal(for: object).onValue(bag.dispose)

        bag += set { [weak object] arg in
            return callback(arg, object!)
        }

        return bag
    }
}

public extension Delegate where Arg == () {
    /// Call any currently set callback and return the result, or return nil if no callback is set.
    func call() -> Ret? {
        return call(())
    }
}
