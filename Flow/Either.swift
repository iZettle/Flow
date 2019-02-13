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
            guard case .left(let left) = self else { return nil }
            return left
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
            guard case .right(let right) = self else { return nil }
            return right
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
        case .left(let left): return .left(transform(left))
        case .right(let right): return .right(transform(right))
        }
    }

    /// Returns either left or right.
    var any: Left {
        switch self {
        case .left(let left): return left
        case .right(let right): return right
        }
    }
}

extension Either: Equatable where Left: Equatable, Right: Equatable {
    public static func == (lhs: Either, rhs: Either) -> Bool {
        switch (lhs, rhs) {
        case (.right(let left), .right(let right)):
            return left == right
        case (.left(let left), .left(let right)):
            return left == right
        default:
            return false
        }
    }
}

extension Either: Hashable where Left: Hashable, Right: Hashable {
    // 1010101.... in binary
    private var binaryDistinguisher: Int {
        return Int.max / 3 * 2 + 1
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .left(let left):
            hasher.combine(left)
        case .right(let right):
            hasher.combine(right)
            hasher.combine(binaryDistinguisher)
        }
    }
}
