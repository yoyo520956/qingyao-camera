import SwiftUI

@main
struct QingyaoCameraApp: App {
    @StateObject private var viewModel = CameraViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
