import Foundation
import Testing
@testable import FireControlCore

@MainActor private final class TestBoard: BoardTransport {
    var onEvent: ((TransportEvent) -> Void)?
    let role: BoardRole
    var state: BoardState
    var commands: [Command] = []
    var revision = 0
    init(_ role: BoardRole) { self.role = role; state = .safe(role) }
    func connect() { onEvent?(.opened) }
    func disconnect() { onEvent?(.closed("Coupure de test")) }
    func send(_ command: Command) { commands.append(command) }
    func last(_ action: Action) -> Command { commands.last { $0.action == action }! }
    func ack(_ action: Action, success: Bool = true, mutate: ((inout BoardState) -> Void)? = nil) {
        let c = last(action)
        mutate?(&state)
        revision += 1
        onEvent?(.message(WireMessage(type: "ack", role: role, id: c.id, success: success,
                                      error: success ? nil : "Échec injecté", revision: revision, state: state)))
    }
    func presence(_ present: Bool) {
        state.onScene = present
        if !present { state.pumpEnabled = false }
        revision += 1
        onEvent?(.message(WireMessage(type: "event", role: role, event: "presenceChanged", revision: revision, state: state)))
    }
}

struct CoordinatorTests {
    @MainActor private func setup() -> (InterventionCoordinator, TestBoard, TestBoard) {
        let m = InterventionCoordinator(), truck = TestBoard(.truck), house = TestBoard(.house)
        m.install(truck, for: .truck); m.install(house, for: .house)
        truck.ack(.getState); house.ack(.getState)
        return (m, truck, house)
    }
    @MainActor private func arrive(_ m: InterventionCoordinator, _ t: TestBoard, _ h: TestBoard) {
        m.startFire()
        h.ack(.startFire) { $0.fireEnabled = true; $0.fanEnabled = true; $0.alarmEnabled = true }
        m.answerCall(); m.acceptIntervention()
        t.ack(.setBeacon) { $0.beaconEnabled = true }
        t.ack(.setSiren) { $0.sirenEnabled = true }
        m.confirmDeparture(); t.presence(true)
        t.ack(.setSiren) { $0.sirenEnabled = false }
        h.ack(.setAlarm) { $0.alarmEnabled = false }
    }
    @Test @MainActor func testPumpBlockedBeforeArrivalAndPendingNotConfirmed() async {
        let (m, t, h) = setup()
        m.setPump(true)
        #expect(!(t.commands.contains { $0.action == .setPump }))
        m.startFire()
        #expect(m.phase == .starting)
        #expect(m.states[.house]?.fireEnabled == false)
        #expect(m.hasPending(.house, .startFire))
        h.ack(.startFire) { $0.fireEnabled = true; $0.fanEnabled = true; $0.alarmEnabled = true }
        #expect(m.phase == .incomingCall)
    }
    @Test @MainActor func testArrivalStopsAlarmsOnceAndNeverStartsPump() async {
        let (m, t, h) = setup(); arrive(m, t, h)
        #expect(m.phase == .intervention)
        #expect(m.canPump)
        #expect(m.states[.truck]?.sirenEnabled == false)
        #expect(m.states[.house]?.alarmEnabled == false)
        #expect(m.states[.truck]?.beaconEnabled == true)
        #expect(m.states[.house]?.fanEnabled == true)
        let count = t.commands.count + h.commands.count
        t.presence(true)
        #expect(t.commands.count + h.commands.count == count)
        #expect(!(t.commands.contains { $0.action == .setPump }))
    }
    @Test @MainActor func testPartialExtinctionFailureCannotFinishAndRetryWorks() async {
        let (m, t, h) = setup(); arrive(m, t, h)
        m.setPump(true); t.ack(.setPump) { $0.pumpEnabled = true }
        m.setPump(false); t.ack(.setPump) { $0.pumpEnabled = false }
        #expect(m.phase == .intervention)
        #expect(m.states[.house]?.fireEnabled == true)
        m.confirmExtinction()
        t.ack(.setPump) { $0.pumpEnabled = false }
        t.ack(.setSiren); h.ack(.setAlarm)
        h.ack(.stopFire, success: false) { $0.fireEnabled = false; $0.fanEnabled = false }
        #expect(m.phase == .extinguishing)
        #expect(m.states[.house]?.fireEnabled == true)
        m.finish(); #expect(m.phase == .extinguishing)
        m.retryStops()
        t.ack(.setPump); t.ack(.setSiren); h.ack(.setAlarm); h.ack(.stopFire)
        #expect(m.phase == .extinguished)
        m.finish()
        t.ack(.emergencyStop) { $0 = .safe(.truck); $0.emergencyLocked = true }
        #expect(m.phase == .finishing)
        h.ack(.emergencyStop) { $0 = .safe(.house); $0.emergencyLocked = true }
        #expect(m.phase == .finished)
        m.newIntervention()
        t.ack(.rearm) { $0.emergencyLocked = false }
        h.ack(.rearm) { $0.emergencyLocked = false }
        #expect(m.phase == .preparation)
        #expect(!(m.pumpUsed))
    }
    @Test @MainActor func testPresenceLossSupersedesPendingActivationAndReturnNeedsUser() async {
        let (m, t, h) = setup(); arrive(m, t, h)
        m.setPump(true)
        let old = t.last(.setPump)
        t.presence(false)
        #expect(t.last(.setPump).payload.enabled == false)
        #expect(!(m.canPump))
        #expect(m.records.first { $0.id == old.id }?.status == .failed)
        t.ack(.setPump)
        let count = t.commands.count
        t.presence(true)
        #expect(t.commands.count == count)
        #expect(m.states[.truck]?.pumpEnabled == false)
        #expect(m.canPump)
    }
    @Test @MainActor func testDisconnectPausesClearsStateAndReconnectDoesNotReplay() async {
        let (m, t, h) = setup(); arrive(m, t, h)
        m.setPump(true); t.ack(.setPump) { $0.pumpEnabled = true }
        t.disconnect()
        #expect(m.paused); #expect(m.states[.truck] == nil); #expect(!(m.canPump))
        let replacement = TestBoard(.truck)
        m.install(replacement, for: .truck); replacement.ack(.getState)
        #expect(replacement.commands.map(\.action) == [.getState])
        #expect(m.paused)
        m.resume(); #expect(replacement.last(.setPump).payload.enabled == false)
        replacement.ack(.setPump)
        #expect(!(m.paused)); #expect(m.states[.truck]?.pumpEnabled == false)
    }
    @Test @MainActor func testEmergencyNeedsBothStopsAndExplicitRearm() async {
        let (m, t, h) = setup(); arrive(m, t, h)
        m.emergencyStop(); m.setPump(true)
        #expect(m.emergencyLocked); #expect(!(m.canPump)); #expect(!(m.canRearm))
        t.ack(.emergencyStop) { $0 = .safe(.truck); $0.emergencyLocked = true }
        #expect(!(m.canRearm))
        h.ack(.emergencyStop) { $0 = .safe(.house); $0.emergencyLocked = true }
        #expect(m.canRearm)
        m.rearm(); t.ack(.rearm) { $0.emergencyLocked = false }
        #expect(m.emergencyLocked)
        h.ack(.rearm) { $0.emergencyLocked = false }
        #expect(!(m.emergencyLocked)); #expect(m.phase == .preparation)
    }
    @Test @MainActor func testWrongRoleAndIncoherentAckRejected() async {
        let (m, _, h) = setup()
        m.startFire(); h.ack(.startFire)
        #expect(m.phase == .starting)
        #expect(m.records.last?.status == .failed)
        h.onEvent?(.message(WireMessage(type: "state", role: .truck, revision: 99, state: .safe(.truck))))
        #expect(m.connections[.house] == .disconnected)
        #expect(m.states[.house] == nil)
    }
    @Test @MainActor func testHouseDisconnectSupersedesPendingPumpStart() async {
        let (m, t, h) = setup(); arrive(m, t, h)
        m.setPump(true); h.disconnect()
        #expect(m.paused)
        #expect(t.last(.setPump).payload.enabled == false)
        t.ack(.setPump)
        #expect(!(m.canPump))
        #expect(m.states[.truck]?.pumpEnabled == false)
    }
    @Test @MainActor func testNozzleRangeAndExtinctionBeforePumpAreBlocked() async {
        let (m, t, h) = setup(); arrive(m, t, h)
        m.confirmExtinction(); #expect(m.phase == .intervention)
        m.nozzleMinimum = 80; m.nozzleMaximum = 100
        m.aim(120); #expect(!(t.commands.contains { $0.action == .setNozzleAngle }))
        m.aim(90); #expect(t.last(.setNozzleAngle).payload.angle == 90)
        t.ack(.setNozzleAngle) { $0.nozzleAngle = 90; $0.servoStopped = false }
        m.nozzleMinimum = 110
        #expect(!(m.canAim))
    }
    @Test @MainActor func testCommandTimeoutInvalidatesConnectionAndNeverConfirms() async throws {
        let (m, _, _) = setup()
        m.startFire()
        try await Task.sleep(for: .milliseconds(4300))
        #expect(m.connections[.house] == .disconnected)
        #expect(m.states[.house] == nil)
        #expect(m.paused)
        #expect(m.phase == .starting)
        #expect(m.records.last { $0.role == .house && $0.action == .startFire }?.status == .failed)
    }
    @Test @MainActor func testStaleSnapshotCannotRestoreOldPumpOutput() async {
        let (m, t, h) = setup(); arrive(m, t, h)
        m.setPump(true); t.ack(.setPump) { $0.pumpEnabled = true }
        let revision = t.revision
        let oldState = t.state
        t.presence(false)
        t.ack(.setPump)
        t.onEvent?(.message(WireMessage(type: "state", role: .truck, revision: revision, state: oldState)))
        #expect(!(m.onScene))
        #expect(m.states[.truck]?.pumpEnabled == false)
    }
    @Test @MainActor func testCallResponsesWaitForFireAndAnswerDoesNotAcceptMission() async {
        let (m, t, h) = setup()
        m.startFire()
        m.answerCall(); m.acceptIntervention()
        #expect(m.phase == .starting)
        #expect(t.commands.map(\.action) == [.getState])
        h.ack(.startFire) { $0.fireEnabled = true; $0.fanEnabled = true; $0.alarmEnabled = true }
        m.answerCall()
        #expect(m.phase == .briefing)
        #expect(t.commands.map(\.action) == [.getState])
        m.acceptIntervention()
        let count = t.commands.count
        m.answerCall(); m.acceptIntervention()
        #expect(m.phase == .departure)
        #expect(t.commands.count == count)
    }
    @Test @MainActor func testCallResponsesCannotBypassEmergencyOrDisconnectedBoard() async {
        let (m, t, h) = setup()
        m.startFire()
        h.ack(.startFire) { $0.fireEnabled = true; $0.fanEnabled = true; $0.alarmEnabled = true }
        h.disconnect()
        m.answerCall(); m.acceptIntervention()
        #expect(m.phase == .incomingCall)
        #expect(!t.commands.contains { $0.action == .setBeacon || $0.action == .setSiren })
        m.emergencyStop()
        m.answerCall(); m.acceptIntervention()
        #expect(m.emergencyLocked)
        #expect(m.phase == .incomingCall)
        #expect(!t.commands.contains { $0.action == .setBeacon || $0.action == .setSiren })
    }
    @Test @MainActor func testAdministrationWaitsForAckAndBlocksMissionUntilStopped() async {
        let (m, _, h) = setup()
        m.setHouseEquipment(.setFireLEDs, enabled: true)
        #expect(m.states[.house]?.fireEnabled == false)
        #expect(!m.canStart)
        #expect(!m.canChangeConfiguration)
        m.startFire()
        #expect(m.phase == .preparation)
        h.ack(.setFireLEDs) { $0.fireEnabled = true }
        #expect(m.states[.house]?.fanEnabled == false)
        #expect(!m.canStart)
        m.setHouseEquipment(.setFireLEDs, enabled: false)
        h.ack(.setFireLEDs) { $0.fireEnabled = false }
        #expect(m.canStart)
        #expect(m.canChangeConfiguration)
    }
    @Test @MainActor func testAdministrationRespectsScenarioAndEmergency() async {
        let (m, t, h) = setup()
        arrive(m, t, h)
        let before = h.commands.count
        m.setHouseEquipment(.setFan, enabled: false)
        m.setHouseEquipment(.setAlarm, enabled: true)
        #expect(h.commands.count == before)
        m.emergencyStop()
        let afterStop = h.commands.count
        m.setHouseEquipment(.setFireLEDs, enabled: true)
        #expect(h.commands.count == afterStop)
        #expect(!m.canAdministerHouse)
    }
    @Test @MainActor func testSimulatedAdminOutputsAreIndependent() async throws {
        let m = InterventionCoordinator()
        m.connect()
        try await Task.sleep(for: .milliseconds(300))
        for action in [Action.setAlarm, .setFan, .setFireLEDs] {
            m.setHouseEquipment(action, enabled: true)
            try await Task.sleep(for: .milliseconds(300))
        }
        #expect(m.phase == .preparation)
        #expect(m.states[.house]?.alarmEnabled == true)
        #expect(m.states[.house]?.fanEnabled == true)
        #expect(m.states[.house]?.fireEnabled == true)
        m.setHouseEquipment(.setFireLEDs, enabled: false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(m.states[.house]?.fireEnabled == false)
        #expect(m.states[.house]?.fanEnabled == true)
        #expect(m.states[.house]?.alarmEnabled == true)
    }
    @Test func testJSONRoundTripUsesExpectedEnvelope() throws {
        let command = Command(action: .setPump, payload: Payload(enabled: true))
        let data = try JSONEncoder().encode(command)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "command")
        #expect(json["action"] as? String == "setPump")
        #expect(try JSONDecoder().decode(Command.self, from: data) == command)
        let message = WireMessage(type: "state", role: .house, revision: 1, state: .safe(.house))
        let decoded = try JSONDecoder().decode(WireMessage.self, from: JSONEncoder().encode(message))
        #expect(decoded.state.isComplete(for: .house))
    }
    @Test @MainActor func testSimulationCompleteJourneyWithoutNetwork() async throws {
        let m = InterventionCoordinator()
        func wait() async throws { try await Task.sleep(for: .milliseconds(300)) }
        m.connect(); try await wait()
        #expect(m.canStart)
        m.startFire(); try await wait(); #expect(m.phase == .incomingCall)
        m.answerCall(); m.acceptIntervention(); try await wait()
        m.confirmDeparture(); m.simulatePresence(true); try await wait()
        #expect(m.phase == .intervention)
        m.setPump(true); try await wait(); #expect(m.pumpUsed)
        m.confirmExtinction(); try await wait(); #expect(m.phase == .extinguished)
        m.finish(); try await wait(); #expect(m.phase == .finished)
        m.newIntervention(); try await wait(); #expect(m.canStart)
    }
}
