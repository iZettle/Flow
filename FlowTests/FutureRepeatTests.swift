//
//  FutureRepeatTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2015-11-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation
import XCTest

#if DEBUG
@testable import Flow
#else
import Flow
#endif

class FutureRepeatTests: FutureTest {
    func testRepeat() {
        testFuture(repeatCount: 0) { () -> Future<[Int]> in
            var initial = 1
            let initialFuture = Future<Int> { c in
                c(.success(initial));
                initial += 1;
                return NilDisposer()
            }
            
            let f = initialFuture.map { v in
                v * 5
            }
            
            return f.repeatAndCollect(repeatCount: 3).assertValue([1, 2, 3, 4].map { $0*5 })
        }
    }

    func testRepeatCount() {
        testFuture { () -> Future<()> in
            let e = expectation(description: "Sums up")
            var sum1 = 0
            var sum2 = 0
            var sum3 = 0
            return Future { sum1 += 1 }.flatMap {
                Future().onValue { sum2 += 1 }
            }.flatMap { _ -> Future<()>  in
                Future { c in sum3 += 1; c(.success); return NilDisposer() }
            }.repeatAndCollect(repeatCount: 3).onValue { _ in
                XCTAssertEqual(sum1, 4)
                XCTAssertEqual(sum2, 4)
                XCTAssertEqual(sum3, 4)
                e.fulfill()
            }.toVoid()
    }
    }

    func testRepeatCountAlt() {
        testFuture { () -> Future<()> in
            let e = expectation(description: "Sums up")
            var sum1 = 0
            return Future().flatMap {
                Future { c in
                    sum1 += 1;
                    print(sum1);
                    c(.success);
                    return NilDisposer()
                }.map { }
                
                }.repeatAndCollect(repeatCount: 3).onValue { _ in
                    XCTAssertEqual(sum1, 4)
                    e.fulfill()
                }.toVoid()
        }
    }
    
//    func testRepeatCountToCrash() {
//        _ = expectationWithDescription("Sums up")
//        var sum1 = 0
//        Future().flatMap {
//            Future { c in sum1 += 1; print(sum1); c(.success()); return {} }.map { }
//        }.repeatCount(3)
//    }

    func testRepeatCountDelay() {
        testFuture(timeout: 5) { () -> Future<()> in
            let e = expectation(description: "Sums up")
            var sum1 = 0
            var sum2 = 0
            var sum3 = 0
            return Future().delay(by: 0.1).map { sum1 += 1 }.flatMap {
                Future().delay(by: 0.1).onValue { sum2 += 1 }
                }.flatMap { _ -> Future<()>  in
                    Future { c in sum3 += 1; c(.success); return NilDisposer() }.delay(by: 0.1)
                }.repeatAndCollect(repeatCount: 3).onValue { _ in
                    XCTAssertEqual(sum1, 4)
                    XCTAssertEqual(sum2, 4)
                    XCTAssertEqual(sum3, 4)
                    e.fulfill()
                }.toVoid()
        }
    }
    
    func testRepeatCountDelayShort() {
        testFuture(timeout: 5) { () -> Future<()> in
            return Future().delay(by: 0.1).repeatAndCollect(repeatCount: 3).onValue {
                XCTAssertEqual($0.count, 4)
            }.toVoid()
        }
    }
    
    func testRepeatCollect() {
        testFuture(repeatCount: 0) { () -> Future<[Int]> in
            var result = [Int]()
            var initial = 1
            let initialFuture = Future<Int> { c in c(.success(initial)); initial += 1; return NilDisposer() }
            var initial2 = 1
            let f = initialFuture.map { v in v * 2 }.map { v in initial2 += 1; print("initial2", initial2); return v * initial2 }.onValue { result.append($0) }
            
            return f.repeatAndCollect(repeatCount: 3).assertValue([4, 12, 24, 40])
        }
    }
    
    func testRepeatRepeat() {
        testFuture { () -> Future<()> in
            var count = 0
            return Future().onValue { count += 1; print("count", count) }.map { count }.repeatAndCollect(repeatCount: 1).repeatAndCollect(repeatCount: 1).onValue { v in
                XCTAssertEqual(count, 4)
                XCTAssertEqual(v[0], [1, 2])
                XCTAssertEqual(v[1], [3, 4])
            }.toVoid()
        }
    }
    
    
    func testRepeatForeverStackOverflowMain() {
        testFuture(timeout: 2, allDoneDelay: 2, cancelAfterDelay: 0.3) { () -> Future<Int> in
            var cancelResult = 1
            let e = cancelExpectation()
            let f = Future(1).onValue { _ in print("start") }.delay(by: 0.2).onValue { _ in print("delay") }.onCancel {
                print("a"); cancelResult *= 10
                }.onValue { _ in
                    print("m")
                }.delay(by: 0).onValue { _ in
                    print("n")
                }.onCancel {
                    print("b"); cancelResult += 10
                }.onResultRepeat().always {
                    e.fulfill();
                    print("c");
                    XCTAssertEqual(cancelResult, 20)
            }
            
            return f
        }
    }
    
    func testRepeatForeverDelayStackOverflowMainDelay() {
        testFuture(repeatCount: 0, timeout: 2, allDoneDelay: 2, cancelAfterDelay: 0.1) { () -> Future<Int> in
            let f = Future(1).delay(by: 0.01).onResultRepeat()
            return f
        }
    }
    
