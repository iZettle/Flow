# 1.8.5


# 1.8.4

- Fix compilation errors in Xcode 11.4 beta
- Use Swift.Result instead of custom result implementation
- Update sample to match readme.

# 1.8.3

- Fix race conditions for iOS 13 for Signal and cleanup CallbackState<Value>
- Add new combiner `driven(by:)` that makes a `ReadSignal` emit its latest readable values when the given "driver" signal fires events. The combined signal will derive its signal kind from the driver, but without write access.

# 1.8.2

- Fix the `traitCollectionWithFallback` behaviour on iOS 13 to return the view's predicted traits and prior iOS 13 to respect the key window's traits before falling back to the main screen traits.

# 1.8.1

- Added signal transformations `contains(where:)` and `allSatisfy(where:)` as wrappers for boolean `reduce()` transforms.
- Changed `reduce()` implementation to consider initial values when performed on readable signals.

# 1.8

- Added `deallocSignal(for:)` and `NSObject.deallocSignal` for listen on deallocation of objects.
- Added signal transformation `with(weak:)` as a convenience helper for breaking retain cycles.

# 1.7

- Migration to Swift 5.

# 1.6

 - Addition: Make `Callbacker` conform to `SignalProvider`.

# 1.5.2

- Bugfix: Make sure `shared()` updates its last value before calling out to get correct results in case of recursion.

# 1.5.1

- Update `combineLatest` to no longer allow mixing of plain and readable signals as for the returned signal to guarantee to be readable all provided signals must as be readable as well. This is technically a breaking of the API, but as the existing implementation is broken and might result in run-time crashes, this change can be considered as a bug-fix.

# 1.5

- Added new `Future` and `Signal` `delay` alternatives that accepts a closure that returns the delay based on the value allow variable delays.

# 1.4.2

- Fixed a bug with some of `Future`'s repeat methods where the delay `delayBetweenRepetitions` was added after the last repetition as well.
- Fixed bug where the predicate passed to `onResultRepeat` was not always scheduled correctly.

# 1.4.1

- Fixes a problem where onErrorRepeat would not respect the specified delay interval.
- Fixed issues with tvOS support.
- Updates some transforms such as `toVoid()` to schedule on `.none` instead of `.current` so these transforms won't cause a re-schedule.

# 1.4

- Updated the `Signal.flatMapLatest()` transformation to allow more flexible mixing of signal types between `self` and the signal returned from `transform`.
- Added `Signal.toogle()` method for read-write boolean signals.
- Added `didWrite()` transformations to read-write signals.
- Added `UIControl` `valueChanged` that will signal with the latest value when the control event `.valueChanged` is signaled.

# 1.3.1

- Bugfix: Updated `Future.abort(forFutures:)` to more correctly handle repetition.

# 1.3

- Added versions of `bindTo()` that can bind a non optional to an optional value.
- Added `enable()` to `Enablable` similar as `disable()`.
- Added more defaulted parameters to `Scheduler.init` for dispatch queues.
- Fixes a crash on Swift 4.2 when immediately (on the same line) modifying a `ReadWriteSignal`'s `value`.
- Added `Scheduler` `perform` helper.
- Added signal `withLatestFrom` transformation.

# 1.2.1

- Conditionally conform `Either` to Hashable when `Left` and `Right` conforms to `Hashable`.
- Conforms UISlider to SignalProvider.

# 1.2

- Added `NSManagedObjectContext.scheduler` property for scheduling work on managed object contexts when CoreData is available.

# 1.1

- Added `DisposeBag.hold()`  convenience method for holding a reference to an object.
- Added `UITextField` delegates for `shouldEndEditing` and `shouldReturn`l
- Added `UITextField.isEditingSignal` signal.
- Added `UIView.install()` for installing gesture recognizers.
- Added `UIView` signals for displaying editing menu for copy, cut and paste.
- Added `orientationSignal`  that  will signal on orientation changes.
- Added `UIRefreshControl`  `animate()` and `refersh()` helpers.
- Added `disableActiveEventListeners()` helper

# 1.0

This is the first public release of the Flow library.

