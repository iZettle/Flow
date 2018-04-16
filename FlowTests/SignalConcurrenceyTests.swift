//
//  SignalConcurrenceyTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2017-12-11.
//  Copyright © 2017 iZettle. All rights reserved.
//

import XCTest
import Flow


private extension Scheduler {
    static let serialBackground = Scheduler(label: "flow.background")
}

private func assertSerialBackground() {
    XCTAssertTrue(Scheduler.serialBackground.isExecuting, "Not on serialBackground")
}


class SignalConcurrenceyTests: XCTestCase {
    func testSchedulingSignalCreation() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")

        let callbacker = Callbacker<Event<Int>>()
        bag += FiniteSignal<Int>(callbacker: callbacker).map { val -> Int in
            assertMain()
            return val * 2
        }.collect().onValue { vals in
            assertMain()
            XCTAssertEqual(vals, [2, 4, 6])
            e.fulfill()
        }
        
        callbacker.callAll(with: .value(1))
        
        backgroundQueue.async {
            callbacker.callAll(with: .value(2))
            mainQueue.async {
                callbacker.callAll(with: .value(3))
                callbacker.callAll(with: .end)
            }
        }
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
    func testSchedulingReadWriteSignalCurrent() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")
        
        let p = ReadWriteSignal(1)
        var vals = [Int]()
        bag += p.map { val -> Int in
            assertMain()
            return val * 2
        }.onValue { val in
            assertMain()
            vals.append(val)
        }
        
        XCTAssertEqual(p.value, 1)
        
        p.value = 2

        XCTAssertEqual(p.value, 2)

        backgroundQueue.async {
            XCTAssertEqual(p.value, 2)
            p.value = 3
            XCTAssertEqual(p.value, 3)
            mainQueue.async {
                XCTAssertEqual(p.value, 3)
                p.value = 4
                XCTAssertEqual(p.value, 4)
                XCTAssertEqual(vals, [4, 6, 8])
                e.fulfill()
            }
        }
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
    func testSchedulingReadSignalCurrentAndAtOnce() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")
        
        let rw = ReadWriteSignal(1)
        var vals = [Int]()
        let r = rw.map { val in
            val * 2 // As atOnce() will call this immediately it might not always be called from main.
        }.atValue { _ in
            assertMain()
        }
        
        XCTAssertEqual(r.value, 2)
        
        bag += r.atOnce().onValue { val in
            assertMain()
            vals.append(val)
        }
        
        XCTAssertEqual(vals, [2])
        
        rw.value = 2
        
        XCTAssertEqual(r.value, 4)
        
        backgroundQueue.async {
            XCTAssertEqual(r.value, 4)
            rw.value = 3
            XCTAssertEqual(r.value, 6)
            mainQueue.async {
                XCTAssertEqual(r.value, 6)
                rw.value = 4
                XCTAssertEqual(r.value, 8)
                XCTAssertEqual(vals, [2, 4, 6, 8])
                e.fulfill()
            }
        }
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
    func testSchedulingCombineLatest() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")
        
        let rw1 = ReadWriteSignal(1)
        let rw2 = ReadWriteSignal(10)
        var vals = [Int]()
        bag += combineLatest(rw1, rw2).map { v1, v2 -> Int in
            assertMain()
            return v1 + v2
        }.onValue { val in
            assertMain()
            vals.append(val)
        }
        
        
        rw1.value = 2
        
        backgroundQueue.async {
            rw2.value = 20
            rw1.value = 3
            mainQueue.async {
                rw2.value = 30
                XCTAssertEqual(vals, [12, 22, 23, 33])
                e.fulfill()
            }
        }
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
    func testSchedulingOnValueBackground() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")
        
