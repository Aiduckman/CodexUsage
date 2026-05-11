import Foundation

@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    let viewModel = UsageViewModel(useMock: false)

    private init() {}
}
