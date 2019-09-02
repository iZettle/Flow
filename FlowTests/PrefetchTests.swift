//
//  PrefetchTests.swift
//  Flow
//
//  Created by Martin on 2019-07-25.
//  Copyright © 2019 iZettle. All rights reserved.
//

import XCTest
import Flow

private func prefetch<E: SignalProvider>(fetch: @escaping (_ isPrefetching: Bool) -> E) -> Signal<E.Value> {
    return Signal { callback -> Disposable in
        let bag = DisposeBag()
        bag += fetch(true).take(first: 1).onValueDisposePrevious { value in
            callback(value)
            return fetch(false).onValue(callback)
        }
        return bag
    }
}

class PrefetchTests: XCTestCase {
    func testBasicPrefetch() {
        let data = ReadWriteSignal(5)
        let values = data//.startWith(1...5)

        let bag = DisposeBag()
        let signal = prefetch { isPrefetching -> Signal<Int> in
            print("---- prefetch callback", isPrefetching)
            return values.atOnce().atValue {
                print("----- isPrefetching", isPrefetching, $0)
                }.map {
                    min(isPrefetching ? 10 : 20, $0)
                }.plain()
        }

        var count = 0
        bag += signal.onValue { val in
            print("----- val", val)
            count += val
        }

        data.value = 100

        XCTAssertEqual(count, 5 + 5 + 20)
    }
}
