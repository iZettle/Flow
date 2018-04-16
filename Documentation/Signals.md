# Signals

APIs that want to notify the user of changes are common. Apple provides several of those and they come in many forms, such as notifications, delegates, target/action and KVO. What is common to them all is they will notify you of changes over time. In Flow, event-based APIs are represented by signals.

```swift
let statusSignal: Signal<Status> // Might be a notification, KVO or something else
```

Since a signal hides the logic behind and provides a uniform API, you can not only use them interchangeably but you can also easily pass them around.

By calling `onValue()` on a signal you will start listening on new changes until you dispose the returned disposable:

```swift
let disposable = statusSignal.onValue { status in
  // will be called every time a new status is signaled
}
...
disposable.dispose() // Stop listening for events
```

You can construct new signals with modified behavior by applying transformations on existing signals.

```swift
let isEnabled = statusSignal.map { $0.isOpen } // Signal<Bool>
let didEnable = isEnabled.filter { $0 }.toVoid() // Signal<Void>
```

Signals could also be combined:

```swift
let latestEmailAndPassword = combineLatest(emailField, passwordField)
```

And as transformations return new signals we can easily chain signals.

```swift
let bag = DisposeBag()
bag += combineLatest(emailField, passwordField)
  .map { email, password in
    email.isValidEmail && password.isValidPassword
  }.atOnce().bindTo(button, \.isEnabled)
```

## Constructing signals

To construct your own signal for listing on events you call a `Signal<T>` initializer with a closure that will call you back with a callback once someone starts to listen on the signal.

```swift
extension NotificationCenter {
  func signal(forName name: Notification.Name?) -> Signal<Notification> {
    return Signal { callback in // will be called once someone starts listening
      // Set up callback to be called for new notifications
      let observer = self.addObserver(forName: name, using: callback)
      return Disposer { // make sure to clean-up once the listener is removed
        self.removeObserver(observer)
      }
    }
  }
}
```

## Producing values

You could also produce your own values. Here the `Callbacker` type comes in handy as it encapsulates the complexity of registration and de-registration of callbacks:

```swift
let callbacker = Callbacker<Bool>()
...
// Register a callback, and deregister it when the returned disposable is disposed.
bag += callbacker.addCallback { isEnabled in ... }

// Call all registered callbacks with the value `true`
callbacker.callAll(true)
```

Given a `Callbacker` it is easy to create a signal that will register itself for callbacks:

```swift
let isEnabled = Signal(callbacker: callbacker)
```

## Four different kinds of signals

Flow provides four different kinds of signals with different characteristics:

- ***Signal***: A plain signal with no current value
- ***ReadSignal***: A signal with a readonly current value
- ***ReadWriteSignal***: A signal with a mutable current value
- ***FiniteSignal***: A signal with no current value that can terminate

The choice of signal type helps to express your intent in your APIs.  

### `Signal<T>`

`Signal<T>` is the most basic signal. It has no concept of a current value. It is useful to model e.g. notification changes or button presses.

You can convert any of the other signal types to a plain `Signal<T>` by applying  the `plain()` transform:

```swift
let signal: Signal<String> = textField.plain()
```

### `ReadSignal<T>`

A `ReadSignal<T>` has the notion of a current value that you could access using the read-only `value` property. More commonly, the `atOnce()` transform is used, which signals this current value immediately upon setting up a listener:

```swift
bag += textField.atOnce().onValue {
  // will be called immediately with the text fields current value
  // and after that with any changes to this value.
}
```

This is a very useful way to share code between initialization and update handling.

You can create new `ReadSignal`s using some of its initializers:

```swift
let readSignal = ReadSignal(capturing: self.value, callbacker: callbacker)
```

Or by upgrading a plain `Signal<T>` by using one of the `readable()` transforms:

```swift
let readSignal = Signal(callbacker: callbacker).readable(capturing: self.value)
```

If you have a `ReadWriteSignal<T>`, it can be downgraded to `ReadSignal<T>` using the `readOnly()` transformation:

```swift
let internalState = ReadWriteSignal(false) // For convenience
var state: ReadSignal<Bool> { // Should not be exposed as mutable
  return internalState.readOnly()
}
```

### `ReadWriteSignal<T>`

A `ReadWriteSignal<T>` has a mutable `value` property that will emit its current value when `value` is updated.

Typically you construct new instances by providing an initial value:

```swift
let signal = ReadWriteSignal(true)
```

