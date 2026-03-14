import SwiftUI
import AppKit

struct PortMenuView: View {
    @ObservedObject var viewModel: PortViewModel

    var body: some View {
        // Dummy view — we use NSMenu instead
        Text("")
            .onAppear {
                // NSMenu is set up by AppDelegate
            }
    }
}
