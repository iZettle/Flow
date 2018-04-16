//
//  FutureSplitTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2015-11-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation
import Flow
import XCTest



class FutureSplitTests: FutureTest {
    
    func testSplitDirect() {
        testFuture { () -> Future<[Int]> in
            let f = Future(2)
            let f1 = f.map { $0*2 }
            let f2 = f.map { $0*3 }
            return join([f1, f2]).assertValue([4, 6])
        }
    }
    
    func testAllKeepOrdering() {
        testFuture { () -> Future<[Int]> in
            let f1 = Future(1).delay(by: 0.1)
            let f2 = Future(2)
            return join([f1, f2]).assertValue([1, 2])
        }
    }
    
//    func testAllOrderCompleted() {
//        testFuture { () -> Future<[Int]> in
//            let f1 = Future(1).delay(by: 0.1)
//            let f2 = Future(2)
//            return all([f1, f2], ordering: .orderCompleted).assertValue([2, 1])
//        }
//    }
    
    func testSplitDelayed() {
        testFuture(timeout: 100.5) { () -> Future<[Int]> in
            let f = Future(2).delay(by: 0.1)
            let f1 = f.map { $0*2 }
            let f2 = f.delay(by: 0.1).map { $0*3 }
            let f3 = f.map { $0*4 }.delay(by: 0.2)
            
            return join([f1, f2, f3]).assertValue([4, 6, 8])
        }
    }
    
    func testSplitDelayedSwapped() {
        testFuture(timeout: 100.5) { () -> Future<[Int]> in
            let date = Date()
            let f = Future(2).delay(by: 1).always { print("a", -date.timeIntervalSinceNow) }
            let f1 = f.map { $0*2 }.delay(by: 1).always { print("b", -date.timeIntervalSinceNow) }
            let f2 = f.map { $0*3 }.always { print("c", -date.timeIntervalSinceNow) }
            
            return join([f1, f2]).assertValue([4, 6]).always { print("d", -date.timeIntervalSinceNow) }
        }
    }
}

