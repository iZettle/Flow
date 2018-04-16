//
//  FutureBasicTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2015-09-30.
//  Copyright © 2015 iZettle. All rights reserved.
//

import XCTest
import Flow

extension Future {
    convenience init(_ value: Value, delay: TimeInterval, queue: DispatchQueue = backgroundQueue) {
        self.init { c in
            queue.asyncAfter(deadline: .now() + delay) {
                c(.success(value))
            }
            return NilDisposer()
        }
    }
}

class FutureTest: XCTestCase {
    override func setUp() {
        super.setUp()
        clearAliveCounts()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        
        super.tearDown()
    }
    
    func errorExpectation() -> XCTestExpectation {
        return expectation(description: "Receive error")
    }

    func cancelExpectation() -> XCTestExpectation {
        return expectation(description: "Receive cancel")
    }

}

class FutureBasicTests: FutureTest {
    func testFutureNoListenersSharedDisposeImmedidate() {
        let e = expectation(description: "Disposer")
        let d = Disposer {
            e.fulfill()
        }
        let f = Future<()> { c in
            c(.success)
            return d
        }
        
        waitForExpectations(timeout: 0.01, handler: { _ in
            _ = f
            _ = d
        })
    }

    func testFutureNoListenersSharedDisposeDelayed() {
        let e = expectation(description: "Disposer")
        let d = Disposer {
            e.fulfill()
        }
        let f = Future<()> { c in
            Scheduler.main.async(after: 0.1) {
                c(.success)
            }
            return d
        }
        
        waitForExpectations(timeout: 0.5, handler: { _ in
            _ = f
            _ = d
        })
    }
    
    func testFutureValue() {
        testFuture { Future(4711).onValue { XCTAssertEqual($0, 4711) } }
    }
    
    func testflatMap() {
        testFuture {
            Future(4).map { $0*2 }.assertValue(8)
        }
    }

    func testFutureError() {
        let e = errorExpectation()
        testFuture {
            return Future<Int>(error: TestError.fatal).onValue { _ in XCTAssertFalse(true) }.onError { _ in e.fulfill() }
        }
    }

    func testAllError() {
        let e = errorExpectation()
        testFuture {
            return join([Future<Int>(error: TestError.fatal), Future(4711)]).onValue { _ in XCTAssertFalse(true) }.onError { _ in e.fulfill() }
        }
    }

    func testAnyArray() {
        testFuture {
            return select(between: [Future(1).delay(by: 1), Future(2), Future(3).delay(by: 1)]).assertValue(2)
        }
    }
    
    func testAnyError() {
        let e = errorExpectation()
        testFuture {
            return select(Future<Int>(error: TestError.fatal), or: Future(4711)).onValue { _ in XCTAssertFalse(true) }.onError { _ in e.fulfill() }
        }
    }
    
    func testLastWillDispose() {
        testFuture { () -> Future<()> in
            let e = expectation(description: "Last will dispose")
            let f = Future<()> { c in
                
                c(.success)
                return Disposer(e.fulfill)
            }
            return f
        }
    }

    func testLastWillDisposeAsync() {
        testFuture { () -> Future<()> in
            let e = expectation(description: "Last will dispose")
            let f = Future<()> { c in
                
                mainQueue.async { c(.success) }
                return Disposer(e.fulfill)
            }
            return f
        }
    }
    
    func testMapToFuture() {
        testFuture(timeout: 3) {
            return Array(repeating: 1, count: 10000).mapToFuture { Future($0*2) }.assertValue(Array(repeating: 2, count: 10000))
        }
    }

    func testCancel() {
        testFuture { () -> Future<Int> in
            let e = cancelExpectation()
            let f = Future(1, delay: 0, queue: DispatchQueue.main).onCancel { e.fulfill() }
            f.cancel()
            return f
        }
    }

    func testCancelCancel() {
        testFuture { () -> Future<Int> in
            let e1 = cancelExpectation()
            let e2 = cancelExpectation()
            let f = Future(1, delay: 0, queue: DispatchQueue.main).onCancel { e1.fulfill() }.onCancel { e2.fulfill() }
            f.cancel()
            return f
        }
    }
    
    func testAlwaysIfCancelled() {
        testFuture { () -> Future<Int> in
            let e = cancelExpectation()
            let f = Future(1, delay: 0, queue: DispatchQueue.main).always { e.fulfill() }
            f.cancel()
            return f
        }
    }
    
    func testCancelWithRecursionBreak() {
        testFuture { () -> Future<Int> in
            let e = cancelExpectation()
            let f = Future(1, delay: 0.01, queue: DispatchQueue.main).onCancel {
                e.fulfill()
            }
            f.cancel()
            return f
        }
    }

