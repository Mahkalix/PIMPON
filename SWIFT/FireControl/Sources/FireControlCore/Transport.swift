import Foundation

@MainActor public protocol BoardTransport: AnyObject {
    var onEvent: ((TransportEvent) -> Void)? { get set }
    func connect()
    func disconnect()
    func send(_ command: Command)
}

@MainActor public final class SimulationTransport: BoardTransport {
    public var onEvent: ((TransportEvent) -> Void)?
    public let role: BoardRole
    private var state: BoardState
    private var revision = 0
    private var connected = false
    private var generation = UUID()
    public init(role: BoardRole) { self.role = role; state = .safe(role) }
    public func connect() { generation = UUID(); connected = true; onEvent?(.opened) }
    public func disconnect() {
        connected = false
        generation = UUID()
        stop()
        onEvent?(.closed("Connexion simulée coupée ; sécurité locale appliquée."))
    }
    private func stop() {
        if role == .truck {
            state.pumpEnabled = false; state.beaconEnabled = false; state.sirenEnabled = false; state.servoStopped = true
        } else { state.fireEnabled = false; state.fanEnabled = false; state.alarmEnabled = false }
        state.emergencyLocked = true
    }
    public func setPresence(_ present: Bool) {
        guard role == .truck, connected else { return }
        state.onScene = present
        if !present { state.pumpEnabled = false }
        emit(type: "event", event: "presenceChanged")
    }
    public func send(_ command: Command) {
        guard connected else { return }
        let epoch = generation
        // Asynchronous acknowledgement preserves the requested/pending/applied distinction.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, self.connected, self.generation == epoch else { return }
            self.apply(command)
        }
    }
    private func apply(_ c: Command) {
        var error: String?
        let common: Set<Action> = [.getState, .emergencyStop, .rearm]
        let truck: Set<Action> = [.setPump, .setBeacon, .setSiren, .setNozzleAngle]
        let house: Set<Action> = [.startFire, .stopFire, .setFan, .setFireLEDs, .setAlarm]
        if !(common.union(role == .truck ? truck : house)).contains(c.action) { error = "Commande incompatible avec le rôle." }
        else if state.emergencyLocked && c.action != .getState && c.action != .emergencyStop && c.action != .rearm {
            error = "Carte verrouillée : réarmement requis."
        } else {
            switch c.action {
            case .getState: break
            case .emergencyStop: stop()
            case .rearm: state.emergencyLocked = false
            case .setPump:
                if c.payload.enabled == true && state.onScene != true { error = "Pompe interdite hors zone." }
                else { state.pumpEnabled = c.payload.enabled ?? false }
            case .setBeacon: state.beaconEnabled = c.payload.enabled ?? false
            case .setSiren: state.sirenEnabled = c.payload.enabled ?? false
            case .setNozzleAngle:
                if let angle = c.payload.angle, (0...180).contains(angle) {
                    state.nozzleAngle = angle; state.servoStopped = false
                } else { error = "Angle invalide." }
            case .startFire: state.fireEnabled = true; state.fanEnabled = true; state.alarmEnabled = true
            case .stopFire: state.fireEnabled = false; state.fanEnabled = false
            case .setFireLEDs: state.fireEnabled = c.payload.enabled ?? false
            case .setFan: state.fanEnabled = c.payload.enabled ?? false
            case .setAlarm: state.alarmEnabled = c.payload.enabled ?? false
            }
        }
        emit(type: "ack", id: c.id, success: error == nil, error: error)
    }
    private func emit(type: String, id: String? = nil, success: Bool? = nil, error: String? = nil, event: String? = nil) {
        revision += 1
        onEvent?(.message(WireMessage(type: type, role: role, id: id, success: success,
                                    error: error, event: event, revision: revision, state: state)))
    }
}

@MainActor public final class WebSocketTransport: BoardTransport {
    public var onEvent: ((TransportEvent) -> Void)?
    private let url: URL
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var generation = UUID()
    public init(url: URL) { self.url = url }
    public func connect() {
        disconnectSilently()
        let epoch = UUID(); generation = epoch
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task; task.resume()
        // Ready is only established by the coordinator after getState succeeds.
        onEvent?(.opened)
        receiveTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let data: Data
                    switch try await task.receive() {
                    case .data(let bytes): data = bytes
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: throw URLError(.cannotParseResponse)
                    }
                    let message = try JSONDecoder().decode(WireMessage.self, from: data)
                    guard let self, self.generation == epoch else { return }
                    self.onEvent?(.message(message))
                }
            } catch { self?.fail(error, epoch: epoch) }
        }
        heartbeatTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    try await task.send(.string("{\"type\":\"heartbeat\"}"))
                    try await Task.sleep(for: .seconds(1))
                }
            } catch { self?.fail(error, epoch: epoch) }
        }
    }
    public func send(_ command: Command) {
        guard let socket else { return }
        let epoch = generation
        Task { [weak self] in
            do { try await socket.send(.data(JSONEncoder().encode(command))) }
            catch { self?.fail(error, epoch: epoch) }
        }
    }
    public func disconnect() {
        disconnectSilently(); onEvent?(.closed("Connexion fermée."))
    }
    private func disconnectSilently() {
        generation = UUID(); receiveTask?.cancel(); heartbeatTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }
    private func fail(_ error: Error, epoch: UUID) {
        guard epoch == generation else { return }
        disconnectSilently(); onEvent?(.closed(error.localizedDescription))
    }
}
