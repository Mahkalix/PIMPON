import SwiftUI
import UserNotifications
import Observation
import FireControlCore

@main struct FireControlApp: App {
    @State private var coordinator: InterventionCoordinator
    @State private var callNotifications: CallNotifications

    init() {
        let model = InterventionCoordinator()
        _coordinator = State(initialValue: model)
        _callNotifications = State(initialValue: CallNotifications(model: model))
    }

    var body: some Scene {
        WindowGroup { ControlView(model: coordinator, callNotifications: callNotifications) }
    }
}

/// A local notification, never a telephone/VoIP call. All responses are checked
/// against the current call token and the coordinator's safety interlocks.
@MainActor @Observable final class CallNotifications: NSObject, UNUserNotificationCenterDelegate {
    private(set) var permission: UNAuthorizationStatus = .notDetermined
    private(set) var error: String?
    private(set) var requestingPermission = false
    @ObservationIgnored private let model: InterventionCoordinator
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var activeID: String?
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    private static let category = "FIRE_CONTROL_SIMULATED_CALL"
    private static let answer = "ANSWER_SIMULATED_CALL"

    init(model: InterventionCoordinator) {
        self.model = model
        super.init()
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Self.answer, title: "Accepter", options: [.foreground])
        ]
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: [], options: [.customDismissAction])])
        // This app does not restore an intervention after process termination.
        // Discard its old call alerts instead of allowing them to start a new run.
        Task { [weak self] in
            guard let self else { return }
            let requests = await self.center.pendingNotificationRequests()
            self.center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.content.categoryIdentifier == Self.category && $0.identifier != self.activeID }.map(\.identifier))
            let delivered = await self.center.deliveredNotifications()
            self.center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.content.categoryIdentifier == Self.category && $0.request.identifier != self.activeID }.map { $0.request.identifier })
            await self.refreshPermission()
        }
    }

    var enabled: Bool { permission == .authorized || permission == .provisional || permission == .ephemeral }

    func refreshPermission() async {
        permission = await center.notificationSettings().authorizationStatus
    }

    func requestPermission() async {
        guard !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            error = nil
        } catch { self.error = "Notifications indisponibles. L’appel reste accessible dans l’application." }
        await refreshPermission()
    }

    /// Invoked when the scenario or safety state changes, never by a timer.
    func synchronize() {
        guard model.phase == .incomingCall, model.controlsAvailable else {
            cancelCall()
            return
        }
        guard activeID == nil else { return }
        let id = UUID().uuidString
        activeID = id
        error = nil
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshPermission()
            guard !Task.isCancelled, self.activeID == id, self.enabled else { return }
            let content = UNMutableNotificationContent()
            content.title = "Centre d’alerte"
            content.subtitle = "Appel entrant simulé · Fire Control"
            content.body = "Un incendie simulé est signalé. Maintenez la notification pour accepter l’appel."
            content.categoryIdentifier = Self.category
            content.threadIdentifier = "fire-control-calls"
            content.sound = .default
            // Ordinary notifications respect Focus, silent mode and user settings.
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            do {
                try await self.center.add(request)
                if Task.isCancelled || self.activeID != id {
                    self.remove(id)
                }
            } catch {
                if self.activeID == id { self.error = "La notification n’a pas pu être affichée. Répondez depuis la bannière de l’application." }
            }
        }
    }

    func cancelCall() {
        deliveryTask?.cancel()
        deliveryTask = nil
        if let id = activeID { remove(id) }
        activeID = nil
    }

    private func remove(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        return await MainActor.run {
            guard id == self.activeID, self.model.phase == .incomingCall, self.model.controlsAvailable else { return [] }
            return [.banner, .list, .sound]
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        await MainActor.run {
            guard id == self.activeID, self.model.phase == .incomingCall, self.model.controlsAvailable else {
                self.remove(id)
                return
            }
            switch action {
            case Self.answer: self.model.answerCall()
            default: return // Opening or dismissing an alert never accepts a mission.
            }
            self.cancelCall()
        }
    }
}
