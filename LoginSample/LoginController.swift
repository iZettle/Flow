//
//  LoginController.swift
//  LoginSample
//
//  Created by Måns Bernhardt on 2018-04-12.
//  Copyright © 2018 iZettle. All rights reserved.
//

import UIKit
import Flow

struct User {
    var email: String
}

enum LoginError: Error {
    case invalidUser
    case dismissed
}

class LoginController: UIViewController {
    let emailField: UITextField
    let passwordField: UITextField
    let loginButton: UIButton
    let cancelButton: UIBarButtonItem
    
    func runLogin() -> Future<User> {
        return Future { completion in // Completion to call with the result  
            let bag = DisposeBag() // Resources to keep alive while executing 
            
            // Make sure to signal at once to set up initial enabled state
            bag += self.enableLogin.atOnce().bindTo(self.loginButton, \.isEnabled)  
            
            // If button is tapped, initiate potentially long running login request
            bag += self.loginButton.onValue {
                self.login()
                    .performWhile { 
                        // Show spinner during login request
                        self.showSpinnerOverlay() 
                    }.onErrorRepeat { error in
                        // If login fails with an error show an alert...
                        // ...and retry the login request if the user chose to
                        self.showRetryAlert(for: error)
                    }.onValue { user in
                        // If login is successful, complete runLogin() with the user
                        completion(.success(user))
                    }
            }
            
            // If cancel is tapped, complete runLogin() with an error
            bag += self.cancelButton.onValue { 
                completion(.failure(LoginError.dismissed))
            }
            
            return bag // Return a disposable to dispose once the future completes
        }
    }
    
    var enableLogin: ReadSignal<Bool> {
        return combineLatest(emailField, passwordField)
            .map { email, password in
                email.contains("@") && password.count > 4
            }
    }
    
    func login() -> Future<User> {
        return Future { 
            let email = self.emailField.text ?? ""
            guard email.hasPrefix("valid") else {
                throw LoginError.invalidUser
            }
            return User(email: email)
        }.delay(by: 1) // Simulate a long running request by delaying by 1s
    }

        
    func showSpinnerOverlay() -> Disposable {
        let spinner = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
        spinner.frame = self.view.bounds
        spinner.backgroundColor = UIColor(white: 0, alpha: 0.2)
        spinner.startAnimating()
        
        parent?.view.addSubview(spinner)
        return Disposer {
            spinner.removeFromSuperview()
        }
    }

    func showRetryAlert(for error: Error) -> Future<Bool> {
        return Future { completion in
            let alert = UIAlertController(title: "Failed to login", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in completion(.success(true)) })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(.failure(error)) })
            
            self.present(alert, animated: true, completion: nil)

            return Disposer {
                alert.dismiss(animated: true, completion: nil)
            }
        }
    }
    
    init() {
        emailField = UITextField()
        emailField.placeholder = "valid@email.com"
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        
        passwordField = UITextField()
        passwordField.placeholder = "password"
        passwordField.isSecureTextEntry = true
        passwordField.autocapitalizationType = .none

        loginButton = UIButton(type: .system)
        loginButton.setTitle("Login", for: .normal)
        
        cancelButton = UIBarButtonItem()
        cancelButton.title = "Cancel"
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
    
    override func loadView() {
        let stack = UIStackView(arrangedSubviews: [emailField, passwordField, loginButton])
        stack.alignment = .center
        stack.axis = .vertical
        stack.distribution = .equalSpacing
        stack.spacing = 10
        
        navigationItem.leftBarButtonItem = cancelButton
        
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.95, alpha: 1)

        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        self.view = view
        
        emailField.becomeFirstResponder()
    }
}



