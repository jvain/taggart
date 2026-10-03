import SwiftUI

/// Drop-in replacement for `@State`.
///
/// In the macOS 27 SDK `@State` is a macro whose compiler plugin ships with
/// Xcode but not with the Command Line Tools, so `@State` doesn't build there.
/// This wrapper stores a plain `SwiftUI.State` (SwiftUI finds dynamic
/// properties nested in other dynamic properties) and works with both.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
