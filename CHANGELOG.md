# 1.2.1

- Conditionally conform `Either` to Hashable when `Left` and `Right` conforms to `Hashable`.

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

