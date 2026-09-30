import Foundation
import Observation

@MainActor @Observable public final class InterventionCoordinator {
    public private(set) var mode: RunMode = .simulation
    public private(set) var phase: Phase = .preparation
    public private(set) var connections: [BoardRole: Connection] = [:]
    public private(set) var states: [BoardRole: BoardState] = [:]
    public private(set) var errors: [BoardRole: String] = [:]
    public private(set) var records: [CommandRecord] = []
    public private(set) var emergencyLocked = false
    public private(set) var paused = false
    public private(set) var pumpUsed = false
    public private(set) var message = "Remplissez physiquement le réservoir avant la démonstration."
    public var truckAddress = "ws://192.168.1.50:81"
    public var houseAddress = "ws://192.168.1.51:81"
    public var nozzleMinimum = 60.0
    public var nozzleMaximum = 120.0
    public var hardwareRangeValidated = false
    @ObservationIgnored private var transports: [BoardRole: any BoardTransport] = [:]
    @ObservationIgnored private var pending: [String: (BoardRole, Command)] = [:]
    @ObservationIgnored private var timeouts: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var revisions: [BoardRole: Int] = [:]
    @ObservationIgnored private var epochs: [BoardRole: UUID] = [:]
    @ObservationIgnored private var lastSeen: [BoardRole: Date] = [:]
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var rearming = false
    @ObservationIgnored private var awaitingResumeStops = false

