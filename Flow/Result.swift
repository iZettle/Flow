//
//  Result.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-11-14.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation


/// A value indicating either a `success` value or a `failure` error.
public enum Result<Value> {
    case success(Value)
    case failure(Error)
}

public extension Result where Value == () {
    /// Constant to allow writing `.success` instead of `.success(())` where a `Result<()>` is expected.
    static var success: Result {
        return .success(())
    }
}

public extension Result {
    /// Creates a new instance using the `Value` returned from the `getValue` closure.
    /// If `getValue` throws an error, the instance will instead be set to `.failure(error)`
    ///
    ///     let result = Result { try evaluate() }
    init(_ getValue: () throws -> Value) {
        do {
            self = .success(try getValue())
        } catch {
            self = .failure(error)
        }
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
    func getValue() throws -> Value {
        switch self {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

public extension Result {
    /// Returns a new value with result of transforming the `success` value using `transform`.
    /// If `self` is an error or `transform` throws an error, the returned value will instead be `.failure(error)`.
    func flatMap<O>(_ transform: (Value) throws -> Result<O>) -> Result<O> {
        return Result<O> { try transform(getValue()).getValue() }
    }

    /// Returns a new `success` value from transforming the `success` value using `transform`.
    /// If `self` is an error or `transform` throws an error, the returned value will instead be `.failure(error)`.
    func map<O>(_ transform: (Value) throws -> O) -> Result<O> {
        return flatMap { .success(try transform($0)) }
    }
}
