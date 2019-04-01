//
//  UIViewSignalTests.swift
//  Flow
//
//  Created by Emmanuel Garnier on 2016-11-21.
//  Copyright © 2016 iZettle. All rights reserved.
//

import XCTest
import Flow

#if canImport(UIKit)

import UIKit

class UIViewSignalTests: XCTestCase {
    func testSubviewSignalAdd() {
        let window = UIWindow()
        let rootView = UIView()
        let view1 = UIView()
        let view2 = UIView()
        let view3 = UIView()

        window.addSubview(rootView)
        rootView.addSubview(view1)
        rootView.addSubview(view2)

        let bag = DisposeBag()

        let expectation = self.expectation(description: "Signal sent sequence")
        let signal = rootView.subviewsSignal

        bag += signal.atOnce().onValue { (subviews) in
            if subviews == [view1, view2, view3] { expectation.fulfill() }
        }

        rootView.addSubview(view3)

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testSubviewSignalRemove() {
        let window = UIWindow()
        let rootView = UIView()
        let view1 = UIView()
        let view2 = UIView()
        let view3 = UIView()

        window.addSubview(rootView)
        rootView.addSubview(view1)
        rootView.addSubview(view2)
        rootView.addSubview(view3)

        let bag = DisposeBag()

        let expectation = self.expectation(description: "Signal sent sequence")
        let signal = rootView.subviewsSignal

        bag += signal.atOnce().onValue { (subviews) in
            if subviews == [view1, view2] { expectation.fulfill() }
        }

        view3.removeFromSuperview()

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testSubviewSignalMoveWithinSameView() {
        let window = UIWindow()
        let rootView = UIView()
        let view1 = UIView()
        let view2 = UIView()
        let view3 = UIView()

        window.addSubview(rootView)
        rootView.addSubview(view1)
        rootView.addSubview(view2)
        rootView.addSubview(view3)

        let bag = DisposeBag()

        let expectation = self.expectation(description: "Signal sent sequence")
        let signal = rootView.subviewsSignal

        bag += signal.atOnce().onValue { (subviews) in
            if subviews == [view3, view1, view2] { expectation.fulfill() }
        }

        rootView.sendSubviewToBack(view3)

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testSubviewSignalMoveToDifferentTreeView() {
        let window = UIWindow()
        let window2 = UIWindow()
        let rootView = UIView()
        let view1 = UIView()
        let view2 = UIView()
        let view3 = UIView()

        window.addSubview(rootView)
        rootView.addSubview(view1)
        view1.addSubview(view2)
        window2.addSubview(view3)

        let bag = DisposeBag()

        let expectation = self.expectation(description: "Signal sent sequence")
        let signal = view1.subviewsSignal

        bag += signal.atOnce().onValue { (subviews) in
            print(subviews.reduce("after\n") { $0 + "\($1) \n" })
            if subviews == [view2, view3] { expectation.fulfill() }
        }

        view1.addSubview(view3)

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testAllDescendantsSignalAdd() {
        let window = UIWindow()
        let rootView = UIView()
        let view1 = UIView()
        let view2 = UIView()
        let view3 = UIView()
        let view4 = UIView()

        window.addSubview(rootView)
        rootView.addSubview(view1)
        view2.addSubview(view3)
        view2.addSubview(view4)

        let bag = DisposeBag()

        let expectation = self.expectation(description: "Signal sent sequence")
        let signal = window.allDescendantsSignal

        bag += signal.atOnce().onValue { (subviews) in
            if subviews == [rootView, view1, view2, view3, view4] { expectation.fulfill() }
        }

        view1.addSubview(view2)

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testAllDescendantsSignalRemove() {
        let window = UIWindow()
        let rootView = UIView()
        let view1 = UIView()
        let view2 = UIView()
        let view3 = UIView()
        let view4 = UIView()

        window.addSubview(rootView)
        rootView.addSubview(view1)
        view1.addSubview(view2)
        view2.addSubview(view3)
        view2.addSubview(view4)

        let bag = DisposeBag()

        let expectation = self.expectation(description: "Signal sent sequence")
        let signal = window.allDescendantsSignal

        bag += signal.atOnce().onValue { subviews in
            print(subviews.reduce("after\n") { $0 + "\($1) \n" })
            if subviews == [rootView, view1] { expectation.fulfill() }
        }

        view2.removeFromSuperview()

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testAllDescendantsSignalMove() {
        let window = UIWindow()
        let rootView = UIView()
        let view1 = UIView()
        let view2 = UIView()
        let view3 = UIView()
        let view4 = UIView()

        window.addSubview(rootView)
        rootView.addSubview(view1)
        view1.addSubview(view2)
        view2.addSubview(view3)
        view2.addSubview(view4)

        let bag = DisposeBag()

        let expectation = self.expectation(description: "Signal sent sequence")
        let signal = window.allDescendantsSignal

        bag += signal.atOnce().onValue { (subviews) in
            if subviews == [rootView, view1, view4, view2, view3] { expectation.fulfill() }
        }

        view1.insertSubview(view4, at: 0)

        waitForExpectations(timeout: 10) { _ in
            bag.dispose()
        }
    }

    func testKVO() {
        let object = UIButton()

        let signal = object.signal(for: \.isSelected)

        object.isSelected = true

        let bag = signal.distinct().onValue { _ in
            signal.value = true
        }

        object.isSelected = false

        XCTAssertTrue(object.isSelected)

        bag.dispose()
    }

    class TestClass: NSObject {
        @objc dynamic var string: String?
    }

    func testOptionalKVO() {
        let object = TestClass()
        object.string = "initial"

        let signal = object.signal(for: \.string)

        let bag = signal.distinct().onValue { _ in
            object.string = "called"
        }

        object.string = nil

        XCTAssertEqual(object.string, "called")

        bag.dispose()
    }
}

#endif
