//
//  AppDelegate.swift
//  LoginSample
//
//  Created by Måns Bernhardt on 2018-04-12.
//  Copyright © 2018 iZettle. All rights reserved.
//

import UIKit
import Flow


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    let bag = DisposeBag()

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        let vc = UIViewController()
        
        let loginButton = UIButton(type: UIButtonType.system)
        loginButton.setTitle("Show Login Controller", for: .normal)
        
        let stack = UIStackView(arrangedSubviews: [loginButton])
        stack.alignment = .center
        
        vc.view = stack
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window

        window.backgroundColor = .white
        window.rootViewController = vc
        window.makeKeyAndVisible()
        
        bag += loginButton.onValue {
            let login = LoginController()
            let nc = UINavigationController(rootViewController: login)
            vc.present(nc, animated: true, completion: nil)
            
            login.runLogin().onValue { user in
                print("Login succeeded with user", user)
            }.onError { error in
                print("Login failed with error",  error)
            }.always {
                nc.dismiss(animated: true, completion: nil)
            }
        }

        return true
    }
}

