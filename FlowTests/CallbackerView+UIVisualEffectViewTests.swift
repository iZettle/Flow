//
//  Callbacker+UIVisualEffectViewTests.swift
//  FlowTests
//
//  Created by Sam Pettersson on 2020-08-13.
//  Copyright © 2020 iZettle. All rights reserved.
//

import Foundation
import XCTest
import Flow

class CallbackerViewUIVisualEffectViewTests: XCTestCase {
    func testNotCrashing() {
        let effectView = UIVisualEffectView()
        let bag = DisposeBag()
        
        let expectation = self.expectation(description: "did trigger bounds")
        
        bag += effectView.signal(for: \.bounds).atOnce().onValue { _ in
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10)
    }
}
