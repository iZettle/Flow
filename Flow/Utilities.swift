//
//  Utilities.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-03-11.
//  Copyright © 2016 PayPal Inc. All rights reserved.
//

import Foundation

// Generate a new key
func generateKey() -> Key {
    nextKeyMutex.lock()
    defer { nextKeyMutex.unlock() }
    nextKey = nextKey &+ 1
    return nextKey
}

typealias Key = UInt64
private var nextKey: Key = 0
private var nextRawKeyMutex = pthread_mutex_t()
private var nextKeyMutex: PThreadMutex = {
    let mutex = PThreadMutex(&nextRawKeyMutex)
    mutex.initialize()
    return mutex
}()
