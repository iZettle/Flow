//
//  CallbackerTests.swift
//  FlowTests
//
//  Created by Hans Sjunnesson on 14/03/16.
//  Copyright © 2016 iZettle. All rights reserved.
//

import XCTest
import Flow


class CallbackerTests: XCTestCase {
    func testOrderedCallbacks() {
        let bag = DisposeBag()
        
        let countedExpectation = expectation(description: "All callbacks counted")
        let completedExpectation = expectation(description: "Call completed")
        
        let callbacker = OrderedCallbacker<Int, String>()
        
        let numbers = Array(0...1000)
        var results = [Int]()
        
        XCTAssertTrue(callbacker.isEmpty)
        
        for i in numbers {
            bag += callbacker.addCallback({ (value: String) -> () in
                if results.count != i { XCTFail("Incorrect order in callbacks") }
                results.append(i)
                
                if results.count == numbers.count {
                    countedExpectation.fulfill()
                }
            }, orderedBy: i)
        }

        XCTAssertFalse(callbacker.isEmpty)

        callbacker.callAll(with: "foo").onValue {
            completedExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }
    
    func testCallbacker() {
        let bag = DisposeBag()
        let completedExpectation = expectation(description: "Call completed")
        let callbacker = Callbacker<Int>()
        let value = 42
        
        XCTAssertTrue(callbacker.isEmpty)
        
        bag += callbacker.addCallback { v in
            if v == value {
                completedExpectation.fulfill()
            }
        }

        XCTAssertFalse(callbacker.isEmpty)

        callbacker.callAll(with: value)
        
        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }
    
    func testCallbackerIsEmpty() {
        let bag = DisposeBag()
        let callbacker = Callbacker<()>()
        XCTAssertTrue(callbacker.isEmpty)
        bag += callbacker.addCallback { }
        XCTAssertFalse(callbacker.isEmpty)
        bag.dispose()
        XCTAssertTrue(callbacker.isEmpty)
        bag += callbacker.addCallback { }
        bag += callbacker.addCallback { }
        XCTAssertFalse(callbacker.isEmpty)
        bag.dispose()
        XCTAssertTrue(callbacker.isEmpty)
    }

}

