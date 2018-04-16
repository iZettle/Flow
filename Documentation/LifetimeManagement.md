# Lifetime Management

In Flow, lifetime management refers to the handling of for how long a resource is kept alive. This becomes especially important when working with closures, as they, in turn, capture and keep resources alive. Instead of weakly capturing those resources, Flow advocates the use of explicit disposing of resources. At first, this might seem like adding a lot of extra work, but once you adopt it in your application, your code will be much easier to reason about.

## Disposable

In Flow, the `Disposable` protocol is the standard way of handling clean-up after something is done. The protocol only exposes one method `dispose()` to be called to perform clean-up:

```swift
protocol Disposable {
  func dispose()
}
```

The most basic concrete implementation of `Disposable` is the `Disposer` type that just takes a closure that will be called once being disposed:

```swift
let disposer = Disposer { removeObserver(...) }
```

Flow also provides the `DisposeBag` that helps collecting `Disposable`s that should all be disposed at once:

```swift
let bag = DisposeBag()
bag += Disposer { removeObserver(...) }
bag += { removeObserver(...) } // or just add a closure
...
bag.dispose()
```

It is quite common that you also want to add an inner bag to an existing bag:

```swift
let innerBag = bag.innerBag()
```

Concrete implementations of `Disposable`s are reference types that will dispose themselves once there are no longer any references to them.

## Delegate

`Signal`s and `CallBacker`s are both useful for registering and de-registering callbacks. However, these can only handle a one-way communication. If you want to provide an argument that affects the result, you are back to using explicit closure properties with the risk of retain cycles. The `Delegate` helper was designed to address this. It is much like Apple's delegate APIs, but for just one method at a time and using closures instead of protocol conformances:

```swift
var cellForIndex = Delegate<TableIndex, UITableViewCell>()

// Set the delegate. Any previous set delegate will be released
// Once the returned Disposable is being disposed the delegate is un-set.
bag += cellForIndex.set { index in return UITableViewCell(...) }

// Ask the delegate for a value given some argument
let cell = cellForIndex.call(index)
```