But you can also upgrade a `ReadSignal<T>` to a `ReadWriteSignal<T>` using `writable()`:

```swift
let signal = readSignal.writable { self.value = $0 }
```

### `FiniteSignal<T>`

A `FinteSignal<T>` can terminate by signaling an end event, whereafter no more events will be signaled and any hold resources will be disposed. A finite signal is using the `Event<T>` type to signal its events:

```swift
enum Event<Value> {
  case value(Value)
  case end(Error?)
}
```

Some transformations such as `take()` will return a `FiniteSignal<T>` to indicate that it might terminate.

### Applying transformations on read and read-write signals

When applying transformations on read and read-write signals, they will sometimes lose their writable and/or readable properties. E.g. applying a `filter()` transformation can no longer guarantee to provide a current value and hence returns a plain signal `Signal<T>`. Similarly `map()` being a one-way transformation will lose its writable property. However, applying `map()` on read signal will return another read signal where the transform is applied to the current value as well.

### Combining signals

Most combining transforms such as `combineLatest()` requires all the participating signals to be of the same type to be able to derive the returned type. This means that you sometimes have to add or remove readability and finiteness when combining several signals of different types.  
 
## Signal provider

`SignalProvider` allows conforming types to provide a default signal. This makes it more convenient to work with types such as `UIControl`s as you can apply signal transform directly on the instance itself:

```swift
extension UITextField: SignalProvider { ... }
...
bag += textField.map { $0.isValidPassword }.onValue { isEnabled = $0 }
```

`CoreSignal` the base of `Signal`, `ReadSignal` etc. also conforms to `SignalProvider`, and in Flow, all signal transforms are implemented as extensions on `SignalProvider`:

```swift
extension SignalProvider {
  func map<T>(_ transform: @escaping (Value) -> T) -> CoreSignal<Kind.DropWrite, T>
}
```

## Reading marble diagrams

The documentation of many signals transforms includes marble diagrams to help understand what will happen over time. Typically they show several timelines with values at the top being the values before the transform and the values at the bottom the values after. E.g. a `filter()` marble diagram might look like:

```
0)---1----2----3---|
     |    |    |
+---------------------------+
| filter { v in v.isOdd() } |
+---------------------------+
     |         |
-----1---------3---|
```

Here `0)` indicates what happens with a current value if any. For `filter()`, any current value is lost, hence applying `filter()` on a read signal will return a plain signal. We can also see that only odd values are forwarded, hence even values are filtered out.

## Binding signals to values

For convenience and to better state your intent Flow provides `bindTo()` helpers for most common type of bindings. So instead of writing:

```swift
bag += isEnabled.onValue { button.isEnabled = $0 }
bag += isEnabled.onValue { readWriteSignal.value = $0 }
```

You can use `bindTo()` variants instead:

```swift
bag += isEnabled.bindTo(button, \.isEnabled) // using key path
bag += isEnabled.bindTo(readWriteSignal)
```

## UIKit extensions

To make it more convenient to work with UIKit, Flow conforms several  `UIControl`s to `SignalProvider` to allow applying transforms directly on those:

```swift
bag += emailField.map { $0.isValidEmail }.bindTo(button, \.isEnabled)
bag += button.onValue(login)
```

## Key value observing

Flow makes it easy to work with key value observing (KVO):

```swift
let frameSignal = view.signal(for: \.frame) // ReadWriteSignal<CGRect>
bag += frameSignal.onValue { ... }
```

## Key paths

Using key paths you can also more conveniently transform your signals:

```swift
let heightSignal = frameSignal[\.size.height] // ReadWriteSignal<CGFloat>
```

## Scheduling

For most `Signal` APIs accepting a callback closure, there is a defaulted `scheduler` parameter you could explicitly override to schedule the provided callback closure. The default scheduler is set to the current scheduler used when calling the API.

```swift
signal.map {
  // Will be called back on the current scheduler at the time `map` was called. 
}
signal.map(on: .main) {
  // Will be called back on the main queue no matter from where `map` was called.
}
```

You can create your custom schedulers to e.g. wrap dispatch queues.

```swift
let imageProcessing = Scheduler(label: "image processing")

// call from main
imageSignal.map(on: imageProcessing) { image in
   image.scaledAndDecorated() // called in background
}.onValue { image in
  // called on main
}
```

It seldom makes sense to provide a concurrent scheduler for signal transforms as it might change the order of events.
