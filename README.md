<img src="https://github.com/iZettle/Flow/blob/master/flow-logo.png?raw=true" height="140px" />

[![Platforms](https://img.shields.io/badge/platform-%20iOS%20|%20macOS%20|%20tvOS%20|%20linux-gray.svg)](https://img.shields.io/badge/platform-%20iOS%20|%20macOS%20|%20tvOS%20|%20linux-gray.svg)
[![Carthage Compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Swift Package Manager Compatible](https://img.shields.io/badge/SwiftPM-Compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)
![Xcode version](https://img.shields.io/badge/Xcode-16.0.0-green)

Modern applications often contain complex asynchronous flows and life cycles. Flow is a Swift library aiming to simplify building these by solving three main problems:

- **[Lifetime management](Documentation/LifetimeManagement.md)**: Managing long-living resources.
- **[Event handling](Documentation/Signals.md)**: Signaling and observing events over time.
- **[Asynchronous operations](Documentation/Futures.md)**: Handle results that might not yet be available.
- **[Comparison to RxSwift](Documentation/RxSwiftComparison.md)**: Why you might choose Flow over something like RxSwift.

Flow was carefully designed to be:

- **Easy to use**: APIs are carefully designed for readability and ease of use.
- **Pragmatic**: Evolved and designed to solve real problems.
- **Composable**: Types compose nicely making building complex flows easy.
- **Performant**: Flow has been highly tuned for performance.
- **Concurrent**: Flow is thread safe and uses a scheduler model that is easy to reason about.
- **Extensible**: Flow was designed to be extensible.
- **Strongly typed**: Flow makes use of Swift strong typing to better express intention.
- **Correct**: Backed by hundreds of unit tests and field tested for years.

## Example usage

In Flow the `Disposable` protocol is used for lifetime management:

```swift
extension UIView {
  func showSpinnerOverlay() -> Disposable {
    let spinner = ...
    addSubview(spinner)
    return Disposer {
      spinner.removeFromSuperview()
    }
  }
}

let disposable = view.showSpinnerOverlay()

disposable.dispose() // Remove spinner
```

`Disposable` resources can be collected in a common `DisposeBag`:
```swift
let bag = DisposeBag() // Collects resources to be disposed together

bag += showSpinnerOverlay()
bag += showLoadingText()

bag.dispose() // Will dispose all held resources
```

And the `Signal<T>` type is used for event handling. Signals are provided by standard UI components:

```swift
let bag = DisposeBag()

// UIButton provides a Signal<()>
let loginButton = UIButton(...)

bag += loginButton.onValue {
  // Log in user when tapped
}

// UITextField provides a ReadSignal<String>
let emailField = UITextField(...)
let passwordField = UITextField(...)

// Combine and transform signals
let enableLogin: ReadSignal<Bool> = combineLatest(emailField, passwordField)
  .map { email, password in
    email.isValidEmail && password.isValidPassword
  }

// Use bindings and key-paths to update your UI on changes
bag += enableLogin.bindTo(loginButton, \.isEnabled)
```

And finally the `Future<T>` type handles asynchronous operations:

```swift
func login(email: String, password: String) -> Future<User> {
  let request = URLRequest(...)
  return URLSession.shared.data(for: request).map { data in
    User(data: data)
  }
}

login(...).onValue { user in
  // Handle successful login
}.onError { error in
  // Handle failed login
}
```

These three types come with many extensions that allow us to compose complex UI flows:

```swift
class LoginController: UIViewController {
  let emailField: UITextField
  let passwordField: UITextField
  let loginButton: UIButton
  let cancelButton: UIBarButtonItem

  var enableLogin: ReadSignal<Bool> { /* Introduced above */ }
  func login(email: String, password: String) -> Future<User> { /* Introduced above */ }
  func showSpinnerOverlay() -> Disposable { /* Introduced above */ }

  // Returns future that completes with true if user chose to retry
  func showRetryAlert(for error: Error) -> Future<Bool> { ... }

  // Will setup UI observers and return a future completing after a successful login
  func runLogin() -> Future<User> {
    return Future { completion in // Complete the future by calling this with your value
      let bag = DisposeBag() // Collect resources to keep alive while executing

      // Make sure to signal at once to set up initial enabled state
      bag += enableLogin.atOnce().bindTo(loginButton, \.isEnabled)  

      // If button is tapped, initiate potentially long running login request using input
      bag += combineLatest(emailField, passwordField)
        .drivenBy(loginButton)
        .onValue { email, password in
          login(email: email, password: password)
            .performWhile {
              // Show spinner during login request
              showSpinnerOverlay()
            }.onErrorRepeat { error in
              // If login fails with an error show an alert...
              // ...and retry the login request if the user chooses to
              showRetryAlert(for: error)
            }.onValue { user in
              // If login is successful, complete runLogin() with the user
              completion(.success(user))
        }
      }

      // If cancel is tapped, complete runLogin() with an error
      bag += cancelButton.onValue {
        completion(.failure(LoginError.dismissed))
      }

      return bag // Return a disposable to dispose once the future completes
    }
  }
}
```

## Requirements

- Xcode `9.3+`
- Swift 4.1
- Platforms:
  * iOS `9.0+`
  * macOS `10.11+`
  * tvOS `9.0+`
  * watchOS `2.0+`
  * Linux

## Installation

#### [Carthage](https://github.com/Carthage/Carthage)

```shell
github "iZettle/Flow" >= 1.0
```

#### [Cocoa Pods](https://github.com/CocoaPods/CocoaPods)

```ruby
platform :ios, '9.0'
use_frameworks!

target 'Your App Target' do
  pod 'FlowFramework', '~> 1.0'
end
```

#### [Swift Package Manager](https://github.com/apple/swift-package-manager)

```swift
import PackageDescription

let package = Package(
  name: "Your Package Name",
  dependencies: [
      .Package(url: "https://github.com/iZettle/Flow.git",
               majorVersion: 1)
  ]
)
```

## Introductions

Introductions to the main areas of Flow can be found at:

- [Lifetime management](Documentation/LifetimeManagement.md)
- [Event handling](Documentation/Signals.md)
- [Asynchronous operations](Documentation/Futures.md)

To learn even more about available functionality you are encouraged to explore the source files that are extensively documented. Code-completion should also help you to discover many of the transformations available on signals and futures.

## Learn more

To learn more about the design behind Flow's APIs we recommend reading the following articles. They go more into depth about why Flow's types and APIs look and behave the way they do and give you some insights into how they are implemented:

- [Introducing Flow](https://medium.com/izettle-engineering/introducing-flow-42de51988aea)
- [Deriving Signals](https://medium.com/izettle-engineering/deriving-signal-2adb8687e9bf)
- [Deriving Future](https://medium.com/izettle-engineering/deriving-future-607aea9abdee)
- [Expanding on Signals](https://medium.com/izettle-engineering/expanding-on-signals-ad25daee4d64)

And to learn how other frameworks can be built using Flow:

- [Introducing Presentation](https://medium.com/izettle-engineering/introducing-presentation-presenting-ui-made-easy-134d3fbe9311)
- [Introducing Form](https://medium.com/izettle-engineering/introducing-form-layout-styling-and-event-handling-b668d09bb4e6)

## Frameworks built on Flow

If your target is iOS, we highly recommend that you also checkout these frameworks that are built on top of Flow:

- **[Presentation](https://github.com/izettle/presentation)** - Formalizing presentations from model to result
- **[Form](https://github.com/izettle/form)** - Layout, styling, and event handling

## Field tested

Flow was developed, evolved and field-tested over the course of several years, and is pervasively used in [iZettle](https://izettle.com)'s highly acclaimed point of sales app.

## Collaborate

You can collaborate with us on our Slack workspace. Ask questions, share ideas or maybe just participate in ongoing discussions. To get an invitation, write to us at [iz-apps-platform-ios@paypal.com](mailto:iz-apps-platform-ios@paypal.com)