    // Not sure it we can always catch up?
    // With new immediate repeat handling this one will never come past repeatForever()
    func _testRepeatForeverDelayStackOverflowMain() {
        testFuture(repeatCount: 0, timeout: 2, allDoneDelay: 2, cancelAfterDelay: 0.1) { () -> Future<Int> in
            let f = Future(1).onResultRepeat()
            return f
        }
    }
    
    func testRepeatForeverStackOverflowBackgroundDelay() {
        testFuture(repeatCount: 0, timeout: 2, allDoneDelay: 2, cancelAfterDelay: 0.1) { () -> Future<Int> in
            let f = Future(1).onValue(on: .concurrentBackground) { _ in }.delay(by: 0.01).onResultRepeat()
            return f
        }
    }
    
    // cancel seems to never be able to catch up
    func _testRepeatForeverStackOverflowBackground() {
        testFuture(repeatCount: 0, timeout: 2, allDoneDelay: 20, cancelAfterDelay: 0.1) { () -> Future<Int> in
            let f = Future(1).onValue(on: .concurrentBackground) { _ in }.onResultRepeat()
            return f
        }
    }
    
    func testRepeatStackOverflow() {
        testFuture(timeout: 20, allDoneDelay: 20) { () -> Future<[Int]> in
            Future(1).repeatAndCollect(repeatCount: 1000).assertValue(Array<Int>(repeating: 1, count: 1001))
        }
    }


    func testRepeatOnValueCloning() {
        testFuture { () -> Future<[Int]> in
            var count = 0
            let repeatCount = 10
            return Future(1).onValue { _ in print(count); count += 1 }.repeatAndCollect(repeatCount: repeatCount-1).always { XCTAssertEqual(count, repeatCount) }.assertValue(Array(repeating: 1, count: repeatCount))
        }
    }
    
    func testRepeatInitialScheduled() {
        testFuture(timeout: 5) { () -> Future<[Int]> in
            var count = 0
            let repeatCount = 10
            let f = Future<Int>(on: .concurrentBackground) { c in
                XCTAssertFalse(isMain, "Not on background queue");
                c(.success(1));
                return NilDisposer()
            }
            return f.onValue { _ in
                assertMain()
                print(count);
                count += 1
            }.repeatAndCollect(repeatCount: repeatCount-1).always {
                XCTAssertEqual(count, repeatCount)
            }.assertMain().assertValue(Array(repeating: 1, count: repeatCount))
        }
    }
    
    func testRepeatAll() {
        testFuture(timeout: 1, allDoneDelay: 2) { () -> Future<[(Int, Int)]> in
            var count = 0
            return join(Future(1).delay(by: 0).onValue { _ in
                count += 1
                }, Future(2)).repeatAndCollect(repeatCount: 9).always { XCTAssertEqual(count, 10) }
        }
    }

    func testRepeatAny() {
        testFuture(timeout: 15, allDoneDelay: 2) { () -> Future<[Either<Int, Int>]> in
            var count = 0
            return select(Future(1).onValue { _ in count += 1 }, or: Future(2)).repeatAndCollect(repeatCount: 9).always { XCTAssertEqual(count, 10) }
        }
    }

    
    func testRepeatWithSubFutures() {
        testFuture(timeout: 15, allDoneDelay: 2) { () -> Future<[()]> in
            var count = 0
            return Future(1).delay(by: 0.01).flatMap { _ -> Future<()> in
                Future { c in
                    Future().delay(by: 0.01).onValue { count += 1 }
                    Future().onValue { count += 1 }
                    c(.success)
                    return NilDisposer()
                }
            }.delay(by: 0.01).repeatAndCollect(repeatCount: 9).delay(by: 2).always { XCTAssertEqual(count, 20) }
        }
    }
    
    func testRepeatWithDelay() {
        testFuture(timeout: 5) { () -> Future<()> in
            let e = expectation(description: "Sums up")
            var sum = 0
            return Future().delay(by: 0.1).map { sum += 1 }.repeatAndCollect(repeatCount: 3, delayBetweenRepetitions: 0.1).onValue { _ in
                XCTAssertEqual(sum, 4)
                e.fulfill()
            }.toVoid()
        }
    }

    func testRetryOnError() {
        testFuture(timeout: 5) { () -> Future<()> in
            let e = expectation(description: "Sums up")
            var sum = 0
            return Future(error: TestError.fatal).delay(by: 0.1).onError { _ in
                sum += 1
            }.onErrorRepeat(delayBetweenRepetitions: 0.1, maxRepetitions: 3).onError { _ in
                XCTAssertEqual(sum, 4)
                e.fulfill()
            }
        }
    }

    func testRetryMemoryCleanup() {
        testFuture(timeout: 5) { () -> Future<()> in
            return Future().delay(by: 0.0001).repeatAndCollect(repeatCount: 100).toVoid().onValue {
                print("futureUnitTestAliveCount", futureUnitTestAliveCount)
                XCTAssert(futureUnitTestAliveCount < 25)
            }
        }
    }
    
    func testRepeatAbortExternal() {
        testFuture(timeout: 5) { () -> Future<Int> in
            let internalFuture = Future(5).delay(by: 0.1)
            let externalFuture = internalFuture.onResultRepeat { result -> Bool in
                XCTAssertFalse(true)
                return true
            }
            
            externalFuture.cancel()
            
            return externalFuture.assertError()
        }
    }
}

