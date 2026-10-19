import SwiftUI

struct CaptionFollowState {
    var latest = true
    mutating func userScrolling() { latest = false }
    mutating func settled(offset: Double, viewport: Double, content: Double) {
        latest = offset + viewport >= content - 40
    }
}
extension View {
    @ViewBuilder func captionScrollFollowing(_ follow: Binding<CaptionFollowState>) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollPhaseChange { _, phase, context in
                switch phase {
                case .tracking, .interacting, .decelerating: follow.wrappedValue.userScrolling()
                case .idle:
                    let geometry = context.geometry
                    follow.wrappedValue.settled(offset: geometry.contentOffset.y, viewport: geometry.containerSize.height, content: geometry.contentSize.height)
                default: break // Programmatic animations must not disable following.
                }
            }
        } else {
            // macOS 14 retains full scrollback but lacks native phase tracking.
            self
        }
    }
}
