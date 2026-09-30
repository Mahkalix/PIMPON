import SwiftUI
import AVFoundation
import FireControlCore

private enum FireStyle {
    static let red = Color(red: 0.76, green: 0.09, blue: 0.15)
    static let background = Color(red: 0.045, green: 0.052, blue: 0.063)
    static let card = Color(red: 0.085, green: 0.097, blue: 0.115)
    static let signal = Color(red: 0.50, green: 0.86, blue: 0.90)
    static let line = Color.white.opacity(0.10)
    static let orange = Color(red: 1, green: 0.36, blue: 0.10)
    static let amber = Color(red: 1, green: 0.76, blue: 0.32)
}

struct ControlView: View {
    @Bindable var model: InterventionCoordinator
    @Bindable var callNotifications: CallNotifications
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAdministration = false
    @State private var administrationUnlocked = false
    @State private var administrationPassword = ""
    @State private var administrationPasswordError = false
    @State private var callVoice = AVSpeechSynthesizer()
    @State private var voiceEnabled = true
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        NavigationStack {
            List {
                missionHeader
                connections
                safetyStatus
                switch model.phase {
                case .preparation: preparation
                case .starting:
                    Section {
                        Label("Activation du faux feu demandée", systemImage: "flame.fill").font(.headline)
                        Text("En attente des confirmations du ventilateur, des LED et de l’alarme.")
                            .foregroundStyle(.secondary)
                        action("Réessayer le déclenchement", symbol: "arrow.clockwise") { model.retryStart() }
                            .disabled(!model.controlsAvailable || model.hasPending(.house, .startFire))
                    } header: { sectionTitle("Déclenchement", symbol: "flame") }
                case .incomingCall:
                    Section {
                        Label("Le centre d’alerte vous appelle", systemImage: "phone.arrow.down.left.fill").font(.headline)
                        Text("Acceptez l’appel depuis la bannière en haut de l’écran ou la notification iOS.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let error = callNotifications.error { Text(error).font(.caption) }
                    }
                case .briefing: call
                case .finished: completed
                default: intervention
                }
                simulationTools
                equipment
                Section {
                    Label("Maison", systemImage: "house")
                    Text(houseSummary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(20)
            .scrollContentBackground(.hidden)
            .background(FireStyle.background)
            .navigationTitle("FIRE CONTROL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FireStyle.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("FIRE CONTROL").font(.system(.caption, design: .monospaced, weight: .semibold))
                        .tracking(1.5).foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        lockAdministration()
                        showingAdministration = true
                    } label: {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(FireStyle.orange)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Administration de la maison")
                    .accessibilityHint("Ouvre l’accès protégé par mot de passe")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.phase == .incomingCall && model.controlsAvailable { incomingCallBanner }
            }
            .safeAreaInset(edge: .bottom) {
                if model.phase != .finished { emergencyBar }
            }
        }
        .sheet(isPresented: $showingAdministration, onDismiss: lockAdministration) {
            if administrationUnlocked {
                administration
            } else {
                administrationLogin
            }
        }
        .preferredColorScheme(.dark)
        .tint(FireStyle.signal)
        .task { model.connect(); await callNotifications.refreshPermission() }
        .onChange(of: model.phase) { _, phase in
            callNotifications.synchronize()
            callVoice.stopSpeaking(at: .immediate)
            if phase == .briefing { speakBriefing() }
        }
        .onChange(of: model.controlsAvailable) { _, available in
            callNotifications.synchronize()
            if !available { callVoice.stopSpeaking(at: .immediate) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await callNotifications.refreshPermission() }
                callNotifications.synchronize()
            } else if phase == .background {
                callVoice.stopSpeaking(at: .immediate)
                lockAdministration()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.phase == .incomingCall)
    }

    // MARK: Mission

    private var missionHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Rectangle().fill(model.emergencyLocked ? FireStyle.red : FireStyle.signal)
                        .frame(width: 3, height: 14).accessibilityHidden(true)
                    Text(model.mode == .simulation ? "SIMULATION" : "MATÉRIEL")
                        .font(.system(.caption, design: .monospaced, weight: .medium)).tracking(1.2)
                    Spacer()
                    Text("\(BoardRole.allCases.filter { model.connections[$0] == .ready }.count)/2 connectés")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text(model.emergencyLocked ? "Arrêt d’urgence" : model.paused ? "Intervention en pause" : model.phase.rawValue)
                    .font(.system(.largeTitle, weight: .semibold)).tracking(-1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(headerDescription).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(FireStyle.line).frame(height: 1).accessibilityHidden(true)
            }
            .padding(.top, 12).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
    }

    private var headerDescription: String {
        if model.phase == .preparation && !model.emergencyLocked && !model.paused {
            return "Préparez le camion, puis déclenchez l’incendie pour recevoir l’appel."
        }
        if model.phase == .extinguishing { return "Extinction demandée. Confirmation des arrêts en cours." }
        return model.message
    }

    // MARK: Connexions et sécurité

    private var connections: some View {
        Section {
            ForEach(BoardRole.allCases, id: \.self) { role in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Text(name(role)).font(.body.weight(.medium))
                        Spacer(minLength: 16)
                        connectionStatus(role)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(name(role)).font(.body.weight(.medium))
                        connectionStatus(role)
                    }
                }
                .padding(.vertical, 5)
                .listRowBackground(FireStyle.card)
                .accessibilityElement(children: .combine)
            }
            ForEach(BoardRole.allCases, id: \.self) { role in
                if let error = model.errors[role] {
                    Label("\(name(role)) : \(error)", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.primary)
                }
            }
            if !model.ready {
                action("Connecter les équipements", symbol: "arrow.clockwise") { model.connect() }
            }
        } header: { sectionTitle("Connexions", symbol: "antenna.radiowaves.left.and.right") }
    }
    private func connectionStatus(_ role: BoardRole) -> some View {
        Label(connectionLabel(role), systemImage: model.connections[role] == .ready ? "checkmark" : "wifi.slash")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(model.connections[role] == .ready ? FireStyle.signal : Color.secondary)
    }

