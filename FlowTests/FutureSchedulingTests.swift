//
//  FutureSchedulingTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2015-11-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation
import Flow
import XCTest


extension Scheduler {
    static let concurrentBackground = Scheduler(label: "flow.background", attributes: .concurrent)
}

func assertConcurrentBackground() {
    if !Scheduler.concurrentBackground.isExecuting {
        print()
    }
    XCTAssertTrue(Scheduler.concurrentBackground.isExecuting, "Not on concurrentBackground")
}


class FutureNewSchedulingTests: FutureTest {
    func testMap() {
        let e = expectation(description: "complete")
        Future(5).map(on: .concurrentBackground) { val -> Int in
            assertConcurrentBackground()
            return val*2
        }.map { val -> Int in
            assertMain()
            return val + 1
        }.onValue { val in
            assertMain()
            XCTAssertEqual(val, 5*2 + 1)
            e.fulfill()
        }
        
        waitForExpectations(timeout: 100) { _ in }
    }
    
    func testFlatMap() {
        let e = expectation(description: "complete")
        Future(5).flatMap(on: .concurrentBackground) { val -> Future<Int> in
            assertConcurrentBackground()
            return Future().flatMap {
                assertConcurrentBackground()
                return Future(val*2)
            }
        }.flatMap { val -> Future<Int> in
            assertMain()
            return Future(val + 1)
        }.onValue { val in
            assertMain()
            XCTAssertEqual(val, 5*2 + 1)
            e.fulfill()
        }
        
        
        waitForExpectations(timeout: 100) { _ in }
    }

    func testPassingShedulerAtInit() {
        testFuture(repeatCount: 100) {
            Future(on: .concurrentBackground) { c in
                assertConcurrentBackground()
                c(.success(4711))
                return NilDisposer()
            }.assert(on: .main).assertValue(4711)
        }
    }
    
    func testPassingShedulerAtInitDelay() {
        testFuture(repeatCount: 100) {
            Future(on: .concurrentBackground) { c in
                assertConcurrentBackground()
                c(.success(4711))
                return NilDisposer()
            }.delay(by: 0.01).assert(on: .main).assertValue(4711)
        }
    }

    func testManyDelayedToMain() {
        testFuture(timeout: 5) { () -> Future<[Int]> in
            let futures = join((1...100).map { (v: Int) -> Future<Int> in
                var f = Future(v).delay(by: TimeInterval(v%10)/1000)
                f = f.map { val -> Int in
                    assertMain()
                    return val*2
                }
                return f.assertValue(v*2).assert(on: .main)
            })
            
            return futures.assert(on: .main).onValue { v in XCTAssertEqual(v, (1...100).map { $0*2 }) }
        }
    }
    
    func testManyDelayedToBackground() {
        testFuture(timeout: 5) { () -> Future<[Int]> in
            let futures = join((1...100).map { (v: Int) -> Future<Int> in
                var f = Future(v).delay(by: TimeInterval(v%10)/1000)
                f = f.map(on: .concurrentBackground) { val -> Int in
                    assertConcurrentBackground()
                    return val*2
                }
                return f.assertValue(v*2).assert(on: .main)
            })
            
            return futures.assert(on: .main).onValue { v in XCTAssertEqual(v, (1...100).map { $0*2 }) }
        }
    }
    
    func testManyDelayedToBackgroundOrMain() {
        testFuture(repeatCount: 10, timeout: 5) { () -> Future<[Int]> in
            let futures = join((1...100).map { (v: Int) -> Future<Int> in
                var f = Future(v).delay(by: TimeInterval(v%10)/1000)
                f = f.map(on: v%2 == 0 ? .concurrentBackground : .main) { $0*2 }
                return f.assertValue(v*2)
            })
            
            return futures.onValue { v in XCTAssertEqual(v, (1...100).map { $0*2 }) }.assert(on: .main)
        }
    }
    
    func testDelayMain() {
        testFuture(repeatCount: 0, timeout: 1) {
            Future(5).delay(by: 0.1).assert(on: .main).assertDelay(0.09)
        }
    }
    
    func testDelayBackground() {
        testFuture(repeatCount: 10, timeout: 1) { () -> Future<Int> in
            return Future().flatMap(on: .concurrentBackground) {
                Future(1).delay(by: 0.1).assert(on: .concurrentBackground).assertDelay(0.09)
            }.assert(on: .main)
        }
    }

    func testDirectCancelOnMain() {
        testFuture(repeatCount: 0, timeout: 5, allDoneDelay: 1, cancelAfterDelay: 0) { () -> Future<Int> in
            let e = cancelExpectation()
            let future = Future(5).delay(by: 0.3).onCancel {
                e.fulfill()
            }
            return future
        }
    }

