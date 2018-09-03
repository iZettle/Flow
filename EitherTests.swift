//
// Created by Niil Öhlin on 2018-09-03.
// Copyright (c) 2018 iZettle. All rights reserved.
//

import Foundation
import XCTest
import Flow

class EitherTests: XCTestCase {
    func testHashable() {
        let string = "some string"
        let left: Either<String, Int> = .left(string)
        let right: Either<String, Int> = .right(string.hashValue)

        XCTAssertNotEqual(left.hashValue, right.hashValue)
    }
}
