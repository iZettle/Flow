
//
//  SignalProviderTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 15/03/16.
//  Copyright © 2016 iZettle. All rights reserved.
//

import XCTest
#if DEBUG
@testable import Flow
#else
import Flow
#endif
import Foundation


class TickTrigger: SignalProvider {
    public typealias Value = Date
    
    var timer: Timer?
    let delay: TimeInterval
    let callbacker = Callbacker<Date>()
    
    public init(delay: TimeInterval) {
        self.delay = delay
        self.timer = Timer(timeInterval: delay, target: self, selector: #selector(TickTrigger.fire), userInfo: nil, repeats: true)
    }
    
    @objc func fire() -> Void {
        callbacker.callAll(with: Date())
    }
    
    var providedSignal: Signal<Date> {
        return Signal(callbacker: callbacker)
    }
    
    func start() {
        if let timer = self.timer {
            RunLoop.main.add(timer, forMode: RunLoopMode.defaultRunLoopMode)
        }
    }
    
    func invalidate() {
        if let timer = self.timer {
            timer.invalidate()
        }
        
        self.timer = nil
    }
}

struct SignalError: Error {}

class SignalProviderTests: XCTestCase {
    func testEventTrigger() {
        let bag = DisposeBag()
        let tick = TickTrigger(delay: 0.1)
        var numberOfTicks = 0
        let expectation = self.expectation(description: "Counted to three")

        bag += tick.onFirstValue { time in
            //XCTAssertTrue(time.isKind(of: Date.self))
        }

        bag += tick.onValue { time in
            //XCTAssertTrue(time.isKind(of: Date.self))
            numberOfTicks += 1
            
            if numberOfTicks == 3 {
                expectation.fulfill()
            }
        }
        
        tick.start()
        
        waitForExpectations(timeout: 10) { _ in
            tick.invalidate()
            bag.dispose()
        }
    }
    
    fileprivate func test<I, O: Equatable>(_ input: [I], expected: [O], transform: (FiniteSignal<I>) -> FiniteSignal<O>) {
        var result = [O]()
        _ = transform(input.signal()).collect().onValue { result = $0 }
        XCTAssertEqual(result, expected)
    }

    fileprivate func test<I, O>(_ input: [I], expected: [O], isEquivalent: (O, O) -> Bool, transform: (FiniteSignal<I>) -> FiniteSignal<O>) {
        var result = [O]()
        _ = transform(input.signal()).collect().onValue { result = $0 }
        XCTAssert(result.elementsEqual(expected, by: isEquivalent))
    }
    
    fileprivate func testAsync<I, O: Equatable>(_ input: [I], expected: [O], transform: (FiniteSignal<I>) -> FiniteSignal<O>) {
        runTest(timeout: 1) { bag in
            let e = expectation(description: "complete")
            bag += transform(input.signal()).collect().onValue {
                XCTAssertEqual($0, expected)
                e.fulfill()
            }
        }
    }
    
    fileprivate func testAsync<I, O>(_ input: [I], expected: [O], isEquivalent: @escaping (O, O) -> Bool, transform: (FiniteSignal<I>) -> FiniteSignal<O>) {
        runTest(timeout: 1) { bag in
            let e = expectation(description: "complete")
            bag += transform(input.signal()).collect().onValue {
                XCTAssert($0.elementsEqual(expected, by: isEquivalent))
                e.fulfill()
            }
        }
    }

    func testOnFirstValue() {
        var buffer = [Int]()
        let bag = DisposeBag()
        bag += [1, 2, 3, 4].signal().onFirstValue {
            buffer.append($0)
        }
        XCTAssertEqual(buffer, [1])

        buffer = []
        bag += [1, 2, 3, 4].signal().start(with: 0).onFirstValue { buffer.append($0) }
        XCTAssertEqual(buffer, [0])
    }

    func testBuffer() {
        test([1, 2, 3], expected: [[1], [1, 2], [1, 2, 3]], isEquivalent: { (lhs: [Int], rhs: [Int]) -> Bool in
            lhs.elementsEqual(rhs)
        }) {
            $0.buffer()
        }
    }

    func testJust() {
        var r = 0
        _ = Signal(just: 5).onValue { r += $0 }
        XCTAssertEqual(r, 5)
    }

    func testTake() {
        test([1, 2, 3, 4], expected: []) {
            $0.take(first: 0)
        }
        test([1, 2, 3, 4], expected: [1, 2]) {
            $0.take(first: 2)
        }
        test([1, 2, 3, 4], expected: [1, 2, 3, 4]) {
            $0.take(first: 4)
        }
        test([1, 2, 3, 4], expected: [1, 2, 3, 4]) {
            $0.take(first: 6)
        }
    }

    func testTakeWhile() {
        test([1, 2, 3, 4], expected: []) {
            $0.take { $0 < 0 }
        }
        test([1, 2, 3, 4], expected: [1, 2]) {
            $0.take { $0 < 3 }
        }
        test([1, 2, 3, 4], expected: [1, 2, 3, 4]) {
            $0.take { $0 < 5 }
        }
        test([1, 2, 3, 4], expected: [1, 2, 3, 4]) {
            $0.take { $0 < 7 }
        }
    }
    
    func testRecursiveTakeRecursiveSource() {
        let callbacker = Callbacker<Int>()
        
        var result = [Int]()
        let bag = DisposeBag()
        bag += Signal(callbacker: callbacker).take(first: 4).onValue { v in
            result.append(v)
            callbacker.callAll(with: v + 1)
        }
        
        callbacker.callAll(with: 1)
        
        XCTAssertEqual(result, [1, 2, 3, 4])
    }

    func testRecursiveTakeNoRecursiveSource() {
        let callbacker = Callbacker<Int>()
        
        var result = [Int]()
        let bag = DisposeBag()
        // Make no recursive
        bag += Signal(callbacker: callbacker).take(first: 4).onValue { v in
            result.append(v)
            callbacker.callAll(with: v + 1)
        }
        
        callbacker.callAll(with: 1)
        
        XCTAssertEqual(result, [1, 2, 3, 4])
    }

    final class Obj {
        deinit {
            print("Obj deinit")
        }
    }

    func testNoEndNoRelease() {
        runTest(timeout: 1) { bag in
            weak var weakObj1: Obj?
            weak var weakObj2: Obj?
            
            let callbacker = Callbacker<Int>()
            let e = expectation(description: "once")
            
            do {
                let obj1 = Obj()
                let obj2 = Obj()
                weakObj1 = obj1
                weakObj2 = obj2
                
                bag += Signal(callbacker: callbacker).map {
                    _ = obj1
                    return $0*5
                    }.onValue { (val: Int) in
                        XCTAssertEqual(val, 10)
                        _ = obj2
                        e.fulfill()
                }
            }
            
            callbacker.callAll(with: 2)
            
            XCTAssertNotNil(weakObj1)
            XCTAssertNotNil(weakObj2)
        }
    }
    
    func testOnFirstValueRelease() {
        runTest(timeout: 1) { bag in
            weak var weakObj1: Obj?
            weak var weakObj2: Obj?
            
            let bag = DisposeBag()
            
            let callbacker = Callbacker<Int>()
            let e = expectation(description: "once")
            
            do {
                let obj1 = Obj()
                let obj2 = Obj()
                weakObj1 = obj1
                weakObj2 = obj2
                
                bag += Signal(callbacker: callbacker).map {
                    _ = obj1
                    return $0*5
                    }.onFirstValue { (val: Int) in
                        XCTAssertEqual(val, 10)
                        _ = obj2
                        e.fulfill()
                }
            }
            
            callbacker.callAll(with: 2)
            
            XCTAssertNil(weakObj1)
            XCTAssertNil(weakObj2)
        }
    }
    
    func testEndRelease() {
        weak var weakObj1: Obj?
        weak var weakObj2: Obj?

        let bag = DisposeBag()

        do {
            let obj1 = Obj()
            let obj2 = Obj()
            weakObj1 = obj1
            weakObj2 = obj2

            bag += FiniteSignal<Int>(onEvent: { c in
                _ = obj1
                c(.end)
                return NilDisposer()
            }).onValue { val in
                _ = obj2
                XCTAssertTrue(false)
            }
        }
        
        XCTAssertNil(weakObj1)
        XCTAssertNil(weakObj2)

        bag.dispose()
    }
    