    @ViewBuilder private var safetyStatus: some View {
        if model.emergencyLocked {
            Section {
                Label("Commandes verrouillées", systemImage: "lock.shield.fill").font(.headline)
                Text("Les sorties sans confirmation restent inconnues.").foregroundStyle(.secondary)
                action("Réessayer les arrêts", symbol: "stop.circle", role: .destructive) { model.emergencyStop() }
                action("Réarmer et revenir à la préparation", symbol: "arrow.counterclockwise") { model.rearm() }
                    .disabled(!model.canRearm)
            } header: { sectionTitle("Sécurité locale", symbol: "shield.fill") }
        } else if model.paused {
            Section {
                Label("Intervention suspendue", systemImage: "pause.circle.fill").font(.headline)
                Text("Reconnectez les cartes, puis reprenez explicitement. La pompe ne redémarre jamais automatiquement.")
                    .foregroundStyle(.secondary)
                action("Reprendre après confirmation d’arrêt de la pompe", symbol: "play") { model.resume() }
                    .disabled(!model.ready)
            } header: { sectionTitle("Scénario en pause", symbol: "pause.fill") }
        }
    }
    private var emergencyBar: some View {
        VStack(spacing: 7) {
            Button(role: .destructive) { model.emergencyStop() } label: {
                Label("Arrêt d’urgence", systemImage: "stop.octagon.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(FireStyle.red).controlSize(.large)
            Text("Pour arrêter le véhicule, utilisez la télécommande.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Préparation

    private var preparation: some View {
        Section {
            Label("Réservoir rempli, tuyau installé, camion prêt.", systemImage: "drop")
                .font(.subheadline)
            Text("Vérifiez le niveau d’eau vous-même avant de commencer.")
                .font(.caption).foregroundStyle(.secondary)
            primaryAction("Déclencher l’incendie", symbol: "flame.fill") { model.startFire() }
                .disabled(!model.canStart)
        } header: { sectionTitle("Avant de commencer", symbol: "checklist") }
    }

    private var hardwareSettings: some View {
        Section {
            Picker("Mode", selection: Binding(get: { model.mode }, set: { model.configure(mode: $0); model.connect() })) {
                ForEach(RunMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(!model.canChangeConfiguration)
            if model.mode == .hardware {
                Text("L’iPhone et les deux cartes doivent partager le même réseau local.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("WebSocket camion", text: $model.truckAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityLabel("Adresse WebSocket du camion")
                    .disabled(!model.canChangeConfiguration)
                TextField("WebSocket maison", text: $model.houseAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityLabel("Adresse WebSocket de la maison")
                    .disabled(!model.canChangeConfiguration)
                action("Appliquer et connecter", symbol: "network") {
                    model.configure(mode: .hardware); model.connect()
                }.disabled(!model.canChangeConfiguration)
            }
        } header: { sectionTitle("Réglages matériels", symbol: "slider.horizontal.3") }
    }

    private var notificationSettings: some View {
        Group {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Appel en notification").font(.headline)
                        Text(callNotifications.enabled ? "Notification iOS avec son et actions. Les réglages de votre iPhone restent prioritaires." : "Autorisez les notifications pour recevoir l’appel simulé, même hors de l’application si l’alerte a déjà été envoyée.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "bell.badge.fill").foregroundStyle(.orange) }
                if callNotifications.permission == .denied {
                    action("Ouvrir les réglages de notifications", symbol: "gearshape") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } else if !callNotifications.enabled {
                    action("Autoriser les notifications d’appel", symbol: "bell.badge") {
                        Task { await callNotifications.requestPermission() }
                    }.disabled(callNotifications.requestingPermission)
                }
                if let error = callNotifications.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("Sans autorisation, l’appel reste affiché dans l’application. Il ne s’agit pas d’un appel téléphonique.")
            }
            Section {
                Toggle("Message vocal du centre d’alerte", isOn: $voiceEnabled)
                    .onChange(of: voiceEnabled) { _, enabled in
                        if !enabled { callVoice.stopSpeaking(at: .immediate) }
                    }
            }
        }
    }

    // MARK: Faux appel

    private var incomingCallBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.title2).foregroundStyle(.orange)
                    .frame(width: 48, height: 48)
                    .background(.orange.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Centre d’alerte").font(.headline)
                    Text("Appel entrant simulé").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "waveform").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            callBannerAction
        }
        .padding(16)
        .background(FireStyle.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(FireStyle.line) }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appel entrant simulé du centre d’alerte")
    }

    private var callBannerAction: some View {
        Button {
            model.answerCall()
            callNotifications.synchronize()
        } label: {
            Label("Accepter", systemImage: "phone.fill")
                .font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.borderedProminent).tint(Color(red: 0.12, green: 0.47, blue: 0.28))
    }

    private var briefingText: String {
        "Centre d’alerte. Un départ de feu est signalé dans la maison. Rendez-vous sur place avec le camion, puis utilisez la pompe pour intervenir."
    }

    private func speakBriefing() {
        guard voiceEnabled, model.phase == .briefing, model.controlsAvailable else { return }
        callVoice.stopSpeaking(at: .immediate)
        let speech = AVSpeechUtterance(string: briefingText)
        speech.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        speech.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        callVoice.speak(speech)
    }

    private var call: some View {
        Section {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill").font(.title2).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Centre d’alerte").font(.title2.weight(.semibold))
                        Text("Appel simulé · message reçu").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(briefingText).font(.body).fixedSize(horizontal: false, vertical: true)
                if voiceEnabled {
                    HStack {
                        Button("Réécouter", systemImage: "speaker.wave.2", action: speakBriefing)
                            .frame(minHeight: 44).disabled(!model.controlsAvailable)
                        Spacer()
                        Button("Couper le son", systemImage: "speaker.slash") {
                            callVoice.stopSpeaking(at: .immediate)
                        }.frame(minHeight: 44)
                    }.font(.subheadline)
                }
                primaryAction("Accepter l’intervention", symbol: "checkmark") { model.acceptIntervention() }
                    .disabled(!model.controlsAvailable)
            }.padding(.vertical, 12)
        }
    }

    // MARK: Intervention

    private var intervention: some View {
        Group {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.onScene ? "Camion sur place" : "Camion hors zone").font(.headline)
                        Text(model.onScene ? "Présence détectée. Arrêtez le camion avec la télécommande." : "Déplacement avec la télécommande, sans suivi de position.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: model.onScene ? "mappin.circle.fill" : "location.slash").foregroundStyle(model.onScene ? Color.green : Color.secondary) }
                .padding(.vertical, 6)
                if [.departure, .travelling].contains(model.phase) {
                    action(model.states[.truck]?.beaconEnabled == true ? "Arrêter le gyrophare" : "Activer le gyrophare", symbol: "light.beacon.max.fill") { model.setBeacon(model.states[.truck]?.beaconEnabled != true) }
                        .disabled(!model.controlsAvailable || model.hasPending(.truck, .setBeacon))
                    action(model.states[.truck]?.sirenEnabled == true ? "Arrêter la sirène" : "Activer la sirène", symbol: "speaker.wave.2.fill") { model.setSiren(model.states[.truck]?.sirenEnabled != true) }
                        .disabled(!model.controlsAvailable || model.hasPending(.truck, .setSiren))
                }
                if model.phase == .departure {
                    primaryAction("Confirmer le départ", symbol: "flag.fill") { model.confirmDeparture() }
                        .disabled(!model.controlsAvailable || model.states[.truck]?.beaconEnabled != true || model.states[.truck]?.sirenEnabled != true)
                }
            } header: { sectionTitle("Position du camion", symbol: "truck.box.fill") }
            if model.phase == .intervention {
                Section {
                    primaryAction("Activer la pompe", symbol: "drop.fill", tint: FireStyle.signal) { model.setPump(true) }
                        .disabled(!model.canPump || model.states[.truck]?.pumpEnabled == true)
                    action("Arrêter la pompe", symbol: "stop.fill") { model.setPump(false) }
                        .disabled(model.connections[.truck] != .ready || model.emergencyLocked)
                } header: { sectionTitle("Pompe", symbol: "drop.fill") }
                Section {
                    Text("Lorsque vous estimez l’incendie éteint, appuyez sur Confirmer l’extinction.")
                        .font(.callout).foregroundStyle(.secondary)
                    primaryAction("Confirmer l’extinction", symbol: "checkmark.shield.fill") { model.confirmExtinction() }
                        .disabled(!model.canConfirmExtinction)
                    if !model.pumpUsed { Label("Une activation confirmée de la pompe est nécessaire.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                } header: { sectionTitle("Extinction", symbol: "flame") }
            }
            if [.intervention, .extinguishing, .extinguished, .finishing].contains(model.phase) {
                Section {
                    if model.phase == .extinguishing {
                        Label("Arrêts en attente de confirmation", systemImage: "hourglass").font(.headline)
                        Text("La pompe et la maison doivent confirmer leur arrêt.").foregroundStyle(.secondary)
                    }
                    action("Réessayer les commandes d’arrêt", symbol: "arrow.clockwise") { model.retryStops() }
                        .disabled(model.emergencyLocked)
                    if model.phase == .extinguished {
                        primaryAction("Terminer l’intervention", symbol: "checkmark.seal.fill") { model.finish() }.disabled(!model.controlsAvailable)
                    }
                } header: { sectionTitle("Arrêts & fin", symbol: "checkmark.shield") }
            }
        }
    }
    private var completed: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(.green).accessibilityHidden(true)
                Text("Intervention terminée").font(.system(.title2, weight: .semibold))
                Text("Intervention terminée. Les équipements sont confirmés à l’arrêt.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                primaryAction("Préparer une nouvelle intervention", symbol: "arrow.counterclockwise") { model.newIntervention() }
                    .disabled(!model.canRearm)
            }.padding(.vertical, 16).frame(maxWidth: .infinity)
        }
    }

    // MARK: Sorties et journal

    private var equipment: some View {
        Section {
            output("Pompe", symbol: "drop.fill", state: model.states[.truck]?.pumpEnabled, role: .truck, actions: [.setPump], color: .blue)
            output("Gyrophare", symbol: "light.beacon.max.fill", state: model.states[.truck]?.beaconEnabled, role: .truck, actions: [.setBeacon], color: .orange)
            output("Sirène du camion", symbol: "speaker.wave.2.fill", state: model.states[.truck]?.sirenEnabled, role: .truck, actions: [.setSiren], color: .orange)
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Servo").font(.subheadline.weight(.semibold))
                    Text(model.states[.truck]?.servoStopped.map { $0 ? "Arrêt confirmé" : "Consigne appliquée" } ?? "Inconnu · non confirmé")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.hasPending(.truck, .setNozzleAngle) || model.hasPending(.truck, .emergencyStop) {
                        Label("Commande en attente", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: { symbolTile("scope", color: .blue) }
        } header: {
            sectionTitle(model.mode == .simulation ? "Équipements · simulés" : "Équipements · états confirmés", symbol: "switch.2")
        } footer: {
            Text("Une sortie confirmée ne prouve ni un débit d’eau, ni un mouvement réel. Les sorties de la maison sont détaillées dans Administration.")
        }
    }
    private var houseSummary: String {
        guard let house = model.states[.house] else { return "Maison : sorties inconnues, arrêts non confirmés." }
        let pending = [Action.setAlarm, .setFan, .setFireLEDs, .startFire, .stopFire, .emergencyStop].contains { model.hasPending(.house, $0) }
        if pending { return "Maison : commande en attente de confirmation." }
        if house.allStopped(.house) { return "Maison : tous les équipements sont confirmés à l’arrêt." }
        return "Maison : équipements actifs. Consultez les détails dans Administration."
    }

    private func lockAdministration() {
        administrationUnlocked = false
        administrationPassword = ""
        administrationPasswordError = false
    }

    private func unlockAdministration() {
        guard administrationPassword == "PIMPOM" else {
            administrationPasswordError = true
            administrationPassword = ""
            return
        }
        administrationPassword = ""
        administrationPasswordError = false
        administrationUnlocked = true
    }

    private var administrationLogin: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Accès administration", systemImage: "lock")
                        .font(.headline)
                    Text("Saisissez le mot de passe pour accéder aux réglages et aux commandes de la maison.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    SecureField("Mot de passe", text: $administrationPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(unlockAdministration)
                        .accessibilityLabel("Mot de passe administration")
                    if administrationPasswordError {
                        Label("Mot de passe incorrect. Réessayez.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red).font(.callout)
                    }
                    primaryAction("Déverrouiller", symbol: "lock.open", perform: unlockAdministration)
                        .disabled(administrationPassword.isEmpty)
                }
            }
            .scrollContentBackground(.hidden).background(FireStyle.background)
            .navigationTitle("Administration").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { showingAdministration = false }
                }
            }
            .safeAreaInset(edge: .bottom) { emergencyBar }
        }.preferredColorScheme(.dark).tint(FireStyle.signal)
    }

    private var administration: some View {
        NavigationStack {
            List {
                hardwareSettings
                notificationSettings
                if model.mode == .simulation {
                    Section("Tests de connexion") {
                        ForEach(BoardRole.allCases, id: \.self) { role in
                            action("Déconnecter · \(name(role))", symbol: "wifi.slash") { model.simulateDisconnect(role) }
                                .disabled(model.connections[role] != .ready)
                        }
                    }
                }

                Section {
                    Label("Maison · \(model.mode.rawValue)", systemImage: "house.fill").font(.headline)
                    Text(connectionLabel(.house)).foregroundStyle(.secondary)
                    if let error = model.errors[.house] {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                    }
                    Text("Testez les équipements avant la mission. Les commandes manuelles sont disponibles en préparation ; pendant l’intervention, le scénario pilote la maison.")
                        .font(.callout).foregroundStyle(.secondary)
                    if model.emergencyLocked {
                        Label("Arrêt d’urgence : commandes verrouillées", systemImage: "lock.shield.fill")
                    }
                }
                adminEquipment("Alarme de la maison", symbol: "bell.fill", state: model.states[.house]?.alarmEnabled, action: .setAlarm, related: [.startFire, .setAlarm], color: .orange)
                adminEquipment("Ventilateur", symbol: "fan.fill", state: model.states[.house]?.fanEnabled, action: .setFan, related: [.startFire, .stopFire, .setFan], color: .teal)
                adminEquipment("LED du faux feu", symbol: "flame.fill", state: model.states[.house]?.fireEnabled, action: .setFireLEDs, related: [.startFire, .stopFire, .setFireLEDs], color: .orange)
                Section {
                    Text("Remettez les trois équipements à l’arrêt avant de déclencher une mission. Une sortie appliquée n’est pas une mesure physique.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(FireStyle.background)
            .navigationTitle("Administration").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { showingAdministration = false }
                }
            }
            .safeAreaInset(edge: .bottom) { emergencyBar }
        }.preferredColorScheme(.dark).tint(FireStyle.orange)
    }

    private func adminEquipment(_ title: String, symbol: String, state: Bool?, action: Action, related: [Action], color: Color) -> some View {
        Section {
            output(title, symbol: symbol, state: state, role: .house, actions: related, color: color)
            Button {
                model.setHouseEquipment(action, enabled: true)
            } label: { Label("Activer", systemImage: "power").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canAdministerHouse || state == true)
            Button {
                model.setHouseEquipment(action, enabled: false)
            } label: { Label("Arrêter", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.bordered)
                .disabled(!model.canAdministerHouse || state == false)
        }
    }

    @ViewBuilder private var simulationTools: some View {
        if model.mode == .simulation && [.travelling, .intervention].contains(model.phase) {
            Section {
                if [.travelling, .intervention].contains(model.phase) {
                    primaryAction(model.onScene ? "Simuler la sortie de zone" : "Simuler l’arrivée", symbol: "mappin.and.ellipse", tint: FireStyle.signal) {
                        model.simulatePresence(!model.onScene)
                    }.disabled(!model.controlsAvailable)
                }
            } header: { sectionTitle("Simulation", symbol: "play.rectangle") }
        }
    }
    // MARK: Composants natifs partagés

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .tracking(1).foregroundStyle(.secondary).textCase(nil)
    }
    private func symbolTile(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .regular))
            .foregroundStyle(.secondary).frame(width: 28, height: 32)
            .accessibilityHidden(true)
    }
    private func connectionLabel(_ role: BoardRole) -> String {
        switch model.connections[role] ?? .disconnected {
        case .ready: return "Connecté · état reçu"
        case .connecting: return "Connexion en cours"
        case .disconnected: return "Déconnecté"
        }
    }
    private func output(_ label: String, symbol: String, state: Bool?, role: BoardRole, actions: [Action], color: Color) -> some View {
        HStack(spacing: 12) {
            symbolTile(symbol, color: color)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline.weight(.semibold))
                Text(state.map { $0 ? "Actif · confirmé" : "À l’arrêt · confirmé" } ?? "Inconnu · non confirmé")
                    .font(.caption).foregroundStyle(.secondary)
                if actions.contains(where: { model.hasPending(role, $0) }) || model.hasPending(role, .emergencyStop) {
                    Label("Commande en attente", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: state.map { $0 ? "bolt.circle.fill" : "checkmark.circle" } ?? "questionmark.circle")
                .foregroundStyle(state == true ? color : Color.secondary).accessibilityHidden(true)
        }.padding(.vertical, 3).accessibilityElement(children: .combine)
    }
    private func name(_ role: BoardRole) -> String { role == .truck ? "Camion" : "Maison" }
    private func action(_ title: String, symbol: String, role: ButtonRole? = nil, perform: @escaping () -> Void) -> some View {
        Button(role: role, action: perform) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 10))
    }
    private func primaryAction(_ title: String, symbol: String, tint: Color = FireStyle.signal, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36).fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large).tint(tint)
        .foregroundStyle(tint == FireStyle.signal ? FireStyle.background : Color.white)
    }
}
