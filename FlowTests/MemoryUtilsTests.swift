//
//  MomoryUtilsTests.swift
//  FlowTests
//
//  Created by Emmanuel Garnier on 2017-10-02.
//  Copyright © 2017 iZettle. All rights reserved.
//

import XCTest
import Flow

class MemoryUtilsTests: XCTestCase {
    func testDeallocSignal() {
        final class Foo {}
        var object: Foo? = Foo()

        let bag = DisposeBag()
        let expectation = self.expectation(description: "object deallocated")

        bag += Flow.deallocSignal(for: object!).onValue {
            expectation.fulfill()
        }

        object = nil

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testNSObjectDeallocSignal() {
        var object: NSObject? = NSObject()

        let bag = DisposeBag()
        let expectation = self.expectation(description: "object deallocated")

        bag += object!.deallocSignal.onValue {
            expectation.fulfill()
        }

        Scheduler.main.async(after: 2) {
            object = nil
        }

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }
}
