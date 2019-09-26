//
//  Result.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-11-14.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation

/// A value indicating either a `success` value or a `failure` error.
public typealias Result<Value> = Swift.Result<Value, Error>

public extension Result {
    typealias Value = Success
}

public extension Result where Success == () {
    /// Constant to allow writing `.success` instead of `.success(())` where a `Result<()>` is expected.
    static var success: Flow.Result<Void> {
        return .success(())
    }
}

public extension Result {
    /// Returns the value if `self` is .success or nil otherwise.
    var value: Value? {
        if case .success(let value) = self { return value }
        return nil
    }

    /// Returns the error if `self` is .failure or nil otherwise.
    var error: Error? {
        if case .failure(let error) = self { return error }
        return nil
    }

    /// Returns the value if `self` is .success or throw the error if self is `.failure`.
    @available(*, deprecated, message: "Use Result.get()")
    func getValue() throws -> Value {
        switch self {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}