    func testTakeRelease() {
        weak var weakObj1: Obj?
        weak var weakObj2: Obj?
        
        let bag = DisposeBag()

        do {
            let obj1 = Obj()
            let obj2 = Obj()
            weakObj1 = obj1
            weakObj2 = obj2

            bag += [1, 2, 3, 4].signal().atValue { _ in
                _ = obj1
            }.take(first: 2).collect().onValue { vals in
                _ = obj2
                XCTAssertEqual(vals, [1, 2])
            }
        }
        
        XCTAssertNil(weakObj1)
        XCTAssertNil(weakObj2)
        
        bag.dispose()
    }
    
    func testSkip() {
        test([1, 2, 3, 4], expected: [1, 2, 3, 4]) {
            $0.skip(first: 0)
        }
        test([1, 2, 3, 4], expected: [2, 3, 4]) {
            $0.skip(first: 1)
        }
        test([1, 2, 3, 4], expected: [3, 4]) {
            $0.skip(first: 2)
        }
    }
    
    func testReduce() {
        test([1, 2, 3, 4], expected: [1, 3, 6, 10]) {
            $0.reduce(0, combine: +)
        }
    }
    
    func testEnumerate() {
        test([1, 2, 3, 4], expected: [(0, 1), (1, 2), (2, 3), (3, 4)], isEquivalent: ==) {
            $0.enumerate()
        }
    }


    func testLatestTwo() {
        test([1, 2, 3, 4], expected: [(1, 2), (2, 3), (3, 4)], isEquivalent: ==) {
            $0.latestTwo()
        }
    }

    func testLatestTwoNoSource() {
        let p = ReadWriteSignal(0)
        var r = [(Int, Int)]()
        let bag = DisposeBag()
        bag += p.plain().latestTwo().onValue { r.append($0) }
        
        p.value = 1
        p.value = 2
        p.value = 3
        
        XCTAssert(r.elementsEqual([(1, 2), (2, 3)], by: ==))
    }
    
    func testLatestTwoHasSource() {
        let p = ReadWriteSignal(0)
        var r = [(Int, Int)]()
        let bag = DisposeBag()
        bag += p.latestTwo().onValue { r.append($0) }
        
        p.value = 1
        p.value = 2
        p.value = 3
        
        XCTAssert(r.elementsEqual([(0, 1), (1, 2), (2, 3)], by: ==))

    }

    func testDistinct() {
        test([1, 2, 3, 3, 3, 3, 4, 5], expected: [1, 2, 3, 4, 5]) {
            $0.distinct()
        }
    }
    
    func testThrowingMap() {
        test([1, 2, 3, 4, 5, 6, 7, 8], expected: [2, 4, 6]) {
            $0.map { v in
                guard v < 4 else { throw SignalError() }
                return v*2
            }
        }
    }
    
    func testDistinctWithPredicate() {
        test(["a", "b", "abc", "bcd", "cde", "abcd"], expected: ["a", "abc", "abcd"]) {
            $0.distinct { v, u in
                return v.count == u.count
            }
        }
    }

    func testMerging() {
        runTest(timeout: 10) { bag in
            let odds = [1, 3, 5]
            let evens = [2, 4, 6]
            var buffer = [Int]()
            let expectation = self.expectation(description: "Values were properly merged")
            
            let signal = merge(odds.signal(), evens.signal())
            
            bag += signal.onValue { v in
                buffer.append(v)
                
                if Set(buffer) == Set(odds + evens) {
                    expectation.fulfill()
                }
            }
        }
    }
    
    func testMergeWithStartWith() {
        func testCombineLatestWithUsingSourceAndStartWith() {
            var r = 0
            _ = merge(Signal<Int>(), Signal<Int>()).start(with: 7).onValue { r += $0 }
            XCTAssertEqual(r, 7)
        }
    }
    
    func testCombineLatestWith() {
        runTest(timeout: 10) { bag in
            let a = ReadWriteSignal<String>("")
            let b = ReadWriteSignal<Int>(0)
            
            let expected = [("b", 1), ("c", 1), ("c", 2)]
            var buffer = [(String, Int)]()
            
            let expectation = self.expectation(description: "Values should be combined in order")
            
            let bag = DisposeBag()
            
            let signal = combineLatest(a.plain(), b.plain())
            
            bag += signal.onValue { v in
                buffer.append(v)
                
                if buffer.count == expected.count {
                    var equal = true
                    for (index, element) in expected.enumerated() {
                        let t = buffer[index]
                        if t.0 != element.0 {
                            equal = false
                        }
                    }
                    
                    if equal { expectation.fulfill() }
                }
            }
            
            a.value = "a"
            a.value = "b"
            b.value = 1
            a.value = "c"
            b.value = 2
        }
    }
    
    func testCombineLatestWithUsingSource() {
        runTest(timeout: 10) { bag in
            let a = ReadWriteSignal<String>("")
            let b = ReadWriteSignal<Int>(0)
            
            let expected = [("a", 0), ("b", 0), ("b", 1), ("c", 1), ("c", 2)]
            var buffer = [(String, Int)]()
            
            let expectation = self.expectation(description: "Values should be combined in order")
            
            let bag = DisposeBag()
            
            let signal = combineLatest(a, b)
            
            bag += signal.onValue { v in
                buffer.append(v)
                
                if buffer.count == expected.count {
                    var equal = true
                    for (index, element) in expected.enumerated() {
                        let t = buffer[index]
                        if t.0 != element.0 {
                            equal = false
                        }
                    }
                    
                    if equal { expectation.fulfill() }
                }
            }
            
            a.value = "a"
            XCTAssertTrue(signal.value == expected[0])
            a.value = "b"
            XCTAssertTrue(signal.value == expected[1])
            b.value = 1
            XCTAssertTrue(signal.value == expected[2])
            a.value = "c"
            XCTAssertTrue(signal.value == expected[3])
            b.value = 2
            XCTAssertTrue(signal.value == expected[4])
        }
    }
    
    func testCombineLatestWithUsingSourceAndStartWith() {
        var r = 0
        _ = combineLatest(Signal<Int>(), Signal<Int>()).start(with: (7, 11)).onValue { r += $0 + $1 }
        XCTAssertEqual(r, 7+11)
    }
    
    func testCombinedLatestMany() {
        runTest(timeout: 10) { bag in
            let a = ReadWriteSignal<String>("")
            let b = ReadWriteSignal<Int>(0)
            let c = ReadWriteSignal<Double>(0.0)
            let d = ReadWriteSignal<Bool>(false)
            
            let expected = ("one", 1, 1.0, true)
            
            let expectation = self.expectation(description: "All should combine")
            
            let signal = combineLatest(a, b, c, d)
            
            bag += signal.onValue { t in
                if t.0 == expected.0 &&
                    t.1 == expected.1 &&
                    t.2 == expected.2 &&
                    t.3 == expected.3 {
                    expectation.fulfill()
                }
            }
            
            a.value = "one"
            d.value = true
            c.value = 1.0
            b.value = 1
        }
  
    }

    func testCombinedLatestSequenceEmptyAtOnce() {
        var r = 0
        _ = combineLatest([] as [ReadSignal<Int>]).atOnce().onValue { _ in r = 1 }
        XCTAssertEqual(r, 1)
    }
    
    func testCombinedLatestSequence() {
        let a = ReadWriteSignal(0)
        let b = ReadWriteSignal(1)
        let c = ReadWriteSignal(2)
        var result = [Int]()
        let bag = DisposeBag()
        let signals = [a, b, c].map { $0.plain() }
        bag += combineLatest(signals).onValue { vals in
            result = vals
        }
        
        XCTAssertEqual(result, [])
        a.value = 3
        XCTAssertEqual(result, [])
        b.value = 44
        XCTAssertEqual(result, [])
        b.value = 4
        XCTAssertEqual(result, [])
        c.value = 5
        XCTAssertEqual(result, [3, 4, 5])

        a.value = 6
        XCTAssertEqual(result, [6, 4, 5])
        b.value = 7
        XCTAssertEqual(result, [6, 7, 5])
        c.value = 8
        XCTAssertEqual(result, [6, 7, 8])
    }
    