    func testJoin() {
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(1).delay(by: 0.1)
            let f2 = Future(2)
            return f1.join(with: f2).assertValue((1, 2), isSame: ==)
        }
    }

    func testJoinError() {
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(1).delay(by: 0.1).onValue { _ in throw TestError.fatal }
            let f2 = Future(2)
            return f1.join(with: f2).assertError()
        }
    }

    func testJoinErrorAlt() {
        let e = cancelExpectation()
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(1).delay(by: 0.1).onCancel {
                e.fulfill()
            }
            let f2 = Future(2).onValue { _ in throw TestError.fatal }
            return f1.join(with: f2).assertError()
        }
    }
    
    func testJoinErrorDontCancel() {
        let e = expectation(description: "Complete")
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(1).delay(by: 0.1).onValue { _ in e.fulfill() }
            let f2 = Future(2).onValue { _ in throw TestError.fatal }
            return f1.join(with: f2, cancelNonCompleted: false).assertError().delay(by: 0.3)
        }
    }
    
    func testAllTuple() {
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(1).delay(by: 0.1)
            let f2 = Future(2)
            return join(f1, f2).assertValue((1, 2), isSame: ==)
        }
    }

    func testAllArray() {
        testFuture { () -> Future<[Int]> in
            let f1 = Future(1).delay(by: 0.1)
            let f2 = Future(2)
            return join([f1, f2]).assertValue([1, 2], isSame: ==)
        }
    }

    func testAllKeepOrdering() {
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(1).delay(by: 0.1)
            let f2 = Future(2)
            return join(f1, f2).assertValue((1, 2), isSame: ==)
        }
    }
    
    func _testRecursiveImmediateFlatMap() {
        testFuture(timeout: 1000) { () -> Future<Int> in
            func test(_ val: Int) -> Future<Int> {
                if val > 0 {
                    return Future(val).flatMap { test($0 - 1) }
                } else {
                    return Future(val)
                }
            }
            test(10000).cancel()
            return test(1000)
        }
    }
    
    func _testRecursiveImmediateMap() {
        testFuture(timeout: 1000) { () -> Future<Int> in
            var f = Future(4711).delay(by: 1)
            for _ in 1...100000 {
                f = f.map { $0 + 1 }
            }
            return f.onValue {
                print($0)
            }
        }
    }
    
    func testRecursiveFlatMap() {
        testFuture(timeout: 1000) { () -> Future<Int> in
            func test(_ val: Int) -> Future<Int> {
                if val > 0 {
                    return Future(val).delay(by: 0.01).flatMap { test($0 - 1) }
                } else {
                    return Future(val)
                }
            }
            test(10000).cancel()
            return test(1000)
        }
    }
    
    func testRecursiveMap() {
        testFuture(timeout: 1000) { () -> Future<Int> in
            var f = Future(4711)
            for _ in 1...1000 {
                f = f.map { $0 + 1 }.delay(by: 0.01)
            }
            return f.onValue {
                print($0)
            }
        }
    }
    
    
    func _testRecursiveMapCancel() {
        testFuture(timeout: 1000) { () -> Future<Int> in
            var f = Future(4711).delay(by: 1)
            for _ in 1...10000 {
                f = f.map { $0 + 1 }
            }
            f.cancel()
            return f
        }
    }

    func _testRecursiveFlatMapCancel() {
        testFuture(timeout: 1000) { () -> Future<Int> in
            var f = Future(4711).delay(by: 1)
            for _ in 1...10000 {
                f = f.flatMap { Future($0 + 1).delay(by: 0.0001) }
            }
            Scheduler.main.async(after: 1) {
                f.cancel()
            }
            return f
        }
    }
    
    func testFromBackground() {
        let e = expectation(description: "complete")
        backgroundQueue.async {
            Future(4711).onResult { _ in
                e.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1)
    }
    
    func testImmediate() {
        var i = 0
        testFuture {
            Future { i }.onValue { _ in i += 1 }.repeatAndCollect(repeatCount: 3).onValue { val in
                XCTAssertEqual(val, [0, 1, 2, 3])
            }
        }
    }

    func testImmediateWithThrow() {
        func f() throws -> Int {
            throw FutureError.aborted
        }
        testFuture {
            Future<Int> { try f() }.onResult { result in
                XCTAssertTrue(result.error != nil)
            }
        }
    }
    
    func testContinueBeforeImmediateComplete() {
        testFuture(repeatCount: 100) { () -> Future<Int> in
            let e = expectation(description: "Expect to complete")
            return Future<Int>(on: .concurrentBackground) { c in
                backgroundQueue.async { c(.success(5)) }
                return NilDisposer()
            }.onValue { value in
                XCTAssertEqual(value, 5)
                e.fulfill()
            }
        }
    }

    func testMutipleContinueBeforeImmediateComplete() {
        testFuture(repeatCount: 100) { () -> Future<Int> in
            let e1 = expectation(description: "Expect to complete")
            let e2 = expectation(description: "Expect to complete")
            let future = Future<Int>(on: .concurrentBackground) { c in
                backgroundQueue.async { c(.success(5)) }
                return NilDisposer()
            }
            future.onValue { value in
                XCTAssertEqual(value, 5)
                e1.fulfill()
            }
            return future.onValue { value in
                XCTAssertEqual(value, 5)
                e2.fulfill()
            }
        }
    }
}



