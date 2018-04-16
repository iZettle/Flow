//
//  DelegateTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2018-02-07.
//  Copyright © 2018 iZettle. All rights reserved.
//

import XCTest
import Flow

class DelegateTests: XCTestCase {
    func testDelegate() {
        let d = Delegate<Int, Bool>()
        
        XCTAssertNil(d.call(5))

        let bag = DisposeBag()
        
        bag += d.set { $0 > 5 }

        XCTAssertEqual(d.call(10), true)
        XCTAssertEqual(d.call(1), false)

        bag += d.set { $0 < 5 }

        XCTAssertEqual(d.call(10), false)
        XCTAssertEqual(d.call(1), true)
        
        bag.dispose()

        XCTAssertNil(d.call(5))
    }

    func testDelegateOnSet() {
        var onSetCount = 0
        var onSetDisposeCount = 0
        
        let d = Delegate<Int, Bool> { callback in
            XCTAssertEqual(callback(10), onSetCount == 0)
            XCTAssertEqual(callback(1), onSetCount != 0)
            
            onSetCount += 1
            return Disposer {
                onSetDisposeCount += 1
            }
        }
        
        XCTAssertNil(d.call(5))
        
        let bag = DisposeBag()

        XCTAssertEqual(onSetCount, 0)
        XCTAssertEqual(onSetDisposeCount, 0)

        bag += d.set { $0 > 5 }
        
        XCTAssertEqual(onSetCount, 1)
        XCTAssertEqual(onSetDisposeCount, 0)

        XCTAssertEqual(d.call(10), true)
        XCTAssertEqual(d.call(1), false)
        
        bag += d.set { $0 < 5 }
        
        XCTAssertEqual(onSetCount, 2)
        XCTAssertEqual(onSetDisposeCount, 1)
        
        bag.dispose()

        XCTAssertEqual(onSetCount, 2)
        XCTAssertEqual(onSetDisposeCount, 2)

    }
}