    func testCombinedLatestSequenceSignalSource() {
        let a = ReadWriteSignal(0)
        let b = ReadWriteSignal(1)
        let c = ReadWriteSignal(2)
        var result = [Int]()
        let bag = DisposeBag()
        let s = combineLatest([a, b, c]).atOnce()
        bag += s.onValue { vals in
            result = vals
        }
        
        XCTAssertEqual(result, [0, 1, 2])
        a.value = 3
        XCTAssertEqual(s.value, [3, 1, 2])
        XCTAssertEqual(result, [3, 1, 2])
        b.value = 4
        XCTAssertEqual(s.value, [3, 4, 2])
        XCTAssertEqual(result, [3, 4, 2])
        c.value = 5
        XCTAssertEqual(s.value, [3, 4, 5])
        XCTAssertEqual(result, [3, 4, 5])
    }
    
    func testCombinedLatestSequenceStartWith() {
        var r = 0
        _ = combineLatest([Signal<Int>(), Signal<Int>()]).start(with: [7]).onValue { r += $0.reduce(0, +) }
        XCTAssertEqual(r, 7)
    }

    func testCombineLatestRecursive() {
        let rw1 = ReadWriteSignal(0)
        let rw2 = ReadWriteSignal(10)

        var result = [Int]()
        let bag = DisposeBag()
        bag += combineLatest(rw1, rw2).atOnce().take(first: 5).onValue { v1, v2 in
            result.append(v1+v2)
            rw1.value += 1 // will recurse, so below will never be called
            rw2.value += 10
        }
        
        XCTAssertEqual(result, [10, 11, 12, 13, 14])
    }

    func testCombineLatestRecursive2() {
        let rw1 = ReadWriteSignal(0)
        let rw2 = ReadWriteSignal(10)
        
        var result = [Int]()
        let bag = DisposeBag()
        bag += combineLatest(rw1.atOnce().take(first: 3), rw2.atOnce().take(first: 3)).onValue { v1, v2 in
            result.append(v1+v2)
            rw1.value += 1 // will recurse, so below will never be called until take(3) is done but then "end" will be signaled so below will be ignored.
            rw2.value += 10
        }
        
        XCTAssertEqual(result, [10, 11, 12])
    }
    
    func testStartWithSingleValues() {
        test([1, 2, 3], expected: [0, 1, 2, 3]) {
            $0.start(with: 0)
        }
    }

    func testStartWithMutlipeValues() {
        test([2, 3, 4], expected: [0, 1, 2, 3, 4]) {
            $0.start(with: 0, 1)
        }
    }
    
    func testStartWithOrder() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        var r = [Int]()
        bag += property.start(with: 2).start(with: 1).onValue { r.append($0) }
        XCTAssertEqual(r, [1, 2])
        property.value = 3
        XCTAssertEqual(r, [1, 2, 3])
    }
    
