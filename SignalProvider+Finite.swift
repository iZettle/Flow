//
//  SignalProvider+Finite.swift
//  Flow
//
//  Created by Vasil Nunev on 2018-10-29.
//  Copyright © 2018 iZettle. All rights reserved.
//

import Foundation

public extension SignalProvider where Kind == Finite {
    /// Returns a new signal forwarding the values from the signal returned from `transform`, ignoring any errors.
    ///
    ///     ---a--------b------------|
    ///        |        |
    ///     +-------------------------+
    ///     | flatMapLatest() - plain |
    ///     +-------------------------+
    ///     ---s1-------s2-----------|
    ///        |        |
    ///     -----1---2-----1---2--3--|
    ///
    ///     0)--------a---------b----------|
    ///               |         |
    ///     +----------------------------+
    ///     | flatMapLatest() - readable |
    ///     +----------------------------+
    ///     s0)-------s1--------s2---------|
    ///               |         |
    ///     0)--1--2--0--1--2---0--1--2----|
    ///
    /// - Note: If `self` signals a value, any a previous signal returned from `transform` will be disposed.
    /// - Note: If `self` and `other` are both readable their current values will be used as initial values.
    /// - Note: If either `self` of the signal returned from `transform` are terminated, the returned signal will terminated as well.
    func flatMapLatestIgnoringError<V>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> FiniteSignal<V>) -> FiniteSignal<V> {
        return flatMapLatest(on: scheduler) { value in
            transform(value).neverEnds()
        }
    }

    /// Returns a new finite signal that never terminates.
    func neverEnds() -> FiniteSignal<Value> {
        return self.plain().finite()
    }
}