        backgroundQueue.async {
            // create signal on background
            let callbacker = Callbacker<Int>()
            let signal = Signal(callbacker: callbacker)
            
            mainQueue.sync {
                // but listen on main
                bag += signal.onValue { val in
                    XCTAssert(Thread.isMainThread)
                    XCTAssertEqual(val, 4711)
                    e.fulfill()
                }
            }
            callbacker.callAll(with: 4711)
        }
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    func testSchedulingMapBackground() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")
        
        backgroundQueue.async {
            // create signal on background
            let callbacker = Callbacker<Int>()
            let signal = Signal(callbacker: callbacker)
            
            mainQueue.sync {
                // but listen on main
                bag += signal.map { val -> Int in
                    XCTAssert(Thread.isMainThread)
                    return val + 1
                }.onValue { val in
                    XCTAssert(Thread.isMainThread)
                    XCTAssertEqual(val, 4712)
                    e.fulfill()
                }
            }
            callbacker.callAll(with: 4711)
        }
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
    func testSchedulingOnEventBackground() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")
        
        backgroundQueue.async {
            // create signal on background
            let callbacker = Callbacker<Event<Int>>()
            let signal = FiniteSignal(callbacker: callbacker)
            
            mainQueue.sync {
                // but listen on main
                bag += signal.onEvent { event in
                    XCTAssert(Thread.isMainThread)
                    XCTAssertEqual(event.value, 4711)
                    e.fulfill()
                }
            }
            callbacker.callAll(with: .value(4711))
        }
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
    func testMapOn() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")

        let callbacker = Callbacker<Int>()
        let signal = Signal(callbacker: callbacker)
        bag += signal.map(on: .serialBackground) { val -> Int in
            assertSerialBackground()
            return val * 2
        }.map { val -> Int in
            assertMain()
            return val + 1
        }.onValue { val in
            assertMain()
            XCTAssertEqual(val, 5*2+1)
            e.fulfill()
        }
        
        callbacker.callAll(with: 5)
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
    func testOnValueOn() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")
        
        let callbacker = Callbacker<Int>()
        let signal = Signal(callbacker: callbacker)
        bag += signal.map(on: .serialBackground) { val -> Int in
            assertSerialBackground()
            return val * 2
        }.map { val -> Int in
            assertMain()
            return val + 1
        }.onValue(on: .serialBackground) { val in
            assertSerialBackground()
            XCTAssertEqual(val, 5*2+1)
            e.fulfill()
        }
        
        callbacker.callAll(with: 5)
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
    func testAtOnce() {
        let bag = DisposeBag()
        let rw = ReadWriteSignal(7)
        var result = 0
        
        bag += rw.map(on: .serialBackground) { val -> Int in
            assertSerialBackground()
            return val * 2
        }.map { val -> Int in
            assertMain()
            return val + 1
        }.atOnce().onValue { val in
            result = val
            assertMain()
        }

        XCTAssertEqual(result, 7*2 + 1)
    }
    
    func testCurrentValue() {
        let signal = ReadWriteSignal(7).map(on: .serialBackground) { val -> Int in
            assertSerialBackground()
            return val * 2
        }.map { val -> Int in
            assertMain()
            return val + 1
        }.map(on: .serialBackground) { val -> Int in
            assertSerialBackground()
            return val * 2
        }
        
        XCTAssertEqual(signal.value, (7*2 + 1)*2)
    }

    func testAtOnceBackground() {
        let bag = DisposeBag()
        let e = expectation(description: "completed")

        let rw = ReadWriteSignal(7)
        var result = 0
        
        Scheduler.serialBackground.async {
            assertSerialBackground()
            bag += rw.map(on: .main) { val -> Int in
                assertMain()
                return val * 2
            }.map { val -> Int in
                assertSerialBackground()
                return val + 1
            }.atOnce().onValue { val in
                result = val
                assertSerialBackground()
            }
            XCTAssertEqual(result, 7*2 + 1)
            e.fulfill()
        }
        
        waitForExpectations(timeout: 100) { _ in
            bag.dispose()
        }
    }
    
}
