# Futures

When building applications interacting with a user, a goal is to keep the application responsive at all times. It is thus important to not perform long-running operations that will block the UI. This is one reason why many APIs used in UI intensive applications are asynchronous. Being asynchronous means that the caller will not block while executing an operation, but instead, the API will call the user back when the result is available.

A common reason for an API to be asynchronous is that it models access to external services. These services often end up accessing some hardware. As most hardware have much longer latencies than the main CPU, it does make sense to use the CPU for other work while awaiting the result. External services are also often unreliable by nature, which means that they might fail. So it is common that many asynchronous APIs need to be able to report those failures.

## Introducing `Future<T>`

Flow abstracts the idea of an asynchronous operation and encapsulates it into the `Future<T>` type. A `Future<T>` represents a future result, a result that might take time to asynchronously produce. This result could either be a success  or a failure, represented by the `Result<T>` type:

```swift
enum Result<Value> {
  case success(Value)
  case failure(Error)
}
```

Instances of the `Future<T>` type can be passed around without any need to know the origin or details of the operation nor having to drag along any of its dependencies. As a future runs its operation only once, it means that it might already be completed by the time you receive an instance of it. However, this should not affect any logic or any functionality added to futures.

Another benefit of encapsulating operations in a generic future type is that functionality added to it can be applied to many different kinds of asynchronous operations.

## Constructing a future

To construct a new future for an asynchronous operation you call a `Future<T>` initializer with a closure that will call you back with a completion callback to be called once the operation is done. You also return a `Disposable` for cleanup that will be disposed once the operation is done or if the future is being canceled.

```swift
extension URLSession {
  func data(at url: URL) -> Future<Data> {
    return Future { completion in
      let task = dataTask(with: url) { data, _, error in
        if let error = error {
          completion(.failure(error))
        } else {
          completion(.success(data!))
        }
      }
      task.resume()
      
      // make sure to clean-up once the future is completed or cancelled
      return Disposer { task.cancel() }
    }
  }
}
```

## Retrieving the result

To retrieve the result of a future operation, you call `onResult()` and pass a closure.

```swift
session.data(at: url).onResult { result in
  switch result {
    case .success(let data): ...
    case .failure(let error): ...
  }
}
```

Here `onResult()` requires us to handle both failures and successes, however, it is often more convenient to focus on one or the other. For that `Future<T>` provides many convenience methods such as `onValue()` and `onError()`.

##  Transformations

The two most common transformations on futures are `map()` and `flatMap()`. You might already be familiar with these from the Swift standard library's optional and collection types. Applying `map()` on a future returns a new future with the result of calling the `transform` closure with the success value of the original future:

```swift
extension URLSession {
  func json(at: URL) -> Future<Jar> {
    return data(at: url).map { data in
      try Jar(json: data)
    }
  }
}
```

`Jar` is JSON container from the [Lift](https://github.com/izettle/lift) library, used here for illustration purposes.

Here we can see how we transformed a future result of `Data` into a future result of a JSON `Jar` container. This by providing a closure that will be called if `data(at:)` succeeds. Constructing a `Jar` from `Data` might fail and we see that `map()` will capture any thrown errors and convert them into future failures.

Where `map()` transforms the success value to another value, `flatMap()` transforms a success value into another future. This allows us to chain two asynchronous operations:

```swift
session.user(at: userURL).flatMap { user in
  return session.friends(at: user.friendsURL)
}
```

## Focus on the "happy flow"

It is quite typical when working with futures that you focus on the "happy flow". Failures are typically just implicitly forwarded and are explicitly handled only where required, and then normally at the end of a sequence of operations. This is very similar to Swift's optional chaining.

To not have to explicitly handle failures at every point makes code easier to read and reason about. Complex compositions become easier to follow, such as fetching a user's friends:

```swift
json(at: userURL).flatMap { jar in
  let user: User = try jar^
  return json(at: user.friendsURL)
}.map { jar in
  let friends: [Friend] = try jar^
  return friends
}.onValue { friends in
  // everything was successful
}.onError { error in
  // something failed
}
```

If you wonder what the `try jar^` is all about, it is just how [Lift](https://github.com/izettle/lift) converts the JSON contained inside a `Jar` into model values.

In the above example, it might not be obvious at first how much could fail. Both requests could fail, transforming data to JSON could fail, and constructing our model values could fail as well. If all goes well, we end up in `onValue()`'s completion. If something fails, we will end up in `onError()`'s completion.

## Cancellation

A future can be canceled by calling `cancel()` on it. However, if the future has continuations (other transforms applied to it, and hence others also interested in its result) a cancelation will be ignored.

```swift
let imageFuture = image(at: url)
...
imageFuture.cancel()
```

The helper `disposable` will return a disposable that will cancel on dispose which makes canceling of futures at clean-up easier to manage:

```swift
bag += image(at: url).disposable
```

## Combining futures

You could also combine different futures and either wait for them all to be completed using `join()`:

```swift
let friend: Future<Friend>
let pet: Future<Pet>
let friendAndPet = join(friend, pet) // Future<(Friend, Pet)>
```

Or with wait for the first one to complete:

```swift
let friend: Future<Friend>
let pet: Future<Pet>
let friendOrPet = select(friend, or: pet) // Future<Either<Friend, Pet>>
```

Where `Either` is defined as:

```swift
enum Either<Left, Right> {
  case left(Left)
  case right(Right)
}
```

## Repetition of futures

It is also useful to be able to repeat a future, e.g. if it fails:

```swift
data(at: url).onErrorRepeat()
```

Most of the repeat transformations also accept a predicate, a max repetition count, and a delay between repetitions. But perhaps even more powerful is that you could also provide a predicate that takes time to evaluate, such as showing an alert with a retry option:

```swift
func showRetryAlert(for error: Error) -> Future<Bool> { ... }

data(at: url).onErrorRepeat { error in
  showRetryAlert(error: error)
}
```

## Scheduling

For most future APIs accepting a callback closure, there is a defaulted `scheduler` parameter you can explicitly override to schedule the provided callback closure. The default scheduler is set to the current scheduler used when calling the API.

```swift
future.map {
  // Will be called back on the current scheduler at the time `map` was called.
}

future.map(on: .main) {
  // Will be called back on the main queue no matter from where `map` was called.
}
```

You can create your custom schedulers to e.g. wrap dispatch queues.

```swift
let imageProcessing = Scheduler(label: "image processing", attributes: .concurrent)

// call from main
fetchImage.map(on: imageProcessing) { image in
  image.scaledAndDecorated() // called in background
}.onValue { image in
  // called on main
}
```

## Future queues

Flow also includes a queue tailored for working with futures. Future queues are useful for handling exclusive access to a resource and/or when it is important that independent operations are sequenced one after the other.

```swift
let queue = FutureQueue()
queue.enqueue { anOperation() }
...
// Called by other user.
// The closure passed to `enqueue()` won't execute until `anOperation()` completes.
queue.enqueue { otherOperation() }
```

