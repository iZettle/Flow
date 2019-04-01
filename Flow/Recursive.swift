//
//  Recursive.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-11-17.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation

/// Helper to setup local recursive functions without retaining any captured values forever.
/// Once the returned function is released, what's captured inside the recursive function will be released as well.
///
///     let resource = ...
///     let myFunc: (Int) -> () = recursive { arg, myFunc in
///       /// Use `resource`, once the external `myFunc` is released, `resource` will be released as well.
///       arg > 0 ? (myFunc(arg-1) ?? ()) : () // `myFunc` might return nil if the external `myFunc` has been released.
///     }
///     myFunc(4711)
///
///     let fact: (Int) -> Int = recursive { n, fact in
///       return n > 1 ? n*(fact(n - 1) ?? 0) : 1
///     }
public func recursive<A, R>(_ recursiveFunction: @escaping (A, @escaping (A) -> R?) -> R) -> (A) -> R {
    let recursive = Recursive(recursiveFunction)
    return { argument in recursive.function(argument) }
}

public func recursive<R>(_ recursiveFunction: @escaping (@escaping () -> R?) -> R) -> () -> R {
    let recursive = Recursive<(), R> { _, function in
        recursiveFunction { function(()) }
    }
    return { recursive.function(()) }
}

private final class Recursive<A, R> {
    fileprivate var function: ((A) -> R)!

    init(_ recursiveFunction: @escaping (A, @escaping (A) -> R?) -> R) {
        self.function = { [weak self] argument in
            return recursiveFunction(argument, { argument in
                self?.function(argument)
            })
        }
    }
}
