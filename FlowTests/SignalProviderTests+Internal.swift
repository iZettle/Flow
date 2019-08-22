//
//  SignalProviderTests+Internal.swift
//  FlowTests
//
//  Created by Carl Ekman on 2019-05-03.
//  Copyright © 2019 iZettle. All rights reserved.
//

import XCTest
@testable import Flow

class SignalProviderTests_Internal: XCTestCase {

    fileprivate func test<I, O: Equatable>(_ input: [I], expected: [O], initial: I, transform: (FiniteSignal<I>) -> FiniteSignal<O>) {
        var result = [O]()
        _ = transform(input.internalTestingSignal(with: initial)).collect().onValue { result = $0 }
        XCTAssertEqual(result, expected)
    }

    func testReduceWithInitialValue() {
        test([1, 2, 3, 4], expected: [11, 13, 16, 20], initial: 10) {
            $0.reduce(0, combine: +)
        }
    }
}

internal extension Sequence {
    /// Returns a signal that will immedialty signals all `self`'s elements and then terminate.
    /// It also has an initial value. This should only be used for facilitating tests.
    func internalTestingSignal(with initial: Iterator.Element) -> FiniteSignal<Iterator.Element> {
        return FiniteSignal(onEventType: { callback in
            callback(.initial(initial))
            self.forEach { callback(.event(.value($0))) }
            callback(.event(.end))
            return NilDisposer()
        })
    }
}
