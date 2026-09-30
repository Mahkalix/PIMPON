import Foundation

public enum BoardRole: String, Codable, CaseIterable, Sendable { case truck, house }
public enum RunMode: String, CaseIterable, Sendable { case simulation = "Simulation", hardware = "Matériel" }
public enum Phase: String, Sendable {
    case preparation = "Préparation", starting = "Déclenchement du feu", incomingCall = "Centre d’alerte"
    case briefing = "Message d’intervention", departure = "Départ", travelling = "Camion en route"
    case intervention = "Intervention", extinguishing = "Arrêts en cours", extinguished = "Feu simulé éteint"
    case finishing = "Fin en cours", finished = "Intervention terminée"
}
public enum Connection: String, Sendable { case disconnected = "Déconnecté", connecting = "Connexion en cours", ready = "Connecté, état reçu" }
public enum Action: String, Codable, Sendable {
    case getState, setPump, setBeacon, setSiren, setNozzleAngle, startFire, stopFire, setFan, setFireLEDs, setAlarm, emergencyStop, rearm
}
public struct Payload: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var angle: Double?
    public init(enabled: Bool? = nil, angle: Double? = nil) { self.enabled = enabled; self.angle = angle }
}
public struct Command: Codable, Equatable, Sendable {
    public let type = "command"
    public var id: String
    public var action: Action
    public var payload: Payload
    public init(action: Action, payload: Payload = Payload()) {
        id = UUID().uuidString; self.action = action; self.payload = payload
    }
    enum CodingKeys: String, CodingKey { case type, id, action, payload }
}
// Every state is a complete snapshot for its role, never a patch.
public struct BoardState: Codable, Equatable, Sendable {
    public var emergencyLocked: Bool = false
    public var pumpEnabled: Bool?
    public var beaconEnabled: Bool?
    public var sirenEnabled: Bool?
    public var nozzleAngle: Double?
    public var servoStopped: Bool?
    public var onScene: Bool?
    public var fireEnabled: Bool?
    public var fanEnabled: Bool?
    public var alarmEnabled: Bool?
    public init() {}
    public static func safe(_ role: BoardRole) -> BoardState {
        var s = BoardState()
        if role == .truck {
            s.pumpEnabled = false; s.beaconEnabled = false; s.sirenEnabled = false
            s.nozzleAngle = 90; s.servoStopped = true; s.onScene = false
        } else { s.fireEnabled = false; s.fanEnabled = false; s.alarmEnabled = false }
        return s
    }
    public func isComplete(for role: BoardRole) -> Bool {
        switch role {
        case .truck:
            return pumpEnabled != nil && beaconEnabled != nil && sirenEnabled != nil &&
                nozzleAngle?.isFinite == true && servoStopped != nil && onScene != nil
        case .house: return fireEnabled != nil && fanEnabled != nil && alarmEnabled != nil
        }
    }
    public func allStopped(_ role: BoardRole) -> Bool {
        if role == .truck { return pumpEnabled == false && beaconEnabled == false && sirenEnabled == false && servoStopped == true }
        return fireEnabled == false && fanEnabled == false && alarmEnabled == false
    }
}
public struct WireMessage: Codable, Sendable {
    public var type: String
    public var role: BoardRole
    public var id: String?
    public var success: Bool?
    public var error: String?
    public var event: String?
    public var revision: Int
    public var state: BoardState
    public init(type: String, role: BoardRole, id: String? = nil, success: Bool? = nil,
                error: String? = nil, event: String? = nil, revision: Int, state: BoardState) {
        self.type = type; self.role = role; self.id = id; self.success = success
        self.error = error; self.event = event; self.revision = revision; self.state = state
    }
}
public enum TransportEvent: Sendable { case opened, closed(String), message(WireMessage) }
public struct CommandRecord: Identifiable, Sendable {
    public enum Status: String, Sendable { case pending = "En attente", confirmed = "Confirmée", failed = "Erreur" }
    public let id: String
    public let role: BoardRole
    public let action: Action
    public let payload: Payload
    public var status: Status
    public var detail: String
}
