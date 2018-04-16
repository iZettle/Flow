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
public func recursive<A, R>(_ f: @escaping (A,  @escaping (A) -> R?) -> R) -> (A) -> R {
    let r = Recursive(f)
    return { a in r.function(a) }
}

public func recursive<R>(_ f: @escaping (@escaping () -> R?) -> R) -> () -> R {
    let r = Recursive<(), R> { _, r in
        f(r)
    }
    return { r.function(()) }
}

private final class Recursive<A, R> {
    fileprivate var function: ((A) -> R)!
    
    init(_ f: @escaping (A, @escaping (A) -> R?) -> R) {
        self.function = { [weak self] a in
            return f(a, { a in
                self?.function(a)
            })
        }
    }
}


