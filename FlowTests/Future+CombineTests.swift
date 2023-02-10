//
//  Future+CombineTests.swift
//  FlowTests
//
//  Created by Martin Andonoski on 2023-02-09.
//  Copyright © 2023 PayPal Inc. All rights reserved.
//

import XCTest
@testable import Flow
#if canImport(Combine)
import Combine

@available(iOS 13.0, macOS 10.15, *)
final class Future_CombineTests: XCTestCase {

    var bag = CancelBag()
    
    override func tearDownWithError() throws {
        bag.empty()
        
        try super.tearDownWithError()
    }
    
    func testGetValue() {
        let callbacker = Callbacker<Result<Int>>()
        let flowFuture = Flow.Future(callbacker: callbacker)
        
        let combineFuture = flowFuture.toCombineFuture
        let expectation = self.expectation(description: "Result expected")

        bag += combineFuture.sink { completion in
            if case .failure = completion {
                XCTFail("Expected to succeed")
            }
        } receiveValue: { value in
            XCTAssertEqual(value, 1)
            expectation.fulfill()
        }

        callbacker.callAll(with: .success(1))
        wait(for: [expectation], timeout: 1)
    }
    
    func testErrorOut() {
        let callbacker = Callbacker<Result<Int>>()
        let flowFuture = Flow.Future(callbacker: callbacker)
        
        let combineFuture = flowFuture.toCombineFuture
        let expectation = self.expectation(description: "Failiure expected")
        
        bag += combineFuture.sink { completion in
            switch completion {
            case .failure(let error):
                XCTAssertEqual(error as! TestError, .fatal)
                expectation.fulfill()
            case .finished:
                XCTFail("Expected to fail")
            }
        } receiveValue: { value in
            XCTFail("Expected to fail")
        }

        callbacker.callAll(with: .failure(TestError.fatal))
        wait(for: [expectation], timeout: 1)
    }

}

#endif
