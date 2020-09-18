//
//  SignalTests.swift
//  FlowTests
//
//  Created by Hans Sjunnesson on 14/03/16.
//  Copyright © 2016 PayPal Inc. All rights reserved.
//

import XCTest
import Flow

class SignalTests: XCTestCase {
    func testNotifications() {
        let notificationName = "TestNotification"
        let bag = DisposeBag()
        let signal = NotificationCenter.default.signal(forName: NSNotification.Name(rawValue: notificationName))

        let expectation = self.expectation(description: "Signal notification")

        bag += signal.onValue { _ in
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: Notification.Name(rawValue: notificationName), object: nil)

        waitForExpectations(timeout: 10) { error in
            bag.dispose()
        }
    }

    func testSequenceTypeSignal() {
        let a = [1, 2, 3, 4, 5, 6]
        var b = [Int]()

        let bag = DisposeBag()

        let expectation = self.expectation(description: "Signal sent sequence")
        let signal = a.signal()

        bag += signal.onValue { v in
            b.append(v)

            if a == b { expectation.fulfill() }
        }

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testSignalDelay() {
        let e = self.expectation(description: "after delay")

        let bag = DisposeBag()
        bag += Signal(after: 0.1).onValue {
            assertMain()
            Scheduler.main.async(after: 0.1) {
                e.fulfill()
            }
        }

        waitForExpectations(timeout: 1) { error in
            bag.dispose()
        }

    }
    
    func testDebugSignal() {
        let values = [4, 5, 6]
        var debugMessages = [String]()
        
        let bag = DisposeBag()
        
        let expectation = self.expectation(description: "Signal sent sequence")
        expectation.expectedFulfillmentCount = 3
        let signal = values.signal()
        
        bag += signal.debug("debugMessage", printer: { message in
            debugMessages.append(message)
        }).onValue { _ in
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1) { error in
            bag.dispose()
        }
        
        let expectedStrings = [
            "initial",
            "event(value(4))",
            "event(value(5))",
            "event(value(6))",
            "event(end(nil))",
            "disposed"
        ]
        
        let allIsCorrect = zip(debugMessages, expectedStrings).reduce(true) { (result, tuple) -> Bool in
            let (actual, expected) = tuple
            return result && actual.hasSuffix(expected)
        }
        XCTAssertTrue(allIsCorrect)
    }

    func testDebugReadWriteSignal() {
        let readWriteSignal = ReadWriteSignal(0)
        let debuggedSignal = readWriteSignal.debug(printer: { _ in })
        let expectation = self.expectation(description: "Debugged signal sends a value")

        let disposable = debuggedSignal.onValue { _ in
            expectation.fulfill()
        }
        debuggedSignal.value = 5
        disposable.dispose()

        wait(for: [expectation], timeout: 1)
    }
}