    func testStartWithOrderMap() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        var r = [Int]()
        bag += property.map { $0 + 2 }.start(with: 2).start(with: 1).map { $0*2 }.onValue { r.append($0) }
        XCTAssertEqual(r, [2, 4])
        property.value = 1
        XCTAssertEqual(r, [2, 4, 6])
        
    }
    
    func testReuseStartWith() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        let s = property.map { $0 + 2 }.start(with: 2)
        var r = 0
        bag += s.onValue { r += $0*2 } //2*2 3*2
        bag += s.onValue { r += $0*3 } //2*3 3*3
        
        XCTAssertEqual(r, 4+6)
        
        
        property.value = 1
        XCTAssertEqual(r, 4+6+6+9)
        
        bag.dispose()
        
        r = 0
        property.value = 0
        bag += s.onValue { r += $0*2 } //2*2 3*2
        bag += s.onValue { r += $0*3 } //2*3 3*3
        
        XCTAssertEqual(r, 4+6)
        
        
        property.value = 1
        XCTAssertEqual(r, 4+6+6+9)

    }
    
    func testReuseStartWithTwice() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        let s = property.map { $0 + 2 }.start(with: 1).start(with: 2)
        var r = 0
        bag += s.onValue { r += $0*2 } //1*2 + 2*2
        bag += s.onValue { r += $0*3 } //1*3 + 2*3
        
        XCTAssertEqual(r, 2+4+3+6)
        
        
        property.value = 1
        XCTAssertEqual(r, 2+4+3+6+6+9)
        
        bag.dispose()
        
        r = 0
        property.value = 0
        bag += s.onValue { r += $0*2 }
        bag += s.onValue { r += $0*3 }
        
        XCTAssertEqual(r, 2+4+3+6)
        
        
        property.value = 1
        XCTAssertEqual(r, 2+4+3+6+6+9)
        
    }

    func testToSignalSource() {
        var result = [Int]()
        let bag = DisposeBag()
        bag += [1, 2, 3].signal().plain().readable(initial: 0).atOnce().onValue {
            result.append($0)
        }
        
        XCTAssertEqual(result, [0, 1, 2, 3])
    }

    func testStartWithAndFilter() {
        test([1, 2, 3], expected: [0, 1, 2, 3]) {
            $0.start(with: 0).filter {
                print("filter", $0)
                return true
                
            }
        }
    }
    
    func testAtOnce1() {
        var result = [Int]()
        let bag = DisposeBag()
        bag += [1, 2, 3].signal().plain().readable(initial: 0).atOnce().onValue { result.append($0) }
        XCTAssertEqual(result, [0, 1, 2, 3])
    }
    
    func testAtOnceAlt() {
        var result = [Int]()
        let bag = DisposeBag()
        bag += [1, 2, 3].signal().start(with: 0).atValue { result.append($0) }.collect().onValue {
            XCTAssertEqual($0, [0, 1, 2, 3])
        }
        XCTAssertEqual(result, [0, 1, 2, 3])
    }
    
    func testAtOnce2() {
        let a = ReadWriteSignal<Int>(0)
        var result = [Int]()
        
        let bag = DisposeBag()
        bag += a.atOnce().onValue { result.append($0) }
        a.value = 1
        a.value = 2
        XCTAssertEqual(result, [0, 1, 2])
    }
    
    func testAtOnce3() {
        let p = ReadWriteSignal(1)
        let bag = DisposeBag()
        var c = 0
        let p2 = p
        bag += p.atOnce().onValue { c += $0 }
        bag += p2.atOnce().onValue { c += $0 }
        XCTAssertEqual(c, 2)
    }

    func testAtOnce4() {
        let p = ReadWriteSignal(1)
        let bag = DisposeBag()
        var c = 0
        bag += p.atOnce().onValue { c += $0 }
        p.value = 2
        bag += p.atOnce().onValue { c += $0 }
        XCTAssertEqual(c, 1 + 2 + 2)
    }

    func testAtOnceShared() {
        let p = ReadWriteSignal(1)
        let bag = DisposeBag()
        var c = 0
        let s =  p.atOnce()
        bag += s.onValue {
            c += $0
        }
        p.value = 2
        bag += s.onValue {
            c += $0
        }
        XCTAssertEqual(c, 1 + 2 + 2)
    }
    
    func testNestedAtOnce() {
        let p = ReadWriteSignal(0)
        let bag = DisposeBag()
        var c = 0
        bag += p.onValue {
            let p2 = ReadWriteSignal(1)
            XCTAssertEqual(c, 0)
            bag += p2.atOnce().onValue {
                c += $0
            }
            XCTAssertEqual(c, 1)
            c += $0
        }
        p.value = 1
        XCTAssertEqual(c, 2)
    }

    func testDistinctNoSource() {
        let p = ReadWriteSignal(1)
        let bag = DisposeBag()
        var c = 0
        let s = p.plain().distinct()
        bag += s.onValue {
            c += $0
        }
        p.value = 1
        p.value = 1
        p.value = 2
        p.value = 2
        p.value = 3
        
        XCTAssertEqual(c, 1 + 2 + 3)
    }

    func testDistinctNoSourceAlt() {
        let p = ReadWriteSignal(1)
        let bag = DisposeBag()
        var c = 0
        let s = p.plain().distinct()
        bag += s.onValue {
            c += $0
        }
        p.value = 1
        p.value = 1
        p.value = 2
        p.value = 2
        p.value = 3
        
        XCTAssertEqual(c, 1 + 2 + 3)
    }
    
    func testDistinctHasSource() {
        let p = ReadWriteSignal(1)
        let bag = DisposeBag()
        var c = 0
        let s = p.distinct()
        bag += s.onValue {
            c += $0
        }
        XCTAssertEqual(s.value, 1)
        p.value = 1
        XCTAssertEqual(s.value, 1)
        p.value = 1
        XCTAssertEqual(s.value, 1)
        p.value = 2
        XCTAssertEqual(s.value, 2)
        p.value = 2
        XCTAssertEqual(s.value, 2)
        p.value = 3
        XCTAssertEqual(s.value, 3)
        
        XCTAssertEqual(c, 2 + 3)
    }
    
    func testDistinctAtOnce() {
        let p = ReadWriteSignal(1)
        let bag = DisposeBag()
        var c = 0
        let s = p.distinct()
        bag += s.atOnce().onValue {
            c += $0
        }
        XCTAssertEqual(s.value, 1)
        p.value = 1
        XCTAssertEqual(s.value, 1)
        p.value = 1
        XCTAssertEqual(s.value, 1)
        p.value = 2
        XCTAssertEqual(s.value, 2)
        p.value = 2
        XCTAssertEqual(s.value, 2)
        p.value = 3
        XCTAssertEqual(s.value, 3)

        XCTAssertEqual(c, 1 + 2 + 3)
    }

    func testCombineLatestAtOnce() {
        let p = ReadWriteSignal(1)
        let bag = DisposeBag()
        var c = 0
        bag += combineLatest(p, p).atOnce().onValue {
            c += $0 + $1
        }
        XCTAssertEqual(c, 2)
    }
    
    func testCombinedLatestRecursiveFirst() {
        let ap = ReadWriteSignal(1)
        let bp = ReadWriteSignal(10)
        var result = [Int]()
        let bag = DisposeBag()
        bag += combineLatest(ap, bp).map { a, b -> (Int, Int) in
            print("map", a, b)
            if a == 1 {
                ap.value = 2
            }
            return (a, b)
        }.atOnce().onValue { a, b in
            print("onValue", a, b)
            result.append(a)
            result.append(b)
        }
        XCTAssertEqual(result, [1, 10, 2, 10])
    }
    
    func testCombinedLatestRecursiveSecond() {
        let ap = ReadWriteSignal(1)
        let bp = ReadWriteSignal(10)
        var result = [Int]()
        let bag = DisposeBag()
        bag += combineLatest(ap, bp).map { a, b -> (Int, Int) in
            print("atValue", a, b)
            if b == 10 {
                bp.value = 20
            }
            return (a, b)

        }.atOnce().onValue { a, b in
            print("onValue", a, b)
            result.append(a)
            result.append(b)
        }
        XCTAssertEqual(result, [1, 10, 1, 20])
    }

    func testMappedAtOnce() {
        let a = ReadWriteSignal<Int>(0)
        var result = [Int]()
        let b = a.map { $0 }
        
        let bag = DisposeBag()
        a.value = 1
        
        bag += b.atOnce().onValue { result.append($0) }
        a.value = 2
        a.value = 3
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testSharedSignal() {
        let callbacker = Callbacker<Int>()
        var s1 = 0
        let s = Signal<Int> { c in
            s1 += 1
            return callbacker.addCallback(c)
        }
        
        var s2 = 0
        var s3 = 0
        
        let bag = DisposeBag()
        bag += s.onValue { _ in s2 += 1 }
        bag += s.onValue { _ in s3 += 1 }
        
        callbacker.callAll(with: 1)
        callbacker.callAll(with: 2)
        XCTAssertEqual(s1, 1)
        XCTAssertEqual(s2, 2)
        XCTAssertEqual(s3, 2)
    }

    func testSharedReadSignal() {
        let callbacker = Callbacker<Int>()
        var s1 = 0
        let s = ReadSignal(capturing: s1) { c -> Disposable in
            s1 += 1
            return callbacker.addCallback(c)
        }
        
        var s2 = 0
        var s3 = 0
        
        let bag = DisposeBag()
        bag += s.atOnce().onValue { _ in s2 += 1 }
        bag += s.atOnce().onValue { _ in s3 += 1 }
        
        callbacker.callAll(with: 1)
        callbacker.callAll(with: 2)
        XCTAssertEqual(s1, 1)
        XCTAssertEqual(s2, 3)
        XCTAssertEqual(s3, 3)
    }
    
    func testSharedRemoveAndAdd() {
        let callbacker = Callbacker<Int>()
        var s0 = 0
        let s = Signal<Int> { c in
            s0 += 1
            return callbacker.addCallback(c)
        }
        
        var s1 = 0
        var s2 = 0
        
        let d1 = s.onValue { s1 += $0 }
        let d2 = s.onValue { s2 += $0 }
        
        callbacker.callAll(with: 1)
        callbacker.callAll(with: 2)
        XCTAssertEqual(s0, 1)
        XCTAssertEqual(s1, 1+2)
        XCTAssertEqual(s2, 1+2)

        d2.dispose()
        callbacker.callAll(with: 3)
        XCTAssertEqual(s0, 1)
        XCTAssertEqual(s1, 1+2+3)
        XCTAssertEqual(s2, 1+2)
        
        var s3 = 0
        let d3 = s.onValue { s3 += $0 }
        callbacker.callAll(with: 4)
        XCTAssertEqual(s0, 1)
        XCTAssertEqual(s1, 1+2+3+4)
        XCTAssertEqual(s2, 1+2)
        XCTAssertEqual(s3, 4)
        
        d1.dispose()
        callbacker.callAll(with: 5)
        XCTAssertEqual(s0, 1)
        XCTAssertEqual(s1, 1+2+3+4)
        XCTAssertEqual(s2, 1+2)
        XCTAssertEqual(s3, 4+5)

        d3.dispose()
        callbacker.callAll(with: 6)
        XCTAssertEqual(s0, 1)
        XCTAssertEqual(s1, 1+2+3+4)
        XCTAssertEqual(s2, 1+2)
        XCTAssertEqual(s3, 4+5)
        
        var s4 = 0
        let d4 = s.onValue { s4 += $0 }

        callbacker.callAll(with: 7)
        XCTAssertEqual(s0, 2)
        XCTAssertEqual(s1, 1+2+3+4)
        XCTAssertEqual(s2, 1+2)
        XCTAssertEqual(s3, 4+5)
        XCTAssertEqual(s4, 7)

        d4.dispose()
    }

    
    func testMap() {
        runTest { bag in
            let e = expectation(description: "1")
            bag += ReadWriteSignal(2).atOnce().map { $0*2 }.onValue { XCTAssertEqual($0, 4); e.fulfill() }
        }
    }

    func testCompactMapOptionalSome() {
        runTest { bag in
            let e = expectation(description: "1")
            bag += ReadWriteSignal(2).atOnce().compactMap { $0*2 }.onValue { XCTAssertEqual($0, 4); e.fulfill() }
        }
    }

    func testCompactMapOptionalNone() {
        runTest { bag in
            let e = expectation(description: "1")
            bag += ReadWriteSignal(2).atOnce().atValue { _ in e.fulfill() }.compactMap { _ -> Int? in nil }.onValue { _ in XCTAssert(false) }
        }
    }
    
    
    func testBindTo() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        bag += [1, 2].signal().bindTo(property)
        XCTAssertEqual(property.value, 2)
    }
    
    func testBidirectionallyBindTo() {
        let rw1 = ReadWriteSignal(0) 
        let rw2 = ReadWriteSignal(1)
        
        let bag = DisposeBag()
        bag += rw1.bidirectionallyBindTo(rw2)
        
        XCTAssertEqual(rw1.value, 0)
        XCTAssertEqual(rw2.value, 1)
        
        rw1.value = 0
        XCTAssertEqual(rw1.value, 0)
        XCTAssertEqual(rw2.value, 0)
        
        rw1.value = 2
        XCTAssertEqual(rw1.value, 2)
        XCTAssertEqual(rw2.value, 2)
        
        rw1.value = 4
        XCTAssertEqual(rw1.value, 4)
        XCTAssertEqual(rw2.value, 4)
        
        rw2.value = 6
        XCTAssertEqual(rw1.value, 6)
        XCTAssertEqual(rw2.value, 6)
        
        rw1.value = 8
        XCTAssertEqual(rw1.value, 8)
        XCTAssertEqual(rw2.value, 8)
    }

    func testBidirectionallyBindToReadableAtOnceLeft() {
        let rw1 = ReadWriteSignal(0)
        let rw2 = ReadWriteSignal(1)
        
        let bag = DisposeBag()
        bag += rw1.atOnce().bidirectionallyBindTo(rw2)
        
        XCTAssertEqual(rw1.value, 0)
        XCTAssertEqual(rw2.value, 0)
        
        rw1.value = 2
        XCTAssertEqual(rw1.value, 2)
        XCTAssertEqual(rw2.value, 2)
        
        rw2.value = 4
        XCTAssertEqual(rw1.value, 4)
        XCTAssertEqual(rw2.value, 4)
    }

    func testBidirectionallyBindToReadableAtOnceRight() {
        let rw1 = ReadWriteSignal(0)
        let rw2 = ReadWriteSignal(1)
        
        let bag = DisposeBag()
        bag += rw1.bidirectionallyBindTo(rw2.atOnce())
        
        XCTAssertEqual(rw1.value, 1)
        XCTAssertEqual(rw2.value, 1)
        
        rw1.value = 2
        XCTAssertEqual(rw1.value, 2)
        XCTAssertEqual(rw2.value, 2)
        
        rw2.value = 4
        XCTAssertEqual(rw1.value, 4)
        XCTAssertEqual(rw2.value, 4)
    }

    func testBidirectionallyBindToReadableAtOnceBoth() {
        let rw1 = ReadWriteSignal(0)
        let rw2 = ReadWriteSignal(1)
        
        let bag = DisposeBag()
        bag += rw1.atOnce().bidirectionallyBindTo(rw2.atOnce())
        
        XCTAssertEqual(rw1.value, 0)
        XCTAssertEqual(rw2.value, 0)
        
        rw1.value = 2
        XCTAssertEqual(rw1.value, 2)
        XCTAssertEqual(rw2.value, 2)
        
        rw2.value = 4
        XCTAssertEqual(rw1.value, 4)
        XCTAssertEqual(rw2.value, 4)
    }
    
    func testAnySame() {
        let bag = DisposeBag()
        let callbacker = Callbacker<Event<Int>>()
        let s = FiniteSignal<Int>(callbacker: callbacker)
        bag += merge(s, s).collect().onValue {
            XCTAssertEqual($0, [2, 2])
        }
        callbacker.callAll(with: .value(2))
        callbacker.callAll(with: .end)
    }

    func testAnySameAtOnce() {
        let bag = DisposeBag()
        let callbacker = Callbacker<Event<Int>>()
        let s = FiniteSignal<Int>(callbacker: callbacker).plain().readable(initial: 1)
        var result = [Int]()
        bag += merge(s, s).atOnce().onValue {
            result.append($0)
        }
        
        XCTAssertEqual(s.value, 1)
        callbacker.callAll(with: .value(2))
        callbacker.callAll(with: .end)
        XCTAssertEqual(result, [1, 2, 2])
    }
    
    func testReuseAtOnce() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        let s = property.map { $0 + 2 }.atOnce()
        var r = 0
        bag += s.onValue { r += $0*2 } //2*2 3*2
        bag += s.onValue { r += $0*3 } //2*3 3*3
        
        XCTAssertEqual(r, 4+6)
        
        
        property.value = 1
        XCTAssertEqual(r, 4+6+6+9)
    }
    
    func testReuseDoubleAtOnce() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        let s = property.map { $0 + 2 }.atOnce().atOnce()
        var r = 0
        bag += s.onValue { r += $0*2; print("a", $0) } //2*2 * 2
        bag += s.onValue { r += $0*3; print("b", $0) } //2*3 * 2
        
        XCTAssertEqual(r, (4+6)*2)
        
        property.value = 1
        XCTAssertEqual(r, (4+6)*2 + 3*2 + 3*3)
    }
    
    func testDoubleAtOnceLatestTwo() {
        let property = ReadWriteSignal(1)
        
        var value = 0
        let bag = DisposeBag()
        bag += property.atOnce().atOnce().latestTwo().bindTo {
            value = $0 + $1
        }
        XCTAssertEqual(value, 1 + 1)
        property.value = 2
        XCTAssertEqual(value, 1 + 2)
    }

    func testReuseDoubleAtOnceComplex() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        let s = property.map { $0 + 2 }.atOnce().map { $0 - 1 }.atOnce().map { $0 + 1 }.filter { _ in true }
        var r = 0
        bag += s.onValue { r += $0*2; print("a", $0) } //2*2 * 2
        bag += s.onValue { r += $0*3; print("b", $0) } //2*3 * 2
        
        XCTAssertEqual(r, (4+6)*2)
        
        property.value = 1
        XCTAssertEqual(r, (4+6)*2 + 3*2 + 3*3)
    }
    
    func testReuseAtOnceMap() {
        let property = ReadWriteSignal(0)
        let bag = DisposeBag()
        let s = property.map { $0 + 1 }.atOnce()
        var r = 0
        bag += s.map { $0 + 1 }.onValue { r += $0*2 } //2*2 + 3*2
        bag += s.map { $0 + 2 }.onValue { r += $0*3 } //3*3 + 4*3
        
        XCTAssertEqual(r, 4+9)
        
        property.value = 1
        XCTAssertEqual(r, 4+9+6+12)
    }
    
    func testReuseAtOnceEmptyTuple() {
        let bag = DisposeBag()
        let callbacker = Callbacker<()>()
        let s = Signal(callbacker: callbacker).atOnce()
        var r = 0
        bag += s.onValue { r += 2 }
        bag += s.onValue { r += 3 }
        
        XCTAssertEqual(r, 2 + 3)
        
        callbacker.callAll(with: ())

        XCTAssertEqual(r, 2 + 3 + 2 + 3)
    }

    func testStartWithTheRetriggerWithinOnEventBasic() {
        let bag = DisposeBag()
        let callbacker = Callbacker<Int>()
        
        var vals = [Int]()
        
        var done = false
        bag += Signal(callbacker: callbacker).onValue { val in
            print("append", val)
            vals.append(val)
            guard !done else { return }
            done = true
            callbacker.callAll(with: 2)
        }
        callbacker.callAll(with: 1)
        
        XCTAssertEqual(vals, [1, 2])
    }

    func testStartWithTheRetriggerWithinOnEventLatestTwo() {
        let bag = DisposeBag()
        let callbacker = Callbacker<Int>()
        
        var vals = [(Int, Int)]()
        
        var done = false
        bag += Signal(callbacker: callbacker).latestTwo().onValue { val in
            print("append", val)
            vals.append(val)
            guard !done else { return }
            done = true
            callbacker.callAll(with: 3)
        }
        callbacker.callAll(with: 1)
        callbacker.callAll(with: 2)
        
        XCTAssertEqual(vals.count, 2)
        XCTAssertTrue(vals[0] == (1, 2))
        XCTAssertTrue(vals[1] == (2, 3))
    }

    func _testStartWithTheRetriggerWithinOnEventMerge() { /// Sometime fails sometime not.
        for _ in 0..<1 {
            let bag = DisposeBag()
            let callbacker = Callbacker<Int>()
            
            var vals = [Int]()
            
            var done = false
            let s = Signal(callbacker: callbacker)
            bag += merge(s.take(first: 1), s.skip(first: 1).finite()).onValue { val in
                print("append", val)
                vals.append(val)
                guard !done else { return }
                done = true
                callbacker.callAll(with: 2)
            }
            callbacker.callAll(with: 1)
            
            XCTAssertEqual(vals, [1, 2])
        }
    }
    
    func testStartWithTheRetriggerWithinOnEvent_() {
        let bag = DisposeBag()
        let callbacker = Callbacker<Int>()
        
        var vals = [Int]()
        bag += Signal(callbacker: callbacker).distinct().onValue { val in
            print("append", val)
            vals.append(val)
            callbacker.callAll(with: 2)
        }
        callbacker.callAll(with: 1)
        
        XCTAssertEqual(vals, [1, 2])
    }
    
    func testStartWithTheRetriggerWithinOnEvent() {
        let bag = DisposeBag()
        let callbacker = Callbacker<Int>()
        
        var vals = [Int]()
        bag += Signal(callbacker: callbacker).start(with: 1).atValue { print("atValue", $0) }.distinct().onValue { val in
            print("append", val)
            vals.append(val)
            callbacker.callAll(with: 2)
        }
        
        XCTAssertEqual(vals, [1, 2])
    }

    func testAtOnceWithTheRetriggerWithinOnEvent() {
        let bag = DisposeBag()
        let p = ReadWriteSignal(1)
        
        var vals = [Int]()
        bag += p.atOnce().plain().atValue { print("atValue", $0) }.distinct().onValue { val in
            print("append", val)
            vals.append(val)
            p.value = 2
        }
        
        XCTAssertEqual(vals, [1, 2])
    }
    
    func testStartWithTheRetriggerWithinOnEventWithCollect() {
        let bag = DisposeBag()
        let callbacker = Callbacker<Event<Int>>()
        
        bag += FiniteSignal(callbacker: callbacker).start(with: 1).distinct().atValue { val in
            print("append", val)
            callbacker.callAll(with: .value(2))
            callbacker.callAll(with: .end)
        }.collect().onValue {
            XCTAssertEqual($0, [1, 2])
        }
    }
    
    func testStartWithTheRetriggerWithinOnEventWithCollectAsync() {
        runTest(timeout: 1) { bag in
            let e = expectation(description: "1")
            
            let callbacker = Callbacker<Event<Int>>()
            
            bag += FiniteSignal(callbacker: callbacker).start(with: 1).distinct().atValue { val in
                print("append", val)
                callbacker.callAll(with: .value(2))
                callbacker.callAll(with: .end)
            }.collect().onValue {
                XCTAssertEqual($0, [1, 2])
                e.fulfill()
            }
        }
    }

    func testBasicRecursion() {
        //let e = expectation(description: "")
        let callbacker = Callbacker<Int>()
        var results = [Int]()
        _ = Signal(callbacker: callbacker).start(with: 1).distinct().onValue { val in
            print(val)
            callbacker.callAll(with: 2)
            
            results.append(val)
            //e.fulfill()
        }
        
        XCTAssertEqual(results, [1, 2])
        
        //waitForExpectations(timeout: 1) { _ in }
    }

    func testBasicRecursionEnd() {
        let callbacker = Callbacker<Int>()
        _ = Signal(callbacker: callbacker).start(with: 1).take(first: 4).atValue { val in
            print(val)
            callbacker.callAll(with: val*2)
            callbacker.callAll(with: val*2 + 1)
        }.collect().onValue { vals in
            XCTAssertEqual(vals, [1, 2, 3, 4])
        }
    }

    func testExclusiveImmediate() {
        let callbacker = Callbacker<Int>()
        var result = [Int]()
        _ = Signal(callbacker: callbacker).start(with: 1).take(first: 2).onValue { val in
            result.append(val)
            callbacker.callAll(with: val + 1)
            result.append(val*10)
        }
        XCTAssertEqual(result, [1, 10, 2, 20])
    }

    func testExclusiveImmediateTake() {
        let signal = ReadWriteSignal(1)
        var result = 0
        _ = signal.atOnce().take(first: 2).onValue { val in
            signal.value = val + 1
            result = val
        }
        XCTAssertEqual(result, 2)
    }

    func testExclusiveImmediateDistinct() {
        let signal = ReadWriteSignal(1)
        var result = 0
        _ = signal.distinct().atOnce().onValue { val in
            signal.value = 2
            result = val
        }
        XCTAssertEqual(result, 2)
    }

    func testExclusive() {
        let callbacker = Callbacker<Int>()
        var result = [Int]()
        let bag = DisposeBag()
        bag += Signal(callbacker: callbacker).take(first: 2).onValue { val in
            result.append(val)
            callbacker.callAll(with: val + 1)
            result.append(val*10)
        }
        
        callbacker.callAll(with: 1)
        XCTAssertEqual(result, [1, 10, 2, 20])
    }
    
    func testExclusiveAlt() {
        let callbacker = Callbacker<Int>()
        let bag = DisposeBag()
        var result = 0
        bag += Signal(callbacker: callbacker).take(first: 2).onValue { val in
            callbacker.callAll(with: val + 1)
            result = val
        }
        
        callbacker.callAll(with: 1)
        XCTAssertEqual(result, 2)
    }
    
    func testTransactionalAndInitialRecursion() {
        let callbacker = Callbacker<Event<Int>>()
        var result = [Int]()
        _ = FiniteSignal(callbacker: callbacker).start(with: 1).onValue { val in
            result.append(val)
            callbacker.callAll(with: .value(val + 1))
            callbacker.callAll(with: .end)
        }
        XCTAssertEqual(result, [1, 2])
    }
    
    func testExclusiveRecursion() {
        let callbacker = Callbacker<Event<Int>>()
        var result = [Int]()
        let bag = DisposeBag()
        bag += FiniteSignal<Int>(callbacker: callbacker).onValue { val in
            print(val)
            result.append(val)
            callbacker.callAll(with: .value(val + 1))
            callbacker.callAll(with: .end)
        }
        callbacker.callAll(with: .value(1))
        XCTAssertEqual(result, [1, 2])
    }
    
    func _testExclusiveMultiThread() {
        for _ in 0..<1000 {
            let callbacker = Callbacker<Int>()
            var result = [Int]()
            let mutex = Mutex()
            _ = Signal(callbacker: callbacker).start(with: 1).take(first: 2).onEvent(on: .concurrentBackground) { event in
                switch event {
                case .value(let val):
                    mutex.protect { result.append(val) }
                    backgroundQueue.async {
                        callbacker.callAll(with: val + 1)
                    }
                    mutex.protect { result.append(val*10) }
                case .end:
                    XCTAssertEqual(mutex.protect { result }, [1, 10, 2, 20])
                }
            }
        }
    }
    
    func testRecursive() {
        let bag = DisposeBag()
        
        let callbacker = Callbacker<Int>()
        let callbacker2 = Callbacker<Int>()
        
        var val = 1
        bag += Signal(callbacker: callbacker2).onValue {
            val = $0
        }
        
        bag += Signal(callbacker: callbacker).onValue { _ in
            XCTAssertEqual(val, 1)
            callbacker2.callAll(with: 2)
            XCTAssertEqual(val, 2)
        }
        
        callbacker.callAll(with: 1)
    }
    
    func testRecursiveAlt() {
        let bag = DisposeBag()
        
        var result = 0
        let callbacker = Callbacker<Int>()
        
        bag += Signal(callbacker: callbacker).onValue {
            result = $0
        }
        
        let callbacker2 = Callbacker<Double>()
        bag += Signal(callbacker: callbacker2).onValue { val in
            XCTAssertEqual(result, 0)
            callbacker.callAll(with: 4)
            XCTAssertEqual(result, 4)
        }
        
        callbacker2.callAll(with: 3.14)

        XCTAssertEqual(result, 4)
        callbacker.callAll(with: 8)
        XCTAssertEqual(result, 8)
    }

    
    func testCurrent() {
        let p = ReadWriteSignal<Int>(0)
        let s = p.map { $0 * 2 }

        XCTAssertEqual(s.value, 0)
        p.value = 1
        XCTAssertEqual(s.value, 2)
        p.value = 2
        XCTAssertEqual(s.value, 4)
    }

    func testMakeReadableCapturingNoListners() {
        let callbacker = Callbacker<Int>()
        
        var val = 0
        let s = Signal(callbacker: callbacker).readable(capturing: val).map { $0 * 2 }
        
        XCTAssertEqual(s.value, 0)
        val = 1
        XCTAssertEqual(s.value, 2)
        val = 2
        XCTAssertEqual(s.value, 4)
    }

    func testMakeReadableCapturingListener() {
        let callbacker = Callbacker<Int>()
        
        var val = 0
        let s = Signal(callbacker: callbacker).readable(capturing: val).map { $0 * 2 }
        let bag = DisposeBag()
        var result = 0
        bag += s.onValue { result += $0 }
        
        XCTAssertEqual(s.value, 0)
        val = 1
        XCTAssertEqual(s.value, 2)
        callbacker.callAll(with: 2)
        XCTAssertEqual(s.value, 2)
        
        bag.dispose()
        
        val = 3
        XCTAssertEqual(s.value, 6)
        
        XCTAssertEqual(result, 4)

    }

    func testAddSourceInitital() {
        let callbacker = Callbacker<Int>()
        
        let s = Signal(callbacker: callbacker).readable(initial: 0).map { $0 * 2 }
        
        let bag = DisposeBag()
        var result = 0
        bag += s.onValue { result += $0 }

        XCTAssertEqual(s.value, 0)
        callbacker.callAll(with: 1)
        XCTAssertEqual(s.value, 2)
        callbacker.callAll(with: 2)
        XCTAssertEqual(s.value, 4)
        
        bag.dispose()

        callbacker.callAll(with: 4)
        XCTAssertEqual(s.value, 0)

        XCTAssertEqual(result, 6)

    }
    
    func testFlatMapLatestNoSource() {
        let o = ReadWriteSignal(0) // outer
        let i = ReadWriteSignal(0) // inner
        
        let bag = DisposeBag()
        var r = 0
        var cnt = 0
        bag += o.plain().flatMapLatest { val in
            return i.plain().map { val + $0 }
        }.onValue {
            cnt += 1
            r = $0
        }
        
        XCTAssertEqual(r, 0)
        i.value = 1 //cnt
        XCTAssertEqual(r, 0)
        o.value = 2
        XCTAssertEqual(r, 0)
        i.value = 3
        XCTAssertEqual(r, 2 + 3)
        i.value = 4 //cnt
        XCTAssertEqual(r, 2 + 4)
        o.value = 5
        XCTAssertEqual(r, 2 + 4)
        i.value = 6 //cnt
        XCTAssertEqual(r, 5 + 6)
        
        XCTAssertEqual(cnt, 3)
    }

    func testFlatMapLatestHasSource() {
        let o = ReadWriteSignal(1) // outer
        let i = ReadWriteSignal(2) // inner
        
        let bag = DisposeBag()
        var r = 0
        var cnt = 0
        bag += o.readOnly().flatMapLatest { val in
            return i.readOnly().map { val + $0 }
        }.atOnce().onValue {
            cnt += 1
            r = $0
        } //cnt
        
        XCTAssertEqual(r, 3)
        i.value = 3 //cnt
        XCTAssertEqual(r, 1 + 3)
        o.value = 4 //cnt
        XCTAssertEqual(r, 4 + 3)
        i.value = 5 //cnt
        XCTAssertEqual(r, 4 + 5)
        i.value = 6 //cnt
        XCTAssertEqual(r, 4 + 6)
        o.value = 7 //cnt
        XCTAssertEqual(r, 7 + 6)
        i.value = 8 //cnt
        XCTAssertEqual(r, 7 + 8)
        
        XCTAssertEqual(cnt, 7)
    }

    func testFlatMapLatestHasSourceAlt() {
        let o = ReadWriteSignal(1) // outer
        let ia = ReadWriteSignal(2) // inner a
        let ib = ReadWriteSignal(3) // inner b
        
        let bag = DisposeBag()
        var r = 0
        var cnt = 0
        bag += o.readOnly().flatMapLatest { val in
            return (val > 2 ? ib : ia).readOnly().map { val + $0 }
        }.atOnce().onValue {
            cnt += 1
            r = $0
        } //cnt
        
        XCTAssertEqual(r, 1 + 2)
        ib.value = 4
        XCTAssertEqual(r, 1 + 2)
        ia.value = 3 //cnt
        XCTAssertEqual(r, 1 + 3)
        o.value = 2 //cnt
        XCTAssertEqual(r, 2 + 3)
        o.value = 3 //cnt
        XCTAssertEqual(r, 3 + 4)
        ia.value = 4
        XCTAssertEqual(r, 3 + 4)
        ib.value = 5 //cnt
        XCTAssertEqual(r, 3 + 5)
     
        XCTAssertEqual(cnt, 5)
    }
    
    #if os(iOS)
    
    func testUITextField() {
        let bag = DisposeBag()
        let t = UITextField()
        
        var string = ""
        var c = 0
        bag += t.onValue {
            string = $0
            c += 1
        }
        XCTAssertEqual(c, 0)

        t.text = "Hello"
        XCTAssertEqual(t.providedSignal.value, "Hello")
        XCTAssertEqual(string, "Hello")
        XCTAssertEqual(c, 1)

        t.providedSignal.value = "Again"
        XCTAssertEqual(t.providedSignal.value, "Again")
        XCTAssertEqual(string, "Again")
        XCTAssertEqual(c, 2)
        
        let p = ReadWriteSignal("")
        bag += p.bindTo(t)
        p.value = "Prop"
        XCTAssertEqual(t.providedSignal.value, "Prop")
        XCTAssertEqual(string, "Prop")
        XCTAssertEqual(c, 3)
    
        bag.dispose()

    }
    
    #endif
    
    
    func testMakeDistinct() {
        var val = 0
        var setCnt = 0

        let p = ReadWriteSignal(getValue: { val }, setValue: { val = $0; setCnt += 1 }).distinct()
        
        let bag = DisposeBag()
        
        var cnt = 0
        bag += p.onValue { _ in
            cnt += 1
        }
        
        p.value = 0
        p.value = 1
        p.value = 1
        p.value = 2
        
        XCTAssertEqual(setCnt, 2)
        XCTAssertEqual(cnt, 2)
    }
    
    
    func testShared() {
        var val = 0
        
        var getCnt = 0
        let p = ReadWriteSignal(getValue: {
            getCnt += 1
            return val
        }, setValue: { val = $0 }).shared()
        
        let bag = DisposeBag()
        
        XCTAssertEqual(getCnt, 0)
        XCTAssertEqual(p.value, val)
        XCTAssertEqual(getCnt, 1)
        
        var cnt = 0
        bag += p.onValue { _ in
            cnt += 1
        }
        
        p.value = 1
        XCTAssertEqual(getCnt, 2)
        XCTAssertEqual(p.value, 1)
        XCTAssertEqual(getCnt, 2)

        var cnt2 = 0
        bag += p.atOnce().onValue { _ in
            cnt2 += 1
        }

        XCTAssertEqual(getCnt, 2)
        XCTAssertEqual(p.value, 1)
        XCTAssertEqual(cnt2, 1)
        XCTAssertEqual(getCnt, 2)

        p.value = 2
        
        XCTAssertEqual(getCnt, 2)
        XCTAssertEqual(p.value, 2)
        XCTAssertEqual(cnt, 2)
        XCTAssertEqual(cnt2, 2)
        XCTAssertEqual(getCnt, 2)
        
        bag.dispose()

        p.value = 3

        XCTAssertEqual(p.value, 3)
        XCTAssertEqual(getCnt, 3)
    }
    
    func testSignalShared() {
        var val = 0
        
        let callbacker = Callbacker<Int>()
        let foreverBag = DisposeBag()

        foreverBag += callbacker.addCallback {
            val = $0
        }
        var getCnt = 0
        let p = ReadSignal(getValue: {
            getCnt += 1
            return val
        }, onValue: callbacker.addCallback)
        
        let bag = DisposeBag()

        XCTAssertEqual(getCnt, 0)
        XCTAssertEqual(p.value, val)
        XCTAssertEqual(getCnt, 1)
        
        var cnt = 0
        bag += p.onValue { _ in
            cnt += 1
        }
        
        callbacker.callAll(with: 1)
        XCTAssertEqual(getCnt, 2)
        XCTAssertEqual(p.value, 1)
        XCTAssertEqual(getCnt, 2)
        
        var cnt2 = 0
        bag += p.atOnce().onValue { _ in
            cnt2 += 1
        }
        
        XCTAssertEqual(getCnt, 2)
        XCTAssertEqual(p.value, 1)
        XCTAssertEqual(cnt2, 1)
        XCTAssertEqual(getCnt, 2)
        
        callbacker.callAll(with: 2)

        XCTAssertEqual(getCnt, 2)
        XCTAssertEqual(p.value, 2)
        XCTAssertEqual(cnt, 2)
        XCTAssertEqual(cnt2, 2)
        XCTAssertEqual(getCnt, 2)
        
        bag.dispose()
        
        callbacker.callAll(with: 3)

        XCTAssertEqual(p.value, 3)
        XCTAssertEqual(getCnt, 3)
    }
}

