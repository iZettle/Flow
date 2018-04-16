//
//  FutureQueueTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2015-11-05.
//  Copyright © 2015 iZettle. All rights reserved.
//

import XCTest
import Flow


class FutureQueueTests: FutureTest {
    func testSimpleQueue() {
        testQueue { queue in
            queue.enqueueValue(1)
        }
    }

    func testQueue() {
        testQueue { queue in
            join(queue.enqueueValue(1), queue.enqueueValue(2)).assertValue((1, 2), isSame: ==)
        }
    }

    func testQueueAbort() {
        testQueueResult([1, 3], timeout: 2, allDoneDelay: 1) { (queue, add) -> Future<()> in
            queue.enqueueValue(1, delay: 0.2).onValue(add).always { print("a") }
            Scheduler.main.async(after: 0.4) { print("b") ; queue.abortQueuedOperations(with: TestError.fatal) }
            queue.enqueueValue(2, delay: 0.6, assertValue: false).onValue(add).always { print("c") }
            Scheduler.main.async(after: 0.6) { queue.enqueueValue(3).onValue(add).always { print("d") } }
            return queue.didBecomeEmpty.future.always { print("e") }.delay(by: 0.8)
        }
    }

    func testQueueAbortCancel() {
        testQueueResult([Int](), timeout: 2, allDoneDelay: 1) { (queue, add) -> Future<()> in
            queue.enqueue { Future(4).delay(by: 0.2).assertNoError().assertNoValue()  }
            queue.abortQueuedOperations(with: TestError.fatal)
            return queue.isEmptySignal.atOnce().filter { $0 }.toVoid().future
        }
    }

    func testQueueAbortAndClose() {
        testQueueResult([1], timeout: 1.5, allDoneDelay: 1) { (queue, add) -> Future<()> in
            queue.enqueueValue(1, delay: 0.01).onValue(add)
            Scheduler.main.async(after: 0.7) { queue.abortQueuedOperations(with: TestError.fatal, shouldCloseQueue: true) }
            Scheduler.main.async(after: 0.9) { queue.enqueueValue(2, assertValue:false).onValue(add).assertError() }
            return queue.didBecomeEmpty.future.delay(by: 1.2)
        }
    }

    
    func testQueueAsync() {
        testQueueResult([1, 2], timeout: 1.5, allDoneDelay: 1) { (queue, add) -> Future<()> in
            Scheduler.main.async(after: 0.1) { print("A"); queue.enqueue { Future(1, delay: 0.2).onValue(add) } }
            Scheduler.main.async(after: 0.2) { print("B"); queue.enqueue { Future(2).onValue(add) } }
            return queue.didBecomeEmpty.future.always { print("End") }
        }
    }
    
    
    func testBatchQueue() {
        testQueue { queue in
            join(
                queue.enqueueValue(1),
                queue.enqueueBatch { q in
                    XCTAssertEqual(queue.resource, q.resource)
                    return q.enqueueValue(2)
                },
                queue.enqueueValue(3)
            ).assertValue((1, 2, 3), isSame: ==)
        }
    }

    func testQueueSchedulingBackMain() {
        testQueue(repeatCount: 100, timeout: 5, scheduleOn: .concurrentBackground) { queue in
            queue.enqueue { () -> Future<Int> in
                assertConcurrentBackground()
                return Future(1)
            }.assertMain()
        }
    }

    func testQueueSchedulingMainBack() {
        testQueue(repeatCount: 100, timeout: 5, scheduleOn: .main) { queue in
            Future().flatMap(on: .concurrentBackground) { () -> Future<Int> in
                assertConcurrentBackground()
                return queue.enqueue { () -> Future<Int> in
                    assertMain()
                    return Future(1)
                }.onValue { _ in
                    assertConcurrentBackground()
                }
            }
        }
    }

    func testQueueRepeat() {
        testFuture(timeout: 5) { () -> Future<()> in
            let queue = FutureQueue()
            var val = 0
            return queue.enqueue {
                val += 1
                return Future(val)
            }.repeatAndCollect(repeatCount: 3).onValue {
                XCTAssertEqual($0, [1, 2, 3, 4])
            }.toVoid()
        }
    }

    func testBatchQueueRepeat() {
        testFuture(timeout: 5) { () -> Future<()> in
            let queue = FutureQueue()
            return Future(self)
                .flatMap { _ in
                    queue.enqueueBatch { queue in
                        return queue.enqueue { return Future(queue).delay(by: 0.1) }
                    }
                }
                .delay(by: 0.1)
                .repeatAndCollect(repeatCount: 4).toVoid()
        }
    }

    func testQueueConcurrent() {
        testFuture(timeout: 5) { () -> Future<()> in
            let queue = FutureQueue(maxConcurrentCount: 5)
            var maxConcurrentCount: Int = 0
            var concurrentCount: Int = 0
            var values = [Int]()
            for i in 1...100 {
                queue.enqueue { () -> Future<Int> in
                    concurrentCount += 1
                    maxConcurrentCount = max(maxConcurrentCount, concurrentCount)
                    return Future(i).delay(by: 0.001).onValue { val in
                        concurrentCount -= 1
                        values.append(val)
                        print(values.count)
                    }
                }
                
            }
            
            return queue.didBecomeEmpty.future.onValue {
                XCTAssertEqual(maxConcurrentCount, 5)
                XCTAssertEqual(concurrentCount, 0)
                XCTAssertEqual(values.count, 100)
            }
        }
    }

    func testQueueConcurrentCancel() {
        testFuture(timeout: 5, allDoneDelay: 5) { () -> Future<()> in
            let queue = FutureQueue(maxConcurrentCount: 5)
            var maxConcurrentCount: Int = 0
            var concurrentCount: Int = 0
            var values = [Int]()
            for i in 1...100 {
                let f = queue.enqueue { () -> Future<Int> in  

                    concurrentCount += 1
                    maxConcurrentCount = max(maxConcurrentCount, concurrentCount)
                    return Future(i).delay(by: 0.001).onValue { val in
                        values.append(val)
                        print("onValue", i, values.count)
                    }.onCancel {
                        print("cancel", i, values.count)
                    }.always {
                        concurrentCount -= 1
                    }
                }
                
                if i % 2 == 0 {
                    f.cancel()
                }
            }
            
            return queue.didBecomeEmpty.future.onValue {
                XCTAssertEqual(maxConcurrentCount, 5)
                XCTAssertEqual(concurrentCount, 0)
                XCTAssertEqual(values.count, 50)
                _ = queue
            }
        }
    }
    
    func recursive(repeatCount: Int) -> Future<()> {
        return Future().delay(by: 0.1).always(printAliveCounts).flatMap { repeatCount == 0 ? Future() : self.recursive(repeatCount: repeatCount-1) }
    }
    
    func testRecursive() {
        testFuture(timeout: 1) {
            recursive(repeatCount: 4)
        }
    }

}

class RefCount {
    init() { print("RefCount init") }
    deinit { print("RefCount deinit") }
}

extension FutureQueue {
    func exe1() -> Future<()> {
        return enqueue { Future() }
    }
}
