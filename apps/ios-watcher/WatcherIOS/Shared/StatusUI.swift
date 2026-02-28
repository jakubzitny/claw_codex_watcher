import SwiftUI

extension ThreadStatus {
    var color: Color {
        switch self {
        case .running:
            return .orange
        case .thinking:
            return .cyan
        case .completed:
            return .green
        case .waiting:
            return .gray
        case .failed:
            return .red
        }
    }

    var symbolName: String {
        switch self {
        case .running:
            return "bolt.fill"
        case .thinking:
            return "brain.head.profile"
        case .completed:
            return "checkmark.circle.fill"
        case .waiting:
            return "pause.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct StatusPill: View {
    let status: ThreadStatus

    var body: some View {
        Label(status.rawValue.capitalized, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.16), in: Capsule())
            .foregroundStyle(status.color)
    }
}
