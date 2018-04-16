//
//  Either.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-10-18.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation


/// A value indicating either a `left` or a `right` value.
public enum Either<Left, Right> {
    case left(Left)
    case right(Right)
}

public extension Either {
    /// Returns the left value if available, otherwise nil
    var left: Left? {
        get {
            guard case .left(let l) = self else { return nil }
            return l
        }
        set {
            guard let val = newValue else {
                fatalError()
            }
            self = .left(val)
        }
    }
    
    /// Returns the left value if available, otherwise nil
    var right: Right? {
        get {
            guard case .right(let r) = self else { return nil }
            return r
        }
        set {
            guard let val = newValue else {
                fatalError()
            }
            self = .right(val)
        }
    }
}

public extension Either where Left == Right {
    /// Returns a new instance where either the left or right value will be transform using `transform`.
    func map<T>(transform: (Left) -> T) -> Either<T, T> {
        switch self {
        case let .left(v): return .left(transform(v))
        case let .right(v): return .right(transform(v))
        }
    }
    
    /// Returns either left or right.
    var any: Left {
        switch self {
        case let .left(v): return v
        case let .right(v): return v
        }
    }
}