    func testDelayedCancelOnMainTemp() {
        testFuture(repeatCount: 10, timeout: 5, allDoneDelay: 100, cancelAfterDelay: 0.01) { () -> Future<Int> in
            return Future(5).delay(by: 0.3)
        }
    }

    func testDelayedCancelOnMain() {
        testFuture(repeatCount: 10, timeout: 5, allDoneDelay: 1, cancelAfterDelay: 0.01, cancelOn: .globalBackground) { () -> Future<Int> in
            let e = cancelExpectation()
            let future = Future(5).delay(by: 0.3).onCancel {
                assertMain()
                e.fulfill()
            }.assertNoValue().assert(on: .main)
            return future
        }
    }
    
    func testCancelBackground() {
        testFuture(repeatCount: 10, timeout: 5, allDoneDelay: 1, cancelAfterDelay: 0.01, cancelOn: .globalBackground) { () -> Future<Int> in
            let e = cancelExpectation()
            return Scheduler.concurrentBackground.sync {
                Future(1).delay(by: 0.3).onCancel {
                    assertConcurrentBackground()
                    e.fulfill()
                }.assertNoValue().assert(on: .concurrentBackground)
            }
        }
    }
    
    func testCancelAllBackground() {
        testFuture(repeatCount: 0, timeout: 3, allDoneDelay: 4, cancelAfterDelay: 1, cancelOn: .globalBackground) { () -> Future<[Int]> in
            let mutex = Mutex()
            let e = cancelExpectation()
            var completeCount = 0
            let future = join((1...50).map { (v: Int) -> Future<Int> in
                let delay = 0 + TimeInterval(v%10)/2 // 0 - 5
                var f = Future(v).delay(by: delay)
                f = f.map(on: .concurrentBackground) { $0*2 }
                return f/*assertValue(v*2)*/.assert(on: .main).always(on: .concurrentBackground) {
                    mutex.protect { completeCount += 1 }
                }
            }).onCancel { e.fulfill() }
            
            return future
        }
    }
    
    fileprivate func operationUnknownCallbackQueue() -> Future<Int> {
        return Future { c in
            DispatchQueue.global(qos: .default).async { c(.success(4711)) }
            return NilDisposer()
        }
    }
    
    func testOperationUnknownCallackQueueFromMain() {
        testFuture(repeatCount: 0) {
            operationUnknownCallbackQueue().assert(on: .main).assertValue(4711)
        }
    }
    
    func testOperationUnknownCallackQueueFromBackground() {
        testFuture(repeatCount: 10) {
            Future().flatMapResult(on: .concurrentBackground) { _ in
                self.operationUnknownCallbackQueue().assert(on: .concurrentBackground)
            }.assert(on: .main).assertValue(4711)
        }
    }
    
    func testOperationUnknownCallackQueueToBackgroundInThen() {
        testFuture(repeatCount: 100) {
            Future(1).flatMap(on: .concurrentBackground) { v in
                Future(v*2).assert(on: .concurrentBackground)
            }.assert(on: .main).assertValue(2)
        }
    }
    
    func testJumpingBetweenThreads() {
        testFuture(repeatCount: 100) {
            return Future(1).assert(on: .main).flatMap(on: .concurrentBackground) { v -> Future<Int> in
                assertConcurrentBackground()
                return Future(v+2).assert(on: .concurrentBackground)
            }.assert(on: .main).flatMap(on: .concurrentBackground) { v -> Future<Int> in
                assertConcurrentBackground()
                return Future(v*2).onValue(on: .main) { _ in
                    assertMain()
                }
            }.assertValue(6).assert(on: .main)
        }
    }

    func testSchedule() {
        testFuture(repeatCount: 0, timeout: 10) { () -> Future<Void> in
            var futures = [Future<Int>]()
            for i in 0...100 {
                var future = Future(4711)
                for _ in 0...i {
                    future = future.map(on: .concurrentBackground) { v -> Int in
                        assertConcurrentBackground()
                        return v+2
                    }
                }
                futures.append(future)
            }
            return join(futures).toVoid().assert(on: .main)
        }
    }
    
    func testImmediate() {
        var i = 0
        testFuture {
            Future<Int>(on: .concurrentBackground) {
                assertConcurrentBackground()
                return i
            }.onValue { _ in i += 1 }.repeatAndCollect(repeatCount: 3).onValue { val in
                assertMain()
                XCTAssertEqual(val, [0, 1, 2, 3])
            }
        }
    }
    
    func testImmediateWithThrow() {
        func f() throws -> Int {
            throw FutureError.aborted
        }
        
        testFuture {
            Future<Int>(on: .concurrentBackground) {
                assertConcurrentBackground()
                return try f()
                }.onResult { result in
                    assertMain()
                    XCTAssertTrue(result.error != nil)
            }
        }
    }
}
