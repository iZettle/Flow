//
//  FutureUtilitiesTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2016-02-10.
//  Copyright © 2016 iZettle. All rights reserved.
//

import XCTest
import Flow

class SingleTaskPerformerTests: FutureTest {
    func testPerformOneAtTimeSame() {
        testFuture(repeatCount: 100, allDoneDelay: 1) {  () -> Future<Int> in
            let oneAtTheTime = SingleTaskPerformer<Int>()
            oneAtTheTime.performSingleTask {
                Future(4711).delay(by: 1)
            }.assertValue(4711)
            
            return oneAtTheTime.performSingleTask {
                Future(4712).delay(by: 0.1)
            }.assertValue(4711)
        }
    }
    
    func testPerformOneAtTimeSameImmediate() {
        testFuture(repeatCount: 100, allDoneDelay: 1) {  () -> Future<Int> in
            let oneAtTheTime = SingleTaskPerformer<Int>()
            oneAtTheTime.performSingleTask {
                Future(4711)
            }.assertValue(4711)
            
            return oneAtTheTime.performSingleTask {
                Future(4712)
            }.assertValue(4712)
        }
    }
    
    func testPerformOneAtTimeNew() {
        testFuture(repeatCount: 100, timeout: 4, allDoneDelay: 1) {  () -> Future<Int> in
            let oneAtTheTime = SingleTaskPerformer<Int>()
            oneAtTheTime.performSingleTask {
                Future(4711).delay(by: 0.1)
            }.assertValue(4711)
            
            return Future().delay(by: 0.5).flatMap {
                oneAtTheTime.performSingleTask {
                    Future(4712).delay(by: 0.1)
                }.assertValue(4712)
            }
        }
    }
    
    func testPerformOneAtTimeCancel() {
        testFuture(repeatCount: 100, allDoneDelay: 1) {  () -> Future<Int> in
            let oneAtTheTime = SingleTaskPerformer<Int>()
            let f = oneAtTheTime.performSingleTask {
                Future(4711).delay(by: 1)
            }
            
            f.cancel()
            
            return oneAtTheTime.performSingleTask {
                Future(4712).delay(by: 0.1)
            }.assertValue(4712)
        }
    }
    
    func testPerformOneAtTimeCancelAlt2() {
        testFuture(repeatCount: 100, allDoneDelay: 1) {  () -> Future<Int> in
            let oneAtTheTime = SingleTaskPerformer<Int>()
            let f1 = oneAtTheTime.performSingleTask {
                Future(4711).delay(by: 1)
            }
            
            oneAtTheTime.performSingleTask {
                Future(4712).delay(by: 0.1)
            }
            
            f1.cancel()
            
            return oneAtTheTime.performSingleTask {
                Future(4713).delay(by: 0.1)
            }.assertValue(4711)
        }
    }
}



class FutureUtilitiesTests: FutureTest {
    func testReplaceWithResult() {
        let e = expectation(description: "value")
        testFuture(timeout: 1) {
            Future(8).delay(by: 100000).replace(with: .success(4711), after: 0.5).onValue { val in
                XCTAssertEqual(val, 4711)
                e.fulfill()
            }
        }
    }
    
    func testReplaceWithResultNoTimeout() {
        let e = expectation(description: "value")
        testFuture(timeout: 1) {
            Future(8).delay(by: 0.5).replace(with: .success(4711), after: 1000).onValue { val in
                XCTAssertEqual(val, 8)
                e.fulfill()
            }
        }
    }
    
    func testFailAfterTimeout() {
        let e = errorExpectation()
        testFuture(timeout: 1) {
            Future().delay(by: 100000).fail(with: TestError.fatal, after: 0.5).onError { _ in
                e.fulfill()
            }
        }
    }
    
    func testRetryMaxRetrials() {
        let e = errorExpectation()
        var count = 0
        testFuture(timeout: 1) {
            Future().onValue {
                count += 1
            }.onResultRepeat(maxRepetitions: 4).onValue { _ in
                XCTAssertEqual(count, 5)
                e.fulfill()
            }
        }
    }
    

    func testAbortForFuturesSuccess() {
        let e = errorExpectation()
        testFuture(timeout: 1) {
            Future(4711).delay(by: 0.1).abort(forFutures: [ Future().delay(by: 10) ]).onValue { val in
                XCTAssertEqual(val, 4711)
                e.fulfill()
            }
        }
    }

    func testAbortForFuturesFailure() {
        let e = errorExpectation()
        testFuture(timeout: 1) {
            Future().delay(by: 10).abort(forFutures: [ Future().delay(by: 0.1) ]).onError { error in
                XCTAssert(error is FutureError)
                e.fulfill()
            }
        }
    }

    func testIgnoreAbort() {
        testFuture(timeout: 1, cancelAfterDelay: 0.1) { () -> Future<Int> in
            let e = errorExpectation()
            
            let future = Future(5).delay(by: 0.2).onValue { _ in
                e.fulfill() // Should not be aborted
            }
            return future.ignoreCanceling().onResult {
                XCTAssertNotNil($0.error)
            }
        }
    }

    func testHoldUntil() {
        testFuture(timeout: 1, cancelAfterDelay: 0.1) { () -> Future<Int> in
            let signal = ReadWriteSignal(true)
            
            var count = 0
            var result = 0
            Future(1).hold(until: signal).onValue { count += 1; result += $0 }
            XCTAssertEqual(count, 1)
            XCTAssertEqual(result, 1)

            signal.value = false

            let f = Future(10).hold(until: signal).onValue { count += 10; result += $0 }
            XCTAssertEqual(count, 1)
            XCTAssertEqual(result, 1)

            signal.value = true
            XCTAssertEqual(count, 11)
            XCTAssertEqual(result, 11)

            return f
        }
    }
    
    
    func testPeformWhileImmediate() {
        testFuture { () -> Future<()> in
            var result = 0
            let future = Future().performWhile {
                result += 1
                return Disposer {
                    result += 10
                }
            }
            
            XCTAssertEqual(result, 11)
            return future
        }
    }

    func testPeformWhile() {
        testFuture { () -> Future<()> in
            var result = 0
            let future = Future().delay(by: 0.1).performWhile() {
                result += 1
                return Disposer {
                    result += 10
                }
            }
            
            return future.assertValue().onValue {
                XCTAssertEqual(result, 11)
            }
        }
    }
    
    
    func testPeformWhileDelay() {
        testFuture { () -> Future<()> in
            var result = 0
            let future = Future().delay(by: 0.2).performWhile(delayBy: 0.1) {
                result += 1
                return Disposer {
                    result += 10
                }
            }
            
            return future.assertValue().onValue {
                XCTAssertEqual(result, 11)
            }
        }
    }

    func testPeformWhileDelayNeverStart() {
        testFuture { () -> Future<()> in
            var result = 0
            let future = Future().delay(by: 0.1).performWhile(delayBy: 0.2) {
                result += 1
                return Disposer {
                    result += 10
                }
            }
            
            return future.assertValue().onValue {
                XCTAssertEqual(result, 0)
            }
        }
    }
    
    func testPeformWhileRepeat() {
        testFuture { () -> Future<()> in
            var result = 0
            let future = Future().performWhile {
                result += 1
                return Disposer {
                    result += 10
                }
            }.repeatAndCollect(repeatCount: 4).toVoid()
            
            XCTAssertEqual(result, 55)
            return future
        }
    }
}

