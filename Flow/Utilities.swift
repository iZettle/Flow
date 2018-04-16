//
//  Utilities.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-03-11.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation

// Generate a new key
func generateKey() -> Key {
    _nextKeyMutex.lock()
    defer { _nextKeyMutex.unlock() }
    _nextKey = _nextKey &+ 1
    return _nextKey
}

typealias Key = UInt64
private var _nextKey: Key = 0
private var __nextKeyMutex = pthread_mutex_t()
private var _nextKeyMutex: PThreadMutex = {
    let m = PThreadMutex(&__nextKeyMutex)
    m.initialize()
    return m
}()
