//
//  EventListenerTests.swift
//  FlowTests
//
//  Created by Måns Bernhardt on 2018-05-14.
//  Copyright © 2018 PayPal Inc. All rights reserved.
//

import XCTest
import Flow

class EventListenerTests: XCTestCase {
    func testHasEnablableEventListeners() {
        let listeners: [Listener] = [(false, false), (true, false), (false, true), (true, true)].map {
            let l = Listener()
            l.isEnabled = $0
            l.hasEventListeners = $1
            return l
        }

        XCTAssertEqual(listeners.map { $0.isEnabled }, [false, true, false, true])

        let d = listeners.disableActiveEventListeners()

        XCTAssertEqual(listeners.map { $0.isEnabled }, [false, true, false, false])

        d.dispose()

        XCTAssertEqual(listeners.map { $0.isEnabled }, [false, true, false, true])
    }
}

class Listener: HasEventListeners, Enablable {
    var isEnabled = false
    var hasEventListeners = false
}

extension Array: HasEnablableEventListeners where Element: HasEventListeners & Enablable {
    public var enablableEventListeners: [Enablable & HasEventListeners] { return self }
}
