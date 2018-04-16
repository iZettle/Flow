//
//  TestUtilities.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2015-09-30.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation
import XCTest

#if DEBUG
@testable import Flow
#else
import Flow
var futureUnitTestAliveCount: Int32 = 0
var queueItemUnitTestAliveCount: Int32 = 0
var futureQueueUnitTestAliveCount: Int32 = 0
#endif

enum TestError: Error {
    case fatal
}

var isMain: Bool { return Thread.current == Thread.main }

func clearAliveCounts() {
    assert(OSAtomicCompareAndSwap32(futureUnitTestAliveCount, 0, &futureUnitTestAliveCount))
    assert(OSAtomicCompareAndSwap32(queueItemUnitTestAliveCount, 0, &queueItemUnitTestAliveCount))
    assert(OSAtomicCompareAndSwap32(futureQueueUnitTestAliveCount, 0, &futureQueueUnitTestAliveCount))
}

func printAliveCounts() {
    print("futureUnitTestAliveCount", futureUnitTestAliveCount)
    print("futureQueueUnitTestAliveCount", futureQueueUnitTestAliveCount)
    print("queueItemUnitTestAliveCount", queueItemUnitTestAliveCount)
}

let shouldCheckAliveCounts = true

extension XCTestCase {
    func waitForAliveCountReachingZeroUsingTimeout(_ timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        //printAliveCounts()
        
        if futureUnitTestAliveCount == 0 && queueItemUnitTestAliveCount == 0 && futureQueueUnitTestAliveCount == 0 {
            completion(true)
        } else if timeout <= 0 {
            completion(false)
        } else {
            RunLoop.main.run(until: Date())
            Scheduler.main.async(after: 0.1) {
                self.waitForAliveCountReachingZeroUsingTimeout(timeout - 0.1, completion: completion)
            }
        }
    }
    
    func testFuture<T>(repeatCount: Int = 0, timeout: TimeInterval = 0.5, allDoneDelay: TimeInterval = 0.3, cancelAfterDelay: TimeInterval? = nil, cancelOn cancelScheduler: Scheduler = .main, future: () -> Future<T>) {
        let timeout = amIBeingDebugged() ? 1000 : timeout
        //        let timeout = timeout + 100
        //        let allDoneDelay = allDoneDelay + 100
        var count = repeatCount
        for _ in 0...repeatCount {
            let e = self.expectation(description: "Wait for future to complete")
            //XCTAssertTrue(waitForAliveCountReachingZeroUsingTimeout(5))
            autoreleasepool {
                let f = future().always {
                    
                    func done(_ success: Bool) {
                        if !success {
                            print("Not all futures where released")
                        }
                        XCTAssertTrue(success, "Not all futures where released")
                        if count == 0 {
                            printAliveCounts()
                        }
                        count -= 1
                        e.fulfill()
                    }
                    
                    if shouldCheckAliveCounts {
                        self.waitForAliveCountReachingZeroUsingTimeout(allDoneDelay, completion: done)
                    } else {
                        done(true)
                    }
                }
                if let cancelDelay = cancelAfterDelay {
                    cancelScheduler.async(after: cancelDelay) {
                        //print("will cancel")
                        f.cancel()
                    }
                }
            }
        }
        
        waitForExpectations(timeout: timeout + (shouldCheckAliveCounts ? allDoneDelay + 0.5 : 0)) { error in
            //            if let e = error {
            //                XCTFail("Expectation Failed with error: \(e)");
            //            }
        }
    }
}

extension FutureQueue {
    func enqueueValue<Value: Equatable>(_ value: Value, delay: TimeInterval = 0, assertValue: Bool = true) -> Future<Value> {
        let f = enqueue {
            Future(value).delay(by: delay)
        }
        if assertValue {
            return f.assertValue(value)
        } else {
            return f
        }
    }
}

