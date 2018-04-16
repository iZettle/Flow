//
//  EventType.swift
//  Flow
//
//  Created by Måns Bernhardt on 2017-02-15.
//  Copyright © 2017 iZettle. All rights reserved.
//

import Foundation


/// A value indicating either a regular `event` or an `initial` event, optionally with a value.
enum EventType<Value> {
    case initial(Value?)
    case event(Event<Value>)
}

extension EventType {
    func map<O>(_ transform: (Value) throws -> O) rethrows -> EventType<O> {
        switch self {
        case .initial(nil): return .initial(nil)
        case .initial(let val?): return try .initial(transform(val))
        case .event(.value(let val)): return try .event(.value(transform(val)))
        case .event(.end(let error)): return .event(.end(error))
        }
    }
    
    func flatMap<O>(_ transform: (Value) throws -> O?) rethrows -> EventType<O>? {
        switch self {
        case .initial(nil): return .initial(nil)
        case .initial(let val?): return try transform(val).map { .initial($0) }
        case .event(.value(let val)): return try transform(val).map { .event(.value(($0))) }
        case .event(.end(let error)): return .event(.end(error))
        }
    }
    
    var value: Value? {
        switch self {
        case .initial(let val?): return val
        case .event(.value(let val)): return val
        default: return nil
        }
    }
}
