//
//  FutureCompleteEarlyTests.swift
//  FlowTests
//
//  Created by Niil Öhlin on 2019-04-09.
//  Copyright © 2019 iZettle. All rights reserved.
//

import Foundation
import XCTest
import Flow

class CompleteEarlyTests: XCTestCase {

    func testCompleteEarly() {
        let asyncFuture = Future<String> { completion in
            completion(.success("completed normally"))
            return NilDisposer()
        }.delay(by: 1)

        var result: String = "not completed"
        asyncFuture.onValue {
            result = $0
        }

        asyncFuture.unsafeCompleteEarly(.success("completed early"))

        XCTAssertEqual(result, "completed early")
    }

    func testCompleteEarly_cancelsFuture() {
        let shouldNotRun = expectation(description: "should not be fulfilled")
        shouldNotRun.isInverted = true
        let asyncFuture = Future<String>("completed normally").delay(by: 0.1).onValue { _ in
            shouldNotRun.fulfill()
        }

        var result: String = "not completed"
        asyncFuture.onValue {
            result = $0
        }

        asyncFuture.unsafeCompleteEarly(.success("completed early"))

        wait(for: [shouldNotRun], timeout: 0.2)
        XCTAssertEqual(result, "completed early")
    }
}
