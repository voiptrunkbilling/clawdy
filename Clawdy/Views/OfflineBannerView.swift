import SwiftUI

/// A banner displayed when the app is offline (gateway disconnected)
/// Shows clear status and allows manual retry
struct OfflineBannerView: View {
    let connectionStatus: ConnectionStatus
    let gatewayFailure: GatewayConnectionFailure
    let isReconnecting: Bool
    let onRetry: () -> Void
    
    /// Whether we're truly offline (gateway disconnected without chat capability)
    var isOffline: Bool {
        // Gateway disconnected or partialNode (no chat capability)
        switch connectionStatus {
        case .disconnected, .partialNode(_):
            return true
        case .connected, .partialOperator(_, _), .connecting, .pairingPending(_, _):
            return false
        }
    }
    
    /// Primary message to display
    private var offlineMessage: String {
        switch connectionStatus {
        case .disconnected:
            return statusMessageForFailure(gatewayFailure)
        case .partialNode(_):
            return "Chat Unavailable"
        default:
            return "Offline"
        }
    }
    
    /// Secondary message with more detail
    private var detailMessage: String {
        switch connectionStatus {
        case .disconnected:
            return detailMessageForFailure(gatewayFailure)
        case .partialNode(_):
            return "Device features work, but chat needs pairing. Tap to retry."
        default:
            return "Check your network connection"
        }
    }

    private func statusMessageForFailure(_ failure: GatewayConnectionFailure) -> String {
        switch failure {
        case .none:
            return "Not connected"
        case .hostUnreachable:
            return "Not connected"
        case .other(let reason):
            let normalized = reason.lowercased()
            if normalized.contains("timed out") || normalized.contains("timeout") {
                return "Connection Timed Out"
            }
            if normalized.contains("refused") {
                return "Server Unavailable"
            }
            if normalized.contains("network") {
                return "Network Error"
            }
            if normalized.contains("auth") || normalized.contains("token") || normalized.contains("key") {
                return "Authentication Error"
            }
            return "Not connected"
        }
    }

    private func detailMessageForFailure(_ failure: GatewayConnectionFailure) -> String {
        switch failure {
        case .none:
            return "Tap to reconnect"
        case .hostUnreachable:
            return "Tap to reconnect"
        case .other(let reason):
            let normalized = reason.lowercased()
            if normalized.contains("timed out") || normalized.contains("timeout") {
                return "The server may be busy. Tap to retry."
            }
            if normalized.contains("auth") || normalized.contains("token") || normalized.contains("key") {
                return "Check your gateway credentials in Settings"
            }
            return "Tap to reconnect"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Warning icon
                Image(systemName: "network.slash")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(offlineMessage)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(detailMessage)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                Button(action: onRetry) {
                    if isReconnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                            .frame(width: 60)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Retry")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(14)
                    }
                }
                .disabled(isReconnecting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.red)
        }
    }
}

/// A smaller, less intrusive connection status indicator for the top bar
/// Used when connection is in a transitional state (connecting/reconnecting)
struct ConnectionStatusBadge: View {
    let status: ConnectionStatus
    let isReconnecting: Bool
    
    var body: some View {
        if isReconnecting {
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                    .scaleEffect(0.6)
                
                Text("Reconnecting...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.yellow.opacity(0.15))
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview

#Preview("Offline States") {
    VStack(spacing: 20) {
        // Host unreachable
        OfflineBannerView(
            connectionStatus: .disconnected(reason: "Not connected"),
            gatewayFailure: .hostUnreachable(reason: "timed out"),
            isReconnecting: false,
            onRetry: {}
        )
        
        // Gateway Disconnected
        OfflineBannerView(
            connectionStatus: .disconnected(reason: "Not connected"),
            gatewayFailure: .other(reason: "Connection timed out"),
            isReconnecting: false,
            onRetry: {}
        )
        
        // Reconnecting
        OfflineBannerView(
            connectionStatus: .connecting,
            gatewayFailure: .none,
            isReconnecting: true,
            onRetry: {}
        )
        
        // Server unavailable
        OfflineBannerView(
            connectionStatus: .disconnected(reason: "Not connected"),
            gatewayFailure: .other(reason: "Connection refused"),
            isReconnecting: false,
            onRetry: {}
        )
        
        // Auth error
        OfflineBannerView(
            connectionStatus: .disconnected(reason: "Not connected"),
            gatewayFailure: .other(reason: "authentication failed"),
            isReconnecting: false,
            onRetry: {}
        )
        
        Spacer()
        
        ConnectionStatusBadge(
            status: .connecting,
            isReconnecting: true
        )
    }
    .padding(.top, 50)
}