class SignalProviderStressTests: XCTestCase {
    func testStressSerial() {
        runTest(timeout: 10) { bag in
            let queue = DispatchQueue(label: "another.concurrent.background", attributes: .concurrent)
            
            for i in 0..<100 {
                let count = 100
                let c1 = Callbacker<Int>()
                let c2 = Callbacker<Int>()
                let s1 = Signal(callbacker: c1)
                let s2 = Signal(callbacker: c2)
                
                let e = expectation(description: "\(i)")
                Scheduler.background.async {
                    let s = combineLatest(s1, s2).take(first: 1000).map { $0.0 + $0.1 }
                    bag += merge(s, s).take(first: count*2).collect().onValue { vals in
                        //print(i, vals.count)
                        XCTAssertEqual(vals.count, count*2)
                        e.fulfill()
                    }
                    
                    for i in 0..<count {
                        queue.async {
                            c1.callAll(with: i)
                        }
                        queue.async {
                            c2.callAll(with: i*1000)
                        }
                    }
                }
            }
        }
    }
    
    func testStressConcurrent() {
        runTest(timeout: 10) { bag in
            let queue = DispatchQueue(label: "another.concurrent.background", attributes: .concurrent)
            
            for i in 0..<100 {
                let count = 100
                let c1 = Callbacker<Int>()
                let c2 = Callbacker<Int>()
                let s1 = Signal(callbacker: c1)
                let s2 = Signal(callbacker: c2)
                
                
                let e = expectation(description: "\(i)")
                Scheduler.concurrentBackground.async {
                    bag += combineLatest(s1, s2).map { $0.0 + $0.1 }.take(first: count).collect().onValue { vals in
                        XCTAssert(vals.count <= count) // Cant not guaranted count as end might sneak before a value when concurrent.
                        e.fulfill()
                    }
                    
                    for i in 0..<count {
                        queue.async {
                            c1.callAll(with: i)
                        }
                        queue.async {
                            c2.callAll(with: i*1000)
                        }
                    }
                }
            }
            
        }
    }

