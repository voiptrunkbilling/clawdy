import Foundation

/// Predefined agent types with their session keys and default presentation.
/// These are hardcoded agents that users can select when creating a new session.
enum PredefinedAgent: String, CaseIterable, Identifiable {
    /// General-purpose main agent
    case main = "agent:main:main"
    
    /// Sales-focused agent for business conversations
    case sales = "agent:sales:main"
    
    /// Technical support agent
    case technical = "agent:tech:main"
    
    /// Personal assistant agent
    case personal = "agent:personal:main"
    
    // MARK: - Identifiable
    
    var id: String { rawValue }
    
    // MARK: - Display Properties
    
    /// Human-readable display name for the agent
    var displayName: String {
        switch self {
        case .main:
            return "General Assistant"
        case .sales:
            return "Sales Assistant"
        case .technical:
            return "Technical Support"
        case .personal:
            return "Personal Assistant"
        }
    }
    
    /// Default SF Symbol icon for the agent
    var defaultIcon: String {
        switch self {
        case .main:
            return "bubble.left.and.bubble.right.fill"
        case .sales:
            return "briefcase.fill"
        case .technical:
            return "wrench.and.screwdriver.fill"
        case .personal:
            return "person.fill"
        }
    }
    
    /// Default hex color for the agent
    var defaultColor: String {
        switch self {
        case .main:
            return "#0A84FF" // System blue
        case .sales:
            return "#30D158" // System green
        case .technical:
            return "#FF9F0A" // System orange
        case .personal:
            return "#BF5AF2" // System purple
        }
    }
    
    /// Short description of the agent's purpose
    var description: String {
        switch self {
        case .main:
            return "Your everyday AI assistant"
        case .sales:
            return "Help with sales and business conversations"
        case .technical:
            return "Technical troubleshooting and support"
        case .personal:
            return "Personal tasks and reminders"
        }
    }
}

// MARK: - Agent Lookup

extension PredefinedAgent {
    /// Find an agent by its session key
    static func from(sessionKey: String) -> PredefinedAgent? {
        allCases.first { $0.rawValue == sessionKey }
    }
}