    public init() {}
    public var ready: Bool { BoardRole.allCases.allSatisfy { connections[$0] == .ready } }
    public var onScene: Bool { states[.truck]?.onScene == true }
    public var controlsAvailable: Bool { ready && !paused && !emergencyLocked }
    public var canPump: Bool { controlsAvailable && phase == .intervention && onScene && !hasPending(.truck, .setPump) }
    public var validNozzleRange: Bool {
        nozzleMinimum.isFinite && nozzleMaximum.isFinite && nozzleMinimum >= 0 && nozzleMaximum <= 180 && nozzleMinimum < nozzleMaximum
    }
    public var canAim: Bool { canPump && validNozzleRange && (mode == .simulation || hardwareRangeValidated) && !hasPending(.truck, .setNozzleAngle) }
    public var canConfirmExtinction: Bool { controlsAvailable && phase == .intervention && pumpUsed }
    public var canStart: Bool {
        controlsAvailable && phase == .preparation && !houseCommandPending && BoardRole.allCases.allSatisfy { states[$0]?.allStopped($0) == true }
    }
    private var houseCommandPending: Bool { pending.values.contains { $0.0 == .house } }
    public var canAdministerHouse: Bool {
        controlsAvailable && phase == .preparation && !houseCommandPending
    }
    public var canChangeConfiguration: Bool {
        phase == .preparation && !emergencyLocked && !houseCommandPending && states[.house]?.allStopped(.house) != false
    }
    public func setHouseEquipment(_ action: Action, enabled: Bool) {
        guard canAdministerHouse, [.setAlarm, .setFan, .setFireLEDs].contains(action) else { return }
        send(.house, action, enabled: enabled)
    }
    public func hasPending(_ role: BoardRole, _ action: Action) -> Bool {
        pending.values.contains { $0.0 == role && $0.1.action == action }
    }
    public func configure(mode: RunMode) {
        guard canChangeConfiguration else { return }
        for role in BoardRole.allCases { invalidate(role, reason: "Changement de mode"); transports[role]?.onEvent = nil; transports[role]?.disconnect() }
        transports.removeAll(); states.removeAll(); revisions.removeAll()
        self.mode = mode; paused = false; errors.removeAll()
        for role in BoardRole.allCases { connections[role] = .disconnected }
    }
    public func connect() {
        for role in BoardRole.allCases where connections[role] != .ready {
            if mode == .simulation {
                // Preserve simulated firmware state across reconnections.
                install(transports[role] ?? SimulationTransport(role: role), for: role)
            } else {
                let address = role == .truck ? truckAddress : houseAddress
                guard let url = URL(string: address), ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                    errors[role] = "Adresse WebSocket invalide (ws:// ou wss://)."; continue
                }
                install(WebSocketTransport(url: url), for: role)
            }
        }
        startWatchdog()
    }
    // Dependency injection also lets tests exercise the exact production coordinator.
    public func install(_ transport: any BoardTransport, for role: BoardRole) {
        transports[role]?.onEvent = nil; transports[role]?.disconnect()
        invalidate(role, reason: "Nouvelle connexion")
        let epoch = UUID(); epochs[role] = epoch
        transports[role] = transport; connections[role] = .connecting
        revisions[role] = nil; states[role] = nil; errors[role] = nil
        transport.onEvent = { [weak self] event in
            guard let self, self.epochs[role] == epoch else { return }
            self.receive(event, from: role)
        }
        transport.connect()
    }
    public func simulatePresence(_ present: Bool) {
        guard mode == .simulation, phase == .travelling || phase == .intervention else { return }
        (transports[.truck] as? SimulationTransport)?.setPresence(present)
    }
    public func simulateDisconnect(_ role: BoardRole) {
        guard mode == .simulation else { return }; transports[role]?.disconnect()
    }
    public func startFire() {
        guard canStart else { return }
        pumpUsed = false; phase = .starting; message = "Activation du faux feu demandée à la maison."
        send(.house, .startFire)
    }
    public func answerCall() { guard phase == .incomingCall, controlsAvailable else { return }; phase = .briefing }
    public func acceptIntervention() {
        guard [.incomingCall, .briefing].contains(phase), controlsAvailable else { return }
        phase = .departure; message = "Attendez les confirmations du gyrophare et de la sirène, puis confirmez le départ."; send(.truck, .setBeacon, enabled: true); send(.truck, .setSiren, enabled: true)
    }
    public func confirmDeparture() {
        guard phase == .departure, controlsAvailable, states[.truck]?.beaconEnabled == true,
              states[.truck]?.sirenEnabled == true else { return }
        phase = .travelling; message = "Conduisez avec la télécommande. L’application attend la présence dans la zone."; detectArrival()
    }
    public func setBeacon(_ enabled: Bool) {
        guard controlsAvailable, [.departure, .travelling].contains(phase), !hasPending(.truck, .setBeacon) else { return }
        send(.truck, .setBeacon, enabled: enabled)
    }
    public func setSiren(_ enabled: Bool) {
        guard controlsAvailable, [.departure, .travelling].contains(phase), !hasPending(.truck, .setSiren) else { return }
        send(.truck, .setSiren, enabled: enabled)
    }
    public func setPump(_ enabled: Bool) {
        if enabled { guard canPump else { return } }
        else { guard connections[.truck] == .ready, !emergencyLocked else { return } }
        send(.truck, .setPump, enabled: enabled)
    }
    public func aim(_ angle: Double) {
        guard canAim, angle.isFinite, (nozzleMinimum...nozzleMaximum).contains(angle) else { return }
        send(.truck, .setNozzleAngle, angle: angle)
    }
    public func confirmExtinction() {
        guard canConfirmExtinction else { return }; phase = .extinguishing; message = "Extinction demandée : attente des sorties arrêtées sur les deux cartes."; retryStops()
    }
    public func retryStops() {
        if emergencyLocked { emergencyStop(); return }
        guard [.extinguishing, .extinguished, .finishing, .intervention].contains(phase) else { return }
        send(.truck, .setPump, enabled: false)
        send(.truck, .setSiren, enabled: false); send(.house, .setAlarm, enabled: false)
        if phase != .intervention { send(.house, .stopFire) }
        if phase == .finishing { send(.truck, .setBeacon, enabled: false) }
    }
    public func finish() {
        guard phase == .extinguished, controlsAvailable, extinctionConfirmed else { return }
        phase = .finishing
        // Emergency stop also immobilizes the servo, then explicit rearm is required for the next run.
        send(.truck, .emergencyStop); send(.house, .emergencyStop)
    }
    public func emergencyStop() {
        emergencyLocked = true; rearming = false; awaitingResumeStops = false
        message = "Arrêt d’urgence verrouillé. Arrêtez la voiture avec sa télécommande : ses moteurs sont indépendants."
        for role in BoardRole.allCases {
            invalidate(role, reason: "Annulée par l’arrêt d’urgence ; état à vérifier.")
            send(role, .emergencyStop)
        }
    }
    public var canRearm: Bool {
        ready && pending.isEmpty && BoardRole.allCases.allSatisfy { states[$0]?.allStopped($0) == true }
    }
    public func rearm() {
        guard canRearm else { return }
        emergencyLocked = true; rearming = true
        send(.truck, .rearm); send(.house, .rearm)
    }
    public func newIntervention() {
        guard phase == .finished, canRearm else { return }; rearm()
    }
    public func resume() {
        guard paused, ready, !emergencyLocked,
              BoardRole.allCases.allSatisfy({ states[$0]?.emergencyLocked == false }) else { return }
        // Explicit stop confirmation is necessary before making activation controls available again.
        awaitingResumeStops = true
        send(.truck, .setPump, enabled: false)
    }
    public func retryStart() {
        guard phase == .starting, controlsAvailable else { return }; send(.house, .startFire)
    }
    private var extinctionConfirmed: Bool {
        ready && states[.truck]?.pumpEnabled == false && states[.house]?.fireEnabled == false && states[.house]?.fanEnabled == false &&
        !hasPending(.truck, .setPump) && !hasPending(.house, .stopFire)
    }
    private func detectArrival() {
        guard phase == .travelling, onScene, controlsAvailable else { return }
        phase = .intervention; message = "Camion sur place. Arrêtez le véhicule avec la télécommande."
        send(.truck, .setSiren, enabled: false); send(.house, .setAlarm, enabled: false)
    }
    private func send(_ role: BoardRole, _ action: Action, enabled: Bool? = nil, angle: Double? = nil) {
        guard connections[role] == .ready || (action == .getState && connections[role] == .connecting) else {
            errors[role] = "Commande \(action.rawValue) non envoyée : carte indisponible."; return
        }
        if action == .setPump && enabled == false {
            for (id, item) in pending where item.0 == role && item.1.action == .setPump && item.1.payload.enabled == true {
                failRecord(id, "Activation remplacée par une demande d’arrêt.")
            }
        }
        guard !hasPending(role, action) else { return }
        let command = Command(action: action, payload: Payload(enabled: enabled, angle: angle))
        pending[command.id] = (role, command)
        records.append(CommandRecord(id: command.id, role: role, action: action, payload: command.payload, status: .pending, detail: "Demandée, sans confirmation de sortie."))
        if records.count > 100 { records.removeFirst(records.count - 100) }
        timeouts[command.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.commandTimedOut(command.id, role: role)
        }
        transports[role]?.send(command)
    }
    private func commandTimedOut(_ id: String, role: BoardRole) {
        guard pending[id] != nil else { return }
        failRecord(id, "Confirmation absente : sortie inconnue.")
        receive(.closed("Délai de confirmation dépassé."), from: role)
        transports[role]?.disconnect()
    }
    private func failRecord(_ id: String, _ reason: String) {
        pending[id] = nil; timeouts.removeValue(forKey: id)?.cancel()
        if let index = records.firstIndex(where: { $0.id == id }) { records[index].status = .failed; records[index].detail = reason }
    }
    private func invalidate(_ role: BoardRole, reason: String) {
        for id in pending.filter({ $0.value.0 == role }).map(\.key) { failRecord(id, reason) }
    }
    private func receive(_ event: TransportEvent, from role: BoardRole) {
        switch event {
        case .opened: send(role, .getState)
        case .closed(let reason):
            invalidate(role, reason: reason); connections[role] = .disconnected; states[role] = nil; errors[role] = reason
            if phase != .preparation && phase != .finished {
                paused = true; message = "Scénario en pause. Arrêts non confirmés sur la carte déconnectée."
                if role == .house && connections[.truck] == .ready { send(.truck, .setPump, enabled: false) }
            }
        case .message(let m):
            guard connections[role] != .disconnected else { return }
            guard m.role == role, m.state.isComplete(for: role), m.revision >= 0,
                  ["ack", "state", "event"].contains(m.type) else {
                receive(.closed("Message invalide ou rôle de carte incorrect."), from: role); transports[role]?.disconnect(); return
            }
            lastSeen[role] = Date()
            var acknowledged: Command?
            if m.type == "ack" {
                guard let id = m.id, let (target, c) = pending[id], target == role else { return }
                guard m.success == true else {
                    let reason = m.error ?? "Commande refusée."
                    failRecord(id, reason); errors[role] = reason
                    // A failure never applies the attached state as a successful output change.
                    return
                }
                guard matches(c, state: m.state, role: role) else {
                    failRecord(id, "Réponse incohérente : sortie demandée non confirmée.")
                    errors[role] = "Réponse incohérente : sortie demandée non confirmée."
                    return
                }
                errors[role] = nil
                acknowledged = c
                pending[id] = nil; timeouts.removeValue(forKey: id)?.cancel()
                if let index = records.firstIndex(where: { $0.id == id }) {
                    records[index].status = .confirmed; records[index].detail = "Sortie appliquée par la carte, sans mesure physique indépendante."
                }
            }
            let fresh = m.revision > (revisions[role] ?? -1)
            let wasOnScene = onScene
            if fresh { states[role] = m.state; revisions[role] = m.revision }
            if acknowledged?.action == .getState { connections[role] = .ready; errors[role] = nil }
            if fresh && m.state.emergencyLocked && phase != .finishing && phase != .finished { emergencyLocked = true }
            if role == .truck && fresh && wasOnScene && !onScene && phase == .intervention && !emergencyLocked {
                message = "Camion hors zone. Pompe bloquée ; une nouvelle activation sera nécessaire au retour."
                send(.truck, .setPump, enabled: false)
            }
            if fresh && role == .truck && phase == .intervention && m.state.pumpEnabled == true && onScene && !emergencyLocked {
                pumpUsed = true
            }
            if awaitingResumeStops && acknowledged?.action == .setPump && acknowledged?.payload.enabled == false && states[.truck]?.pumpEnabled == false {
                awaitingResumeStops = false; paused = false; message = "Reprise explicite. Aucun équipement n’a été réactivé."
            }
            advance()
        }
    }
    private func matches(_ c: Command, state: BoardState, role: BoardRole) -> Bool {
        switch c.action {
        case .getState: return true
        case .setPump: return state.pumpEnabled == c.payload.enabled
        case .setBeacon: return state.beaconEnabled == c.payload.enabled
        case .setSiren: return state.sirenEnabled == c.payload.enabled
        case .setAlarm: return state.alarmEnabled == c.payload.enabled
        case .setFan: return state.fanEnabled == c.payload.enabled
        case .setFireLEDs: return state.fireEnabled == c.payload.enabled
        case .setNozzleAngle: return state.nozzleAngle == c.payload.angle
        case .startFire: return state.fireEnabled == true && state.fanEnabled == true && state.alarmEnabled == true
        case .stopFire: return state.fireEnabled == false && state.fanEnabled == false
        case .emergencyStop: return state.emergencyLocked && state.allStopped(role)
        case .rearm: return !state.emergencyLocked && state.allStopped(role)
        }
    }
    private func advance() {
        if rearming && ready && pending.isEmpty && BoardRole.allCases.allSatisfy({ states[$0]?.emergencyLocked == false && states[$0]?.allStopped($0) == true }) {
            rearming = false; emergencyLocked = false; paused = false; phase = .preparation; pumpUsed = false
            message = "Réarmé. Préparez à nouveau le réservoir et le camion."; return
        }
        guard controlsAvailable else { return }
        if phase == .starting, states[.house]?.fireEnabled == true, states[.house]?.fanEnabled == true,
           states[.house]?.alarmEnabled == true, !hasPending(.house, .startFire) { phase = .incomingCall; message = "Faux feu confirmé actif. Appel entrant fictif du centre d’alerte." }
        detectArrival()
        if phase == .intervention && onScene { message = "Camion sur place. Lorsque vous estimez l’incendie éteint, appuyez sur Confirmer l’extinction." }
        if phase == .extinguishing && extinctionConfirmed { phase = .extinguished; message = "Pompe, LED et ventilateur confirmés à l’arrêt." }
        if phase == .finishing && pending.isEmpty && BoardRole.allCases.allSatisfy({ states[$0]?.allStopped($0) == true }) { phase = .finished; message = "Tous les équipements connectés sont confirmés à l’arrêt." }
    }
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                guard self.mode == .hardware else { continue }
                for role in BoardRole.allCases where self.connections[role] == .ready {
                    if Date().timeIntervalSince(self.lastSeen[role] ?? .distantPast) > 5 {
                        self.receive(.closed("Heartbeat matériel absent depuis 5 secondes."), from: role)
                        self.transports[role]?.disconnect()
                    }
                }
            }
        }
    }
}
