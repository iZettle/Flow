//
//  ReadSignal+CombineTests.swift
//  FlowTests
//
//  Created by Martin Andonoski on 2023-02-08.
//  Copyright © 2023 PayPal Inc. All rights reserved.
//

import XCTest
#if DEBUG
@testable import Flow
#else
import Flow
#endif
import Foundation
#if canImport(Combine)
import Combine

@available(iOS 13.0, macOS 10.15, *)
final class Signal_CombineTests: XCTestCase {
    
    var bag = CancelBag()

    override func tearDownWithError() throws {
        bag.empty()
        
        try super.tearDownWithError()
    }
    
    func testValueReceived() {
        let signal = ReadWriteSignal("1")
        let publisher = signal.toAnyPublisher()
        
        let valueExpectation = self.expectation(description: "value should fire")
        
        bag += publisher.sink { completion in
            XCTFail("Should not complete")
        } receiveValue: { value in
            XCTAssertEqual(value, "2")
            valueExpectation.fulfill()
        }
        
        signal.value = "2"
        
        wait(for: [valueExpectation], timeout: 1)
    }
    
    func testEndReceived() {
        let callbacker = Callbacker<Event<Int>>()

        let signal = FiniteSignal(callbacker: callbacker)
        let publisher = signal.toAnyPublisher()
        
        let endExpectation = self.expectation(description: "signal should end")
        
        bag += publisher.sink { completion in
            switch completion {
            case .finished:
                endExpectation.fulfill()
            case .failure:
                XCTFail("Should not fail")
            }
        } receiveValue: { value in
            XCTFail("Cancelable should have ended")
        }

        callbacker.callAll(with: .end)
        callbacker.callAll(with: .value(1))
        
        wait(for: [endExpectation], timeout: 1)
    }
    
    func testErrorReceived() {
        let callbacker = Callbacker<Event<Int>>()

        let signal = FiniteSignal(callbacker: callbacker)
        let publisher = signal.toAnyPublisher()
        
        let endExpectation = self.expectation(description: "signal should end with error")
        bag += publisher.sink { completion in
            switch completion {
            case .finished:
                XCTFail("Should fail")
            case .failure(let error):
                XCTAssertEqual(error as! TestError, .fatal)
                endExpectation.fulfill()
            }
        } receiveValue: { value in
            XCTFail("Cancellable should have ended")
        }

        callbacker.callAll(with: .end(TestError.fatal))
        callbacker.callAll(with: .value(1))

        wait(for: [endExpectation], timeout: 1)
    }

}

#endif
