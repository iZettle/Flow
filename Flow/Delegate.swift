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
    private var callbackAndDisposable: (callback: (Arg) -> Ret, disposable: Disposable)? = nil
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

extension Delegate where Arg == () {
    /// Call any currently set callback and return the result, or return nil if no callback is set.
    public func call() -> Ret? {
        return call(())
    }
}
