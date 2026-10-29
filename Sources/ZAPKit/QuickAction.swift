import Foundation

/// A shortcut on the remote. `appId` always comes from the TV's own app list — never guessed. A suggestion
/// without an `appId` stays unresolved until an installed app with that name is found.
public struct QuickAction: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var appId: String?
    /// Hidden from the remote without being removed (Settings → Apps).
    public var isEnabled: Bool
    public var id: String { appId ?? "suggested:\(name)" }

    public init(name: String, appId: String?, isEnabled: Bool = true) {
        self.name = name
        self.appId = appId
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey { case name, appId, isEnabled }

    /// Shortcuts saved before `isEnabled` existed decode as shown.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        appId = try container.decodeIfPresent(String.self, forKey: .appId)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

extension Array where Element == QuickAction {
    /// Drag and drop: the shortcut `id` takes the place of `targetID`, the others keep their order.
    public func moving(_ id: String, to targetID: String) -> [QuickAction] {
        guard id != targetID, let from = firstIndex(where: { $0.id == id }),
              let to = firstIndex(where: { $0.id == targetID }) else { return self }
        var result = self
        let item = result.remove(at: from)
        result.insert(item, at: to)
        return result
    }

    /// One step up (-1) or down (+1): the keyboard and menu alternative to dragging.
    public func moving(_ id: String, by offset: Int) -> [QuickAction] {
        guard let from = firstIndex(where: { $0.id == id }), indices.contains(from + offset) else { return self }
        var result = self
        result.swapAt(from, from + offset)
        return result
    }
}