    func testSerialOrder() {
        runTest(timeout: 10) { bag in
            for i in 0..<100 {
                let e = expectation(description: "\(i)")
                bag += (0..<100).signal().map(on: .background) { $0 * 2 }.collect().onValue { vals in
                    //print(vals)
                    XCTAssertEqual((0..<100).map { $0*2 }, vals)
                    e.fulfill()
                    
                }
            }
        }
    }
    
    func testConcurentOrder() {
        runTest(timeout: 10) { bag in
            for i in 0..<100 {
                let e = expectation(description: "\(i)")
                bag += (0..<100).signal().map(on: .concurrentBackground) { $0 * 2 }.collect().onValue { vals in
                    //print(vals)
                    //XCTAssertEqual((0..<100).map { $0*2 }, vals) // mapping on concurrent queue can not guarantee order and hence not count either as an end might go past a previous value.
                    e.fulfill()
                }
            }
            
        }
    }
    
    func testDisposeAtScheduler() {
        runTest(timeout: 10) { bag in
            
            // Delay sync to make sure it won't be scheduled
            let scheduler = Scheduler(identifyingObject: self, async: { mainQueue.async(execute: $0) }, sync: { $0() })
            
            let rw = ReadWriteSignal(1)
            let e = expectation(description: "only second after dispose")
            
            let s = rw.atOnce().map(on: scheduler) { $0 * 2 }
            
            bag += s.onValue { _ in
                XCTAssert(false, "We should not get here")
            }
            
            bag.dispose()
            bag += s.onValue { _ in
                e.fulfill()
            }
        }
    }
    
