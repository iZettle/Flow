//
//  MultipleContinuationsTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2015-09-30.
//  Copyright © 2015 iZettle. All rights reserved.
//

import XCTest
import Flow


class MultipleContinuationsTests: FutureTest {
    func testMultipleContinuations() {
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(2)

            return join(f1.map { $0*2 }, f1.map { $0 * 3 }).assertValue((4, 6), isSame: ==)
        }
    }

    func testMultipleContinuations2() {
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(2).delay(by: 0.01)
            
            return join(f1.map { $0*2 }, f1.map { $0 * 3 }).assertValue((4, 6), isSame: ==)
        }
    }

    func testMultipleContinuations3() {
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(2)
            
            return join(f1.delay(by: 0.01).map { $0*2 }, f1.map { $0 * 3 }).assertValue((4, 6), isSame: ==)
        }
    }

    func testMultipleContinuations4() {
        testFuture { () -> Future<(Int, Int)> in
            let f = Future(2).delay(by: 0.01)
            let f1 = f.map { $0*2 }
            
            return Future().delay(by: 0.2).flatMap {
                let f2 = f.map { $0 * 3 }
                
                return join(f1, f2).assertValue((4, 6), isSame: ==)
            }
        }
    }
    
    func testMultipleContinuations5() {
        testFuture { () -> Future<(Int, Int)> in
            let f1 = Future(2).delay(by: 0.01).map { $0 + 1 }
            
            return join(f1.delay(by: 0.01).map { $0*2 }, f1.delay(by: 0.01).map { $0 * 3 }).assertValue((6, 9), isSame: ==)
        }
    }
    
    func testCancelingMultipleContinuations() {
        let e = errorExpectation()
        testFuture { () -> Future<(Int, Int)> in
            let f = Future(2)
            let f1 = f.map { $0 * 2 }.delay(by: 0.01)
            let f2 = f.map { $0 * 3 }.delay(by: 0.01)
            f1.cancel()
            return join(f1, f2).onError { _ in e.fulfill() }
        }
    }

    func testCancelingMultipleContinuations2() {
        let c1 = cancelExpectation()
        let c2 = cancelExpectation()
        testFuture { () -> Future<Int> in
            let f = Future(2)
            let f1 = f.map { $0 * 2 }.delay(by: 0.01).onCancel { c1.fulfill() }
            let f2 = f.map { $0 * 3 }.delay(by: 0.01).onCancel { c2.fulfill() }
            let a = join(f1, f2)
            a.cancel()
            return a.mapResult { _ in 4711 }
        }
    }
    
    func testCancelingMultipleContinuations3() {
        let v = expectation(description: "Receive value")
        testFuture { () -> Future<(Int, Int)> in
            let f = Future(2)
            let f1 = f.map { $0 * 2 }.delay(by: 0.01)
            let f2 = f.map { $0 * 3 }.delay(by: 0.01)
            f1.onValue { _ in v.fulfill() }
            return join(f1, f2).assertValue((4, 6), isSame: ==)
        }
    }

    func testCancelingMultipleContinuations4() {
        let v = cancelExpectation()
        testFuture { () -> Future<Int> in
            let f = Future(2).delay(by: 0.01)
            let f1 = f.map { $0 * 2 }.delay(by: 0.01).onCancel { v.fulfill() }
            let f2 = f.map { $0 * 3 }
            f.cancel()
            f1.cancel()
            return f2.assertValue(6)
        }
    }

    func testCancelingMultipleContinuations5_a() {
        testFuture(timeout: 5) { () -> Future<Int> in
            let f = Future(2)
            let f1 = f.map { $0 * 2 }.delay(by: 0.01)
            let f3 = f1.map { $0 * 3 }
            let a = f1.assertValue(4)
            f3.cancel()
            return a
        }
    }
    
    func testCancelingMultipleContinuations5_b() {
        testFuture(repeatCount: 100) { () -> Future<Int> in
            let v = cancelExpectation()
            let f = Future(2)
            let f1 = f.map { $0 * 2 }.delay(by: 0.01)
            let f3 = f1.onCancel { v.fulfill() }
            let a = f1.assertValue(4)
            f3.cancel()
            return a
        }
    }
    
    func testCancelingMultipleContinuations6() {
        testFuture(repeatCount: 100) { () -> Future<(Int, Int)> in
            let v = cancelExpectation()
            let f = Future(2)
            let f1 = f.map(on: .concurrentBackground) { $0 * 2 }.delay(by: 0.01)
            let f2 = f.map(on: .concurrentBackground) { $0 * 3 }.delay(by: 0.01)
            let f3 = f1.onCancel { v.fulfill() }
            let a = join(f1, f2).assertValue((4, 6), isSame: ==)
            f3.cancel()
            return a
        }
    }
    
    func testCancelingMultipleContinuations6_() {
        testFuture(repeatCount: 100) { () -> Future<Int> in
            let f1 = Future(2)
            let f3 = f1.map(on: .concurrentBackground) { $0 }
            let a = f1.assertNoError()
            f3.cancel()
            return a
        }
    }
    
    func testMultipleContinuationsAndRepeat() {
        testFuture(repeatCount: 100) { () -> Future<(Int, Int)> in
            let v = cancelExpectation()
            var count = 0
            let f = Future(2).onValue { _ in count += 1 }.repeatAndCollect(repeatCount: 4).map { $0[0] }
            let f1 = f.map { $0 * 2 }.delay(by: 0.01)
            let f2 = f.map { $0 * 3 }.delay(by: 0.01)
            let f3 = f1.onCancel { v.fulfill() }
            let a = join(f1, f2).assertValue((4, 6), isSame: ==).onValue { _ in
                XCTAssertEqual(count, 5)
            }
  
            f3.cancel()

            return a
        }
    }
    
    func testMultipleContinuationsAndRepeat2() {
        testFuture(timeout: 5) { () -> Future<(Int, Int)> in
            var count = 0
            let f = Future(2).delay(by: 0.01).onValue { _ in count += 1; print(count) }.repeatAndCollect(repeatCount: 4).map { $0[0] }.onValue { _ in print("f") }
            let f1 = f.map { $0 * 2; }.delay(by: 0.01).onValue { v in print("f1", v) }
            let f2 = f.map { $0 * 3 }.delay(by: 0.01).onValue { _ in print("f2") }
            return join(f1, f2).onValue { t1, t2 in print(t1, t2) }.assertValue((4, 6), isSame: ==).onValue { _ in
                XCTAssertEqual(count, 5)
            }
        }
    }

    func testMultipleContinuationsAndRepeat3() {
        let v = cancelExpectation()
        testFuture(timeout: 5) { () -> Future<(Int, Int)> in
            var count = 0
            let f = Future(2).delay(by: 0.01).onValue { _ in count += 1; }.repeatAndCollect(repeatCount: 4).map { $0[0] }
            let f1 = f.map { $0 * 2 }.delay(by: 0.01)
            let f2 = f.map { $0 * 3 }.delay(by: 0.01)
            let f3 = f1.onCancel { v.fulfill(); print("was cancelled") }
            let a = join(f1, f2).assertValue((4, 6), isSame: ==).onValue { _ in
                XCTAssertEqual(count, 5)
            }
            f3.cancel()
            return a.delay(by: 0.03)
        }
    }

    func testMultipleContinuationsAndRepeat4() {
        testFuture(timeout: 5) { () -> Future<(Int, Int)> in
            var count1 = 0
            var count2 = 0
            var count3 = 0
            let f = Future(2).delay(by: 0.01).onValue { _ in count1 += 1; print(count1, count2, count3) }.repeatAndCollect(repeatCount: 4).map { $0[0] }
            let f1 = f.map { $0 * 2 }.delay(by: 0.01).onValue { _ in count2 += 1; print("count2", count2) }.repeatAndCollect(repeatCount: 2).map { $0[0] }
            let f2 = f.map { $0 * 3 }.delay(by: 0.01).onValue { _ in count3 += 1; print("count3", count3) }.repeatAndCollect(repeatCount: 3).map { $0[0] }
            let a = join(f1, f2).assertValue((4, 6), isSame: ==).onValue { _ in
                XCTAssertEqual(count2, 3)
                XCTAssertEqual(count3, 4)
                XCTAssertEqual(count1, 5 + 5*2 + 5*3)
            }
            return a.delay(by: 0.03)
        }
    }
    
    func testMultipleContinuationsAndRepeat5() {
        let v = cancelExpectation()
        testFuture(timeout: 5) { () -> Future<(Int, Int)> in
            var count1 = 0
            var count2 = 0
            var count3 = 0
            let f = Future(2).delay(by: 0.01).onValue { _ in count1 += 1; print(count1, count2, count3) }.repeatAndCollect(repeatCount: 4).map { $0[0] }
            let f1 = f.map { $0 * 2 }.delay(by: 0.01).onValue { _ in count2 += 1; print("count2", count2) }.repeatAndCollect(repeatCount: 2).map { $0[0] }
            let f2 = f.map { $0 * 3 }.delay(by: 0.01).onValue { _ in count3 += 1; print("count3", count3) }.repeatAndCollect(repeatCount: 3).map { $0[0] }
            let f3 = f1.onCancel { v.fulfill(); print("was cancelled") }
            let a = join(f1, f2).assertValue((4, 6), isSame: ==).onValue { _ in
                XCTAssertEqual(count2, 3)
                XCTAssertEqual(count3, 4)
                XCTAssertEqual(count1, 5 + 5*2 + 5*3)
            }
            f3.cancel()
            return a.delay(by: 0.03)
        }
    }
}



