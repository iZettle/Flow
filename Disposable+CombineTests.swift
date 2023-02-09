//
//  Disposable+CombineTests.swift
//  Flow
//
//  Created by Carl Ekman on 2023-02-09.
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
final class Disposable_CombineTests: XCTestCase {

    var bag = CancelBag()

    override func tearDownWithError() throws {
        bag.cancel()

        try super.tearDownWithError()
    }

    func testCancellingDisposable() {
        let disposed = expectation(description: "Disposed")

        let disposer = Disposer { disposed.fulfill() }
        disposer.asAnyCancellable.cancel()

        wait(for: [disposed], timeout: 1)
    }

    func testCancelBag() {
        var bag = CancelBag()

        let cancelled1 = expectation(description: "Cancelled 1")
        let cancelled2 = expectation(description: "Cancelled 2")
        let cancelled3 = expectation(description: "Cancelled 3")

        bag += { cancelled1.fulfill() }
        bag += { cancelled2.fulfill() }
        bag += { cancelled3.fulfill() }

        bag.cancel()
        XCTAssertFalse(bag.isEmpty)

        wait(for: [cancelled1, cancelled2, cancelled3], timeout: 1)
        XCTAssertFalse(bag.isEmpty)

        bag.empty()
        XCTAssertTrue(bag.isEmpty)
    }

    func testCancellingDisposeBag() {
        let bag = DisposeBag()

        let cancelled1 = expectation(description: "Cancelled 1")
        let cancelled2 = expectation(description: "Cancelled 2")
        let cancelled3 = expectation(description: "Cancelled 3")

        bag += { cancelled1.fulfill() }
        bag += { cancelled2.fulfill() }
        bag += { cancelled3.fulfill() }

        bag.asAnyCancellable.cancel()

        wait(for: [cancelled1, cancelled2, cancelled3], timeout: 1)
    }

    func testDisposeBagToCancelBag() {
        let disposeBag = DisposeBag()

        let disposed = expectation(description: "Disposed")

        disposeBag += { disposed.fulfill() }

        var cancelBag = CancelBag(disposable: disposeBag)
        cancelBag.empty()

        wait(for: [disposed], timeout: 1)
    }

    func testCancelPublisherSink() {
        let callbacker = Callbacker<Event<Int>>()

        let signal = FiniteSignal(callbacker: callbacker)
        let publisher = signal.toAnyPublisher()

        let cancelled = expectation(description: "Cancelled")

        bag += { cancelled.fulfill() }

        publisher.sink { _ in
            XCTFail("Did not expect completion")
        } receiveValue: { _ in
            XCTFail("Did not expect value")
        }.store(in: &bag)

        bag.cancel()
        callbacker.callAll(with: .value(1))
        callbacker.callAll(with: .end(TestError.fatal))

        wait(for: [cancelled], timeout: 1)
    }

}

#endif
