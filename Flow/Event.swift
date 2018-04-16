//
//  Event.swift
//  Flow
//
//  Created by Måns Bernhardt on 2017-02-15.
//  Copyright © 2017 iZettle. All rights reserved.
//

import Foundation


/// A value indicating either a `value` or an `end`, optionally with an error.
public enum Event<Value> {
    case value(Value)
    case end(Error?)
}

public extension Event {
    // The value of `self` if available
    var value: Value? {
        if case let .value(value) = self { return value }
        return nil
    }
    
    // The error of `self` if available
    var error: Error? {
        if case let .end(error) = self { return error }
        return nil
    }
    
    // Is this an end and not a value event?
    var isEnd: Bool {
        if case .end = self { return true }
        return false
    }
}

public extension Event {
    /// Constant to allow writing `.end` instead of `.end(nil)`.
    static var end: Event {
        return .end(nil)
    }
}

