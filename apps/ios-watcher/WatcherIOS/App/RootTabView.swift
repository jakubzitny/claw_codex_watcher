import SwiftUI

struct RootTabView: View {
    @ObservedObject var store: WatcherStore

    var body: some View {
        TabView {
            ThreadsView(store: store)
                .tabItem {
                    Label("Threads", systemImage: "list.bullet.rectangle.portrait")
                }

            SettingsView(store: store)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
