//
//  RecursiveTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2016-11-17.
//  Copyright © 2016 iZettle. All rights reserved.
//

import XCTest
import Flow

class RecursiveTests: XCTestCase {
    func testRecursive() {
        var count = 0
        var object: Optional = NSObject()
        weak var ref = object!

        XCTAssertNotNil(ref)

        do {
            let innerObject = object!

            let myFunc: (Int) -> () = recursive { arg, myFunc in
                guard arg > 0 else { return }
                count += 1
                myFunc(arg-1)
                _ = innerObject // Keep a ref
            }
            
            XCTAssertNotNil(ref)
            object = nil
            XCTAssertNotNil(ref)
            
            myFunc(5)
            XCTAssertEqual(count, 5)

            XCTAssertNotNil(ref)
        }

        XCTAssertNil(ref)
    }

    func testRecursiveFactorial() {
        let fact: (Int) -> Int = recursive { n, fact in
            return n > 1 ? n*(fact(n - 1) ?? 0) : 1
        }
        
        XCTAssertEqual(fact(1), 1)
        XCTAssertEqual(fact(2), 2)
        XCTAssertEqual(fact(3), 6)
        XCTAssertEqual(fact(4), 24)
    }
    
    func testRecursiveFibonacci() {
        let fibs: (Int) -> Int = recursive { n, fibs in
            if n == 0 {
                return 0
            } else if n == 1{
                return 1
            }
            
            return (fibs(n - 1) ?? 0) + (fibs(n - 2) ?? 0)
        }
        
        XCTAssertEqual(fibs(1), 1)
        XCTAssertEqual(fibs(2), 1)
        XCTAssertEqual(fibs(3), 2)
        XCTAssertEqual(fibs(4), 3)
        XCTAssertEqual(fibs(5), 5)

    }
    
    func testRecursiveNoArgs() {
        var count = 5
        let update: () -> Int = recursive { update in
            count -= 1
            return count >= 0 ? ((update() ?? 0) + 1) : 0
        }
        
        XCTAssertEqual(update(), 5)
    }
}
