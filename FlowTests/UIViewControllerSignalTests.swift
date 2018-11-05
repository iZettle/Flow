//
//  UIViewControllerSignalTests.swift
//  Flow
//
//  Created by João D. Moreira on 2018-11-05.
//  Copyright © 2018 iZettle. All rights reserved.
//

import XCTest
import Flow

#if canImport(UIKit)

import UIKit

class UIViewControllerSignalTests: XCTestCase {
    let window = UIWindow()
    let bag = DisposeBag()

    func testLoadView() {
        let viewController = UIViewController()

        let expectation = self.expectation(description: "UIViewController's view didLoad")
        bag += viewController.viewDidLoadSignal.onValue {
            expectation.fulfill()
        }

        viewController.loadViewIfNeeded()

        waitForExpectations(timeout: 1)
    }

    func testAppearView() {
        let navController = UINavigationController()
        window.rootViewController = navController
        window.isHidden = false

        let viewController = UIViewController()

        let viewWillAppearExpectation = self.expectation(description: "UIViewController's view will appear")
        bag += viewController.viewWillAppearSignal.onValue { _ in
            viewWillAppearExpectation.fulfill()
        }

        let viewDidAppearExpectation = self.expectation(description: "UIViewController's view did appear")
        bag += viewController.viewDidAppearSignal.onValue { _ in
            viewDidAppearExpectation.fulfill()
            self.window.rootViewController = nil
        }

        let viewWillDisappearExpectation = self.expectation(description: "UIViewController's view will disappear")
        bag += viewController.viewWillDisappearSignal.onValue { _ in
            viewWillDisappearExpectation.fulfill()
        }

        let viewDidDisappearExpectation = self.expectation(description: "UIViewController's view did disappear")
        bag += viewController.viewDidDisappearSignal.onValue { _ in
            viewDidDisappearExpectation.fulfill()
        }

        navController.pushViewController(viewController, animated: true)

        let orderedExpectations = [viewWillAppearExpectation, viewDidAppearExpectation,
                                   viewWillDisappearExpectation, viewDidDisappearExpectation]
        wait(for: orderedExpectations, timeout: 5, enforceOrder: true)
    }

    func testLayoutSubviews() {
        let viewController = UIViewController()

        let viewWillLayoutSubviews = self.expectation(description: "UIViewController subview will layout")
        bag += viewController.viewWillLayoutSubviewsSignal.onValue {
            viewWillLayoutSubviews.fulfill()
        }

        let viewDidLayoutSubviews = self.expectation(description: "UIViewController subview did layout")
        bag += viewController.viewDidLayoutSubviewsSignal.onValue {
            viewDidLayoutSubviews.fulfill()
        }

        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        wait(for: [viewWillLayoutSubviews, viewDidLayoutSubviews], timeout: 5, enforceOrder: true)
    }
}

#endif
