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
        let publisher = signal.asAnyPublisher
        
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
        let publisher = signal.asAnyPublisher

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
        let publisher = signal.asAnyPublisher

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

    func testPublisherCancellation() {
        let callbacker = Callbacker<Event<Int>>()
        let signal = FiniteSignal(callbacker: callbacker)
        let publisher = signal.publisher

        let completed = expectation(description: "Completed")
        completed.isInverted = true
        let published = expectation(description: "Published")
        published.expectedFulfillmentCount = 1

        bag += publisher.sink { completion in
            completed.fulfill()
        } receiveValue: { value in
            published.fulfill()
        }

        callbacker.callAll(with: .value(1))
        publisher.bag.cancel()
        callbacker.callAll(with: .value(2))
        callbacker.callAll(with: .end)

        wait(for: [completed, published], timeout: 1)

    }

    func testAutosink() {
        let completed = expectation(description: "Completed")
        let valueSunk = expectation(description: "Value sunk")
        valueSunk.expectedFulfillmentCount = 3

        let autocancel1 = expectation(description: "1")
        let autocancel2 = expectation(description: "2")
        let autocancel3 = expectation(description: "3")

        bag += (1...3).publisher.autosink { completion in
            completed.fulfill()
        } receiveValue: { value in
            valueSunk.fulfill()

            var subBag = self.bag.subset()

            switch value {
            case 1: subBag += { autocancel1.fulfill() }
            case 2: subBag += { autocancel2.fulfill() }
            case 3: subBag += { autocancel3.fulfill() }
            default: XCTFail("Unexpected value out of range")
            }

            return subBag.asAnyCancellable
        }

        wait(for: [valueSunk, autocancel1, autocancel2, autocancel3, completed], timeout: 1)
    }

}

#endif
