//
//  PropertyTests.swift
//  FlowTests
//
//  Created by Hans Sjunnesson on 22/03/16.
//  Copyright © 2016 iZettle. All rights reserved.
//

import XCTest
import Flow


class PropertyTests: XCTestCase {

    func testHasInitialValue() {
        let property = ReadWriteSignal<Int>(1)
        XCTAssertEqual(property.value, 1)
    }
    
    func testSimpleProperty() {
        let bag = DisposeBag()
        let property = ReadWriteSignal<Int>(1)
        
        let expectation1 = expectation(description: "ReadWriteSignal should have 1")
        let expectation2 = expectation(description: "ReadWriteSignal should have 2")
        
        bag += property.onValue { v in
            switch v {
            case 1: expectation1.fulfill()
            case 2: expectation2.fulfill()
            default: return
            }
        }
        
        property.value = 1
        property.value = 2
        
        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }
    
    func testMultipleTriggers() {
        let bag = DisposeBag()
        let property = ReadWriteSignal<Int>(1)
        
        let expectation1 = expectation(description: "ReadWriteSignal should have 1")
        let expectation2 = expectation(description: "ReadWriteSignal should have 2")
        
        bag += property.onValue { v in
            if v == 1 { expectation1.fulfill() }
        }

        bag += property.onValue { v in
            if v == 2 { expectation2.fulfill() }
        }

        property.value = 1
        property.value = 2
        
        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }


}