extension XCTestCase {
    func testQueue<T>(repeatCount: Int = 0, timeout: TimeInterval = 0.5, allDoneDelay: TimeInterval = 0.3, scheduleOn: Scheduler = .current, function: (FutureQueue<Int>) -> Future<T>) {
        testFuture(repeatCount: repeatCount, timeout: timeout, allDoneDelay: allDoneDelay) {
            function(FutureQueue(resource: 4711, executeOn: scheduleOn))
        }
    }
    
    func testQueueResult<T: Equatable, Result>(_ result: [T], repeatCount: Int = 0, timeout: TimeInterval = 0.5, allDoneDelay: TimeInterval = 0.1, scheduleOn: Scheduler = .current, function: @escaping (FutureQueue<Int>, @escaping (T) -> ()) -> Future<Result>) {
        testQueue(repeatCount: repeatCount, timeout: timeout, allDoneDelay: allDoneDelay) { (queue: FutureQueue<Int>) -> Future<Result> in
            var r = [T]()
            return function(FutureQueue(resource: 4711, executeOn: scheduleOn), { (v: T) -> () in print("append \(v)"); r.append(v) }).always { print("testQueueResult \(r)"); XCTAssertTrue(r.elementsEqual(result), "\(r) != \(result)") }
        }
    }
}


public let mainQueue = DispatchQueue.main
public let backgroundQueue = DispatchQueue.global(qos: .default)
extension Scheduler {
    static let globalBackground = Scheduler(queue: backgroundQueue)
}

func assertMain() { assert(isMain, "Not on main queue" ) }
func assertBackground() { assert(!isMain, "Not on background queue" ) }


extension Future {
    @discardableResult
    func assertMain() -> Future {
        return always { 
            if (!isMain) {
                print("")
            }
            XCTAssertTrue(isMain, "Not on main queue" )
        }
    }
    
    @discardableResult
    func assertBackground() -> Future {
        return always { 
            if (isMain) {
                print("")
            }
            XCTAssertFalse(isMain, "Not on background queue")
        }
    }
    
    @discardableResult
    func assert(on scheduler: Scheduler) -> Future {
        return always {
            XCTAssertTrue(scheduler.isExecuting, "Not executing on correct scheduler: \(scheduler == .main ? "main" : "background")")
        }
    }
    
    @discardableResult
    func assertNoValue() -> Future {
        return onValue { _ in XCTAssertTrue(false, "Invalid reception of value") }
    }
    
    @discardableResult
    func assertError() -> Future {
        return onError { e in XCTAssertTrue(true, "Did not receive error") }
    }
    
    @discardableResult
    func assertNoError() -> Future {
        return onError { e in XCTAssertTrue(false, "Did not expect error: \(e)") }
    }
    
    @discardableResult
    func assertNoCancel() -> Future {
        return onCancel { XCTAssertTrue(false, "Should not cancel") }
    }
    
    @discardableResult
    func assertValue() -> Future {
        return assertNoError().assertNoCancel()
    }
    
    @discardableResult
    func assertValue(_ value: Value, isSame: @escaping (Value, Value) -> Bool) -> Future {
        return assertValue().onValue { (v: Value) -> Void in XCTAssertTrue(isSame(v, value)) }
    }
    
    @discardableResult
    func assertDelay(_ delay: TimeInterval) -> Future {
        let date = Date()
        return always { XCTAssertTrue(-date.timeIntervalSinceNow > delay, "Delay was not long enough: \(-date.timeIntervalSinceNow)") }
    }
}

extension Future where Value: Equatable {
    @discardableResult
    func assertValue(_ value: Value) -> Future {
        return assertValue().onValue { (v: Value) -> Void in XCTAssertEqual(v, value) }
    }
}

func amIBeingDebugged() -> Bool {
    var info = kinfo_proc()
    var mib : [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride
    let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    assert(junk == 0, "sysctl failed")
    return (info.kp_proc.p_flag & P_TRACED) != 0
}
