import Foundation

/// Payload returned by the gateway's chat.history RPC.
struct GatewayChatHistoryPayload: Decodable {
    let sessionKey: String
    let sessionId: String?
    let messages: [GatewayChatHistoryMessage]
    let thinkingLevel: String?

    private enum CodingKeys: String, CodingKey {
        case sessionKey
        case sessionId
        case messages
        case thinkingLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionKey = try container.decode(String.self, forKey: .sessionKey)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        messages = try container.decodeIfPresent([GatewayChatHistoryMessage].self, forKey: .messages) ?? []
        thinkingLevel = try container.decodeIfPresent(String.self, forKey: .thinkingLevel)
    }
}

/// A single message in the gateway chat history payload.
struct GatewayChatHistoryMessage: Decodable {
    let role: String
    let content: [GatewayChatHistoryContent]
    let timestamp: Double?
    let toolCallId: String?
    let toolName: String?
    let stopReason: String?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case timestamp
        case toolCallId
        case tool_call_id
        case toolName
        case tool_name
        case stopReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
            ?? container.decodeIfPresent(String.self, forKey: .tool_call_id)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
            ?? container.decodeIfPresent(String.self, forKey: .tool_name)
        stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)
        content = (try? container.decode([GatewayChatHistoryContent].self, forKey: .content)) ?? []
    }
}

/// Content entries for a gateway history message (text, tool calls, tool results, attachments).
struct GatewayChatHistoryContent: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let thinkingSignature: String?
    let mimeType: String?
    let fileName: String?
    let content: GatewayJSONValue?
    let id: String?
    let name: String?
    let arguments: GatewayJSONValue?

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case thinking
        case thinkingSignature
        case mimeType
        case fileName
        case content
        case id
        case name
        case arguments
    }
}

/// Minimal JSON value type for decoding flexible history payload fields.
enum GatewayJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: GatewayJSONValue])
    case array([GatewayJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: GatewayJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([GatewayJSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    /// Render the value as a human-readable string for tool input/output display.
    func stringValue(pretty: Bool = true) -> String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object, .array:
            let jsonObject = toJSONObject()
            guard JSONSerialization.isValidJSONObject(jsonObject) else {
                return nil
            }
            let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : []
            guard let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: options) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        case .null:
            return nil
        }
    }

    private func toJSONObject() -> Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.toJSONObject() }
        case .array(let value):
            return value.map { $0.toJSONObject() }
        case .null:
            return NSNull()
        }
    }
}
