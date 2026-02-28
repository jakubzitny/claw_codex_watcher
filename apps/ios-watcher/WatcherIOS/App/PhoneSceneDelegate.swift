import SwiftUI
import UIKit

@MainActor
final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private let container = AppContainer.shared

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let rootView = RootTabView(store: container.store)
        let hostingController = UIHostingController(rootView: rootView)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hostingController
        self.window = window
        window.makeKeyAndVisible()

        Task { @MainActor in
            await container.store.startIfNeeded()
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Task { @MainActor in
            await container.store.startIfNeeded()
        }
    }
}
