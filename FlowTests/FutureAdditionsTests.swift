import XCTest
import Flow

class FutureAdditionsTests: XCTestCase {

    func testFlatMapErrorTransformsFirstErrorInToSecondError() {
        let expectation = self.expectation(description: "Error called")
        expectation.assertForOverFulfill = true

        Future<Int>() {
                throw StubError.originalError
            }
            .flatMapError { _ in
                throw StubTransformedError.transformedError
            }
            .onValue {
                XCTFail("Expected error, got value \($0)")

                expectation.fulfill()
            }
            .onError {
                let error = $0 as? StubTransformedError
                XCTAssertEqual(error, StubTransformedError.transformedError)

                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 1)
    }

    func testFlatMapErrorWhenFirstWorkerFailsAndSecondSucceedsReturnsExpectedValue() {
        let firstWorker = StubWorker(stubWork: { _ in
            throw StubError.originalError
        })

        let successfulWorker = StubWorker(stubWork: { _ in
            return 2
        })

        let expectation = self.expectation(description: "Got value")
        expectation.assertForOverFulfill = true

        firstWorker.work()
            .flatMapError { _ in successfulWorker.work() }
            .onValue {
                XCTAssertEqual(2, $0)

                expectation.fulfill()
            }
            .onError {
                XCTFail("Unexpected error: \($0)")

                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 10)
    }

    func testFlatMapErrorWhenFirstWorkerSucceedsReturnsExpectedValue() {
        let firstWorker = StubWorker(stubWork: { _ in
            return 2
        })

        let secondWorker = StubWorker(stubWork: { _ in
            return 3
        })

        let expectation = self.expectation(description: "Got value")
        expectation.assertForOverFulfill = true

        firstWorker.work()
            .flatMapError { _ in secondWorker.work() }
            .onValue {
                XCTAssertEqual(2, $0)

                expectation.fulfill()
            }
            .onError {
                XCTFail("Unexpected error: \($0)")

                expectation.fulfill()
            }

        self.waitForExpectations(timeout: 10)
    }
}

fileprivate final class StubWorker {

    var stubWork: (Int) throws -> Int

    init(
        stubWork: @escaping (Int) throws -> Int
    ) {
        self.stubWork = stubWork
    }

    func work() -> Future<Int> {
        return Future<Int>(1)
            .map {
                return try self.stubWork($0)
            }
            .delay(by: 0.1)
    }
}


fileprivate enum StubError: Error, Equatable {
    case originalError
}

fileprivate enum StubTransformedError: Error, Equatable {
    case transformedError
}