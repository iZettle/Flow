//
//  SignalTests.swift
//  FlowTests
//
//  Created by Hans Sjunnesson on 14/03/16.
//  Copyright © 2016 iZettle. All rights reserved.
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
}
