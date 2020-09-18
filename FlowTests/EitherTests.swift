//
// Created by Niil Öhlin on 2018-09-03.
// Copyright © 2018 PayPal Inc. All rights reserved.
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