    func testDebounce() {
        runTest(timeout: 2) { bag in
            let signal = ReadWriteSignal(1)
            
            var result = [Int]()
            bag += signal.debounce(0.2).atOnce().onValue {
                result.append($0)
            }
            
            signal.value = 2
            
            let signals: [(TimeInterval, Int)] = [
                (0.1, 3),
                (0.2, 4),
                (0.5, 5),
                (0.6, 6),
                (0.7, 7),
                (1.0, 8),
                ]
            
            for (time, value) in signals {
                Scheduler.main.async(after: time) {
                    signal.value = value
                }
            }
  
            let e = expectation(description: "done")
            Scheduler.main.async(after: 1.5) {
                e.fulfill()
                XCTAssertEqual(result, [1, 4, 7, 8])
            }
            
        }
    }
    
    #if DEBUG
    func testDebounceSimulatedDelay() {
        runTest(timeout: 2) { bag in
            let timer = SimulatedTimer()
            
            bag += overrideDisposableAsync(by: timer.disposableAsync)
            
            let signals: [(TimeInterval, Int)] = [
                (1, 3),
                (2, 4),
                (5, 5),
                (6, 6),
                (7, 7),
                (10, 8),
                ]
            
            let signal = ReadWriteSignal(1)
            
            for (time, value) in signals {
                bag += timer.schedule(at: time) { signal.value = value }
            }
            
            var result = [(TimeInterval, Int)]()
            bag += signal.debounce(2).atOnce().onValue {
                result.append((timer.time, $0))
            }
            
            signal.value = 2
            
            let e = expectation(description: "done")
            bag += timer.schedule(at: 100) {
                e.fulfill()
                XCTAssertEqual(result.map { $0.0 }, [0, 4, 9, 12])
                XCTAssertEqual(result.map { $0.1 }, [1, 4, 7, 8])
            }
        }
    }
    #endif

