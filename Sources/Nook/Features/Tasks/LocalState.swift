import SwiftUI

/// Stand-in for `@State` while the toolchain lacks the SwiftUIMacros plugin (Command Line Tools only).
/// Wraps `SwiftUI.State` without using the attribute, so it behaves identically.
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    private var state: SwiftUI.State<Value>

    init(wrappedValue: Value) {
        state = SwiftUI.State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { state.projectedValue }
}
