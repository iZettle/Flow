*This document is largely copied from https://github.com/iZettle/Flow/issues/11*

***Built for Swift and Apple platforms***
Flow was designed for Swift and Apple platforms, and take advantage of their strength.

RxSwift originally came from C# a quite different language.

***Evolved internally to solve real problems***
Even though Flow has been around for many years, it has had the benefit of being developed in private, hence we have several times made large changes to improve ergonomics in APIs, performance, and making it up to date with latest updates to Swift etc.

RxSwift has been in the wild for a while, a benefit in itself, but also a disadvantage as it's hard to change early design decisions.  

***A better concurrency story***
Flow works hard to make your code easier to reason about. One great example is how callbacks are being scheduled:

```swift
// called from main
combineLatest(signalA, signalB).map { a, b in
 // guaranteed to also be called from main
}
```

So in the above example, no matter on what scheduler/thread/queue signalA and signalB are signaling their values, the map callback is guaranteed to be called on the same scheduler it was set up from.

This is not true for RxSwift where you often have to protect yourself from unknown signals by explicitly moving to schedulers (`.observeOn(MainScheduler.instance)`).

***More consistent types***
Flow have four signals types, Signal, ReadSignal, ReadWriteSignal and FiniteSignal. The type of the signal let you know a lot about it and what to expect from it. These types are first class, and all transformation are aware of these and converts them accordingly:

```swift
let rw = ReadWriteSignal(4711)
let r = rw.map { $0 * 2 } // ReadSignal<Int>, mapping will drop write access
let s = r.filter { $0%2 == 0 } // Signal<Int>, filter will drop read access
let f = s.take(first: 2) // FiniteSignal<Int>, take might terminate the signal
```

RxFlow's addition of traits seems like an after-construction, and traits are not enforced throughout. Often you have to fall back to the internal observable and then you have lost the benefit of explicit single types.

***Future vs Signal***
Flow sees signals and futures as distinct types with different semantics. A signal abstract the observation of events over time, whereas a future abstract a result that might not yet be available.

So a future will execute no matter if anyone is interested in the result or not. You can compare this to Apple APIs such as running an animation where if you provide a completion block or not will not affect if the animation is run. A future will also remember its result so you can access it even after a future has completed.

In comparison,  a signal will not start producing values until someone starts to listen to them. Applying transforms etc. won't start anything.

The overlap of transformations that you would like to apply for signal in comparison to future are quite few, so the benefit of sharing implementing is small. And due to the difference in semantics and behaviors, sharing implementation would not make much sense anyway.

RxSwift uniforms the future and signal abstractions into the observable type. We think this makes it harder for the user to reason about their code.

**More lightweight syntax**

I just grab an example from RxSwift using three text fields:

```swift
var a: UITextField
var b: UITextField
var c: UITextField
```

Which is implemented like:

```swift
// c = a + b
let sum = Observable.combineLatest(a.rx.text.orEmpty, b.rx.text.orEmpty) { a, b in
  (Int(a) ?? 0, Int(b) ?? 0)
}

 // bind result to UI
 sum.map { a, b in
     "\(a + b)"
  }.bind(to: c.rx.text)
  .disposed(by: disposeBag)
```

Where as the same expressed in Flow will become:

```swift
// c = a + b
let sum = combineLatest(a, b).map { a, b in
  (Int(a) ?? 0, Int(b) ?? 0)
}

// bind result to UI
bag += sum.map { a, b in
  "\(a + b)"
 }.atOnce().bindTo(c)
```

***Simpler implementation***

We think Flow has an implementation that is easier than RxSwift, making it easier to understand, debug and extend it.

***Summary***

Flow works hard to make your code easier to read, maintain and reason about. Flow does not try to do everything but is instead focusing on solving the most common problems. It has a more pragmatic API design making it easier to onboard new people.