    func testThrottle() {
        runTest(timeout: 2) { bag in
            let signal = ReadWriteSignal(1)
            
            var result = [Int]()
            bag += signal.throttle(0.2).onValue {
                result.append($0)
            }
            
            signal.value = 2
            
            let signals: [(TimeInterval, Int)] = [
                (0.1, 3),
                (0.15, 4),
                (0.3, 5),
                (0.5, 6),
                (0.55, 7),
                (0.9, 8),
                (0.95, 9),
            ]
            
            for (time, value) in signals {
                Scheduler.main.async(after: time) {
                    signal.value = value
                }
            }

            let e = expectation(description: "done")
            Scheduler.main.async(after: 1.5) {
                e.fulfill()
                XCTAssertEqual(result, [2, 4, 5, 7, 8, 9])
            }
        }
    }
    
    #if DEBUG
    func testThrottleSimulatedDelay() {
        runTest(timeout: 2) { bag in
            let timer = SimulatedTimer()
            
            bag += overrideDisposableAsync(by: timer.disposableAsync)
            
            let signals: [(TimeInterval, Int)] = [
                (05, 3),
                (15, 4),
                (25, 5),
                (26, 6),
                (45, 7),
                (46, 8),
            ]
            
            let signal = ReadWriteSignal(1)
            
            for (time, value) in signals {
                bag += timer.schedule(at: time) { signal.value = value }
            }
            
            var result = [(TimeInterval, Int)]()
            bag += signal.throttle(10).onValue {
                result.append((timer.time, $0))
            }
            
            signal.value = 2

            let e = expectation(description: "done")
            bag += timer.schedule(at: 100) {
                e.fulfill()
                XCTAssertEqual(result.map { $0.0 }, [0, 10, 20, 30, 45, 55])
                XCTAssertEqual(result.map { $0.1 }, [2, 3, 4, 6, 7, 8])
            }
        }
    }
    #endif
}


extension XCTestCase {
    func runTest(timeout: TimeInterval = 1, function: (DisposeBag) -> ()) {
        let bag = DisposeBag()
        function(bag)
        waitForExpectations(timeout: amIBeingDebugged() ? 1000 : timeout) { _ in
            bag.dispose()
        }
    }
}

// A helper to easier simulat delays and verify timings in unit test.
final class SimulatedTimer {
    private var mutex = Mutex()
    private(set) var time: TimeInterval = 0
    private var count = 0
    private var queue = [() -> ()]()
    private var scheduledWork = [UUID: (time: TimeInterval, work: () -> ())]()
    private static var nextKey: Int = 0

    func schedule(at time: TimeInterval, execute work: @escaping () -> ()) -> Disposable {
        let key = UUID()
        mutex.protect {
            assert(time >= self.time)
            scheduledWork[key] = (time, work)
        }
        
        return Disposer {
            self.mutex.protect { self.scheduledWork[key] = nil }
        }
    }

    func disposableAsync(after delay: TimeInterval, execute work: @escaping () -> ()) -> Disposable {
        let d = schedule(at: time + delay, execute: work)
        mainQueue.async { self.release() }
        return d
    }
    
    func release() {
        mutex.lock()
        guard count == 0, let next = scheduledWork.sorted(by: { $0.value.time < $1.value.time }).first else {
            return mutex.unlock()
        }
        
        count += 1
        time = next.value.time
        scheduledWork[next.key] = nil
        mutex.unlock()
        
        //print("call", next)
        next.value.work()
        
        mutex.protect { count -= 1 }
        mainQueue.async { self.release() }
    }
}

