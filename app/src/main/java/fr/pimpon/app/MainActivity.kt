package fr.pimpon.app

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fr.pimpon.firecontrol.core.*

private enum class AppRole(val title: String) { FIREFIGHTER("Pompier"), ADMIN("Admin") }

private val Ink = Color(0xFF0D151D)
private val Panel = Color(0xFF192530)
private val PanelRaised = Color(0xFF223340)
private val FireRed = Color(0xFFFF554F)
private val SignalLime = Color(0xFFB7F17A)
private val Muted = Color(0xFF9BAAB6)

class MainActivity : ComponentActivity() {
    private val relay = AlertRelay()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val coordinator = InterventionCoordinator()
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(
                primary = SignalLime, onPrimary = Ink, secondary = FireRed, onSecondary = Color.White,
                background = Ink, surface = Panel, surfaceVariant = PanelRaised,
                onBackground = Color(0xFFF5F7F8), onSurface = Color(0xFFF5F7F8),
                error = FireRed
            )) { FireControlApp(coordinator, relay) }
        }
    }

    override fun onDestroy() {
        relay.stop()
        super.onDestroy()
    }
}

@Composable
private fun FireControlApp(coordinator: InterventionCoordinator, relay: AlertRelay) {
    val state by coordinator.state.collectAsState()
    var role by remember { mutableStateOf(AppRole.FIREFIGHTER) }
    var relayStatus by remember { mutableStateOf("Pas encore connecté au centre") }
    var remoteStatus by remember { mutableStateOf("En attente du téléphone pompier") }
    var adminAddress by remember { mutableStateOf("") }
    var angle by remember { mutableFloatStateOf(90f) }
    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    val onStatus: (String) -> Unit = { value -> mainHandler.post { relayStatus = value } }
    val onRemoteStatus: (String) -> Unit = { value -> mainHandler.post { remoteStatus = value } }
    val onAlert: () -> Unit = { mainHandler.post { coordinator.receiveRemoteCall() } }

    LaunchedEffect(Unit) { coordinator.connect() }
    LaunchedEffect(state.nozzleMinimum, state.nozzleMaximum) { angle = angle.coerceIn(state.nozzleMinimum, state.nozzleMaximum) }
    LaunchedEffect(role, relayStatus, state.phase, state.onScene, state.boards[BoardRole.truck]?.pumpEnabled, state.boards[BoardRole.truck]?.drivingDirection, state.boards[BoardRole.house]?.fireEnabled) {
        if (role == AppRole.FIREFIGHTER) relay.sendStatus("${state.phase.label} · ${if (state.onScene) "sur les lieux" else "en déplacement / en attente"} · pompe ${output(state.boards[BoardRole.truck]?.pumpEnabled)} · feu ${output(state.boards[BoardRole.house]?.fireEnabled)}")
    }

    Scaffold(
        containerColor = Ink,
        bottomBar = {
            if (role == AppRole.FIREFIGHTER && state.phase !in setOf(Phase.PREPARATION, Phase.FINISHED)) {
                Column(Modifier.fillMaxWidth().background(Ink).padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Button(
                        onClick = coordinator::emergencyStop,
                        colors = ButtonDefaults.buttonColors(containerColor = FireRed, contentColor = Color.White),
                        shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth().height(54.dp)
                    ) { Text("ARRÊT D’URGENCE", fontWeight = FontWeight.Black, letterSpacing = 1.sp) }
                    Text("L’arrêt d’urgence ne remplace pas l’arrêt physique du camion.", color = Muted, fontSize = 11.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 5.dp))
                }
            }
        }
    ) { inset ->
        Column(
            Modifier.fillMaxSize().padding(inset).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Header(role, onRoleChange = { role = it })
            if (state.emergencyLocked && role == AppRole.FIREFIGHTER) EmergencyLockedCard(state, coordinator)
            when (role) {
                AppRole.ADMIN -> AdminDashboard(state, relay, relayStatus, remoteStatus, onStatus, onRemoteStatus, coordinator)
                AppRole.FIREFIGHTER -> FirefighterDashboard(state, relay, relayStatus, adminAddress, { adminAddress = it }, onStatus, onAlert, coordinator, angle, { angle = it })
            }
            Spacer(Modifier.height(10.dp))
        }
    }
}

@Composable
private fun Header(role: AppRole, onRoleChange: (AppRole) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Column {
            Text("PIMPON", fontSize = 22.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp)
            Text("CENTRE DE SECOURS", fontSize = 10.sp, color = Muted, letterSpacing = 1.6.sp)
        }
        Row(Modifier.background(Panel, CircleShape).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            AppRole.entries.forEach { item ->
                val selected = role == item
                TextButton(
                    onClick = { onRoleChange(item) },
                    colors = ButtonDefaults.textButtonColors(contentColor = if (selected) Ink else Muted),
                    modifier = Modifier.background(if (selected) SignalLime else Color.Transparent, CircleShape).height(38.dp)
                ) { Text(item.title, fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium) }
            }
        }
    }
}

@Composable
private fun AdminDashboard(
    state: AppState, relay: AlertRelay, relayStatus: String, remoteStatus: String,
    onStatus: (String) -> Unit, onRemoteStatus: (String) -> Unit, coordinator: InterventionCoordinator
) {
    val address = remember { AlertRelay.localIpv4() }
    HeroCard(eyebrow = "MODE ORGANISATION", title = "Centre de secours", body = "Préparez la scène puis envoyez un faux appel au téléphone du pompier.", accent = SignalLime) {
        Text("LIAISON TÉLÉPHONE", style = MaterialTheme.typography.labelLarge, color = Muted, letterSpacing = 1.sp)
        Text(relayStatus, fontWeight = FontWeight.SemiBold)
        if (address != null) {
            Text("Adresse du centre", color = Muted, fontSize = 12.sp)
            Text("$address:${AlertRelay.PORT}", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = SignalLime)
        } else Text("Adresse Wi‑Fi indisponible. Connectez ce téléphone au réseau local.", color = FireRed)
        ActionButton("Ouvrir le relais sur ce téléphone", address != null) {
            onRemoteStatus("En attente du téléphone pompier")
            relay.startHost(onStatus, onRemoteStatus)
        }
        Text("Sur l’autre téléphone, choisissez Pompier et connectez-vous à cette adresse. Gardez les deux applications ouvertes sur le même Wi‑Fi.", color = Muted, fontSize = 12.sp)
    }

    HeroCard(eyebrow = "DÉCLENCHEMENT", title = "Prêt à lancer l’alerte ?", body = "Le faux feu est simulé par les LED, le ventilateur et l’alarme de la scène.", accent = FireRed) {
        StatusLine("État du scénario", state.phase.label)
        StatusLine("Connexion des cartes", if (state.ready) "Camion et maison prêts" else "Simulation / matériel en attente")
        Button(
            onClick = {
                val sent = relay.sendEmergencyCall()
                if (sent) onStatus("Appel d’urgence envoyé au téléphone pompier")
                else if (relay.isHosting()) onStatus("Aucun téléphone pompier connecté. Connectez-le à l’adresse ci-dessus.")
                else onStatus("Aucun relais ouvert : ouvrez-le ou utilisez le test sur cet appareil.")
            },
            enabled = state.phase == Phase.PREPARATION && !state.emergencyLocked,
            colors = ButtonDefaults.buttonColors(containerColor = FireRed, contentColor = Color.White),
            shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth().height(62.dp)
        ) { Text("🚨   DÉCLENCHER LE FAUX APPEL", fontWeight = FontWeight.Black, letterSpacing = .4.sp) }
        OutlinedButton(onClick = coordinator::startFire, enabled = state.phase == Phase.PREPARATION && state.controls, modifier = Modifier.fillMaxWidth()) { Text("Tester le scénario sur ce téléphone") }
        Text("La liaison entre téléphones fonctionne sur le réseau local de démonstration. Le téléphone pompier lance les équipements associés à son propre scénario.", color = Muted, fontSize = 12.sp)
    }

    if (state.emergencyLocked) EmergencyLockedCard(state, coordinator)
    if (state.phase == Phase.FINISHED) {
        val canRearm = state.ready && state.records.none { it.status == CommandRecord.Status.PENDING } && BoardRole.entries.all { state.boards[it]?.allStopped(it) == true }
        ActionButton("Réarmer la scène", canRearm, coordinator::newIntervention)
    }

    if (state.phase == Phase.PREPARATION) AdminEquipmentSetup(state, coordinator)
    AdminScenarioStatus(state, remoteStatus)
}

@Composable
private fun AdminEquipmentSetup(state: AppState, coordinator: InterventionCoordinator) {
    SectionCard("Préparer la scène") {
        Text("Mode de la maquette", color = Muted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            RunMode.entries.forEach { mode -> FilterChip(selected = state.mode == mode, onClick = { coordinator.setMode(mode) }, label = { Text(mode.label) }) }
        }
        Text("Remplir le réservoir, vérifier les alimentations, installer le tuyau et diriger la lance vers la zone de réception.", color = Muted)
        if (state.mode == RunMode.HARDWARE) {
            var truckAddress by remember(state.truckAddress) { mutableStateOf(state.truckAddress) }
            var houseAddress by remember(state.houseAddress) { mutableStateOf(state.houseAddress) }
            OutlinedTextField(truckAddress, { truckAddress = it; coordinator.updateAddress(BoardRole.truck, it) }, label = { Text("WebSocket camion") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(houseAddress, { houseAddress = it; coordinator.updateAddress(BoardRole.house, it) }, label = { Text("WebSocket maison") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            ActionButton("Connecter les deux cartes", true, coordinator::applyHardwareAddresses)
            var validated by remember(state.hardwareRangeValidated) { mutableStateOf(state.hardwareRangeValidated) }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = validated, onCheckedChange = { validated = it; coordinator.validateHardwareRange(it) })
                Text("Plage mécanique de la lance vérifiée", color = Muted, fontSize = 12.sp)
            }
        }
        Text("Plage de lance : ${state.nozzleMinimum.toInt()}° à ${state.nozzleMaximum.toInt()}°", color = Muted, fontSize = 12.sp)
        Text("Minimum", color = Muted, fontSize = 12.sp)
        Slider(value = state.nozzleMinimum, onValueChange = { coordinator.setNozzleRange(it, state.nozzleMaximum) }, valueRange = 0f..(state.nozzleMaximum - 1f).coerceAtLeast(1f))
        Text("Maximum", color = Muted, fontSize = 12.sp)
        Slider(value = state.nozzleMaximum, onValueChange = { coordinator.setNozzleRange(state.nozzleMinimum, it) }, valueRange = (state.nozzleMinimum + 1f).coerceAtMost(179f)..180f)
        Text("Camion : ${state.connections[BoardRole.truck]?.label} · Maison : ${state.connections[BoardRole.house]?.label}", fontSize = 12.sp, color = Muted)
        state.errors.values.forEach { Text(it, color = FireRed, fontSize = 12.sp) }
    }
}

@Composable
private fun AdminScenarioStatus(state: AppState, remoteStatus: String) {
    SectionCard("Suivi de l’intervention") {
        Text(if (remoteStatus == "En attente du téléphone pompier") "État du téléphone pompier : aucun retour reçu" else remoteStatus, color = if (remoteStatus == "En attente du téléphone pompier") Muted else SignalLime)
        if (state.phase != Phase.PREPARATION) {
            StatusLine("Scénario local", state.phase.label)
            StatusLine("Pompe locale", output(state.boards[BoardRole.truck]?.pumpEnabled))
            StatusLine("Feu local", output(state.boards[BoardRole.house]?.fireEnabled))
        }
    }
}

@Composable
private fun FirefighterDashboard(
    state: AppState, relay: AlertRelay, relayStatus: String, adminAddress: String,
    onAddressChange: (String) -> Unit, onStatus: (String) -> Unit, onAlert: () -> Unit,
    coordinator: InterventionCoordinator, angle: Float, onAngle: (Float) -> Unit
) {
    when (state.phase) {
        Phase.PREPARATION -> {
            HeroCard(eyebrow = "GARDE · CENTRE DE SECOURS", title = "En attente d’une alerte", body = "Restez prêt. Le centre de secours vous contactera dès qu’un départ sera nécessaire.", accent = SignalLime) {
                StatusLine("Liaison", relayStatus)
                OutlinedTextField(adminAddress, onAddressChange, label = { Text("Adresse du téléphone admin") }, placeholder = { Text("192.168.1.20") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                ActionButton("Se connecter au centre", adminAddress.isNotBlank()) { relay.connectToAdmin(adminAddress, onStatus, onAlert) }
                Text("Les deux téléphones doivent être sur le même Wi‑Fi. Laissez cette application ouverte pendant la démonstration.", color = Muted, fontSize = 12.sp)
            }
            SectionCard("Prêt au départ") {
                StatusLine("Camion", state.connections[BoardRole.truck]?.label ?: "Connexion…")
                StatusLine("Scène incendie", state.connections[BoardRole.house]?.label ?: "Connexion…")
                Text("Le réservoir se remplit manuellement avant la démonstration. Aucun niveau d’eau n’est mesuré.", color = Muted, fontSize = 12.sp)
            }
        }
        Phase.STARTING -> HeroCard("ALERTE REÇUE", "Préparation de l’intervention", "Activation du feu simulé et des équipements de la scène…", FireRed) { StatusLine("État", "Confirmation des cartes en cours") }
        Phase.INCOMING_CALL -> IncomingCallScreen(state, coordinator)
        Phase.BRIEFING -> HeroCard("CENTRE D’ALERTE", "ALERTE INCENDIE !", "Un incendie vient d’être détecté. Intervention nécessaire immédiatement.", FireRed) {
            Text("Unité demandée : camion de pompiers", color = Muted)
            Button(onClick = coordinator::acceptIntervention, enabled = state.controls, colors = ButtonDefaults.buttonColors(containerColor = SignalLime, contentColor = Ink), modifier = Modifier.fillMaxWidth().height(58.dp)) { Text("ACCEPTER L’INTERVENTION", fontWeight = FontWeight.Black) }
            if (!state.controls) Text("Connexion aux cartes nécessaire avant d’accepter le départ.", color = FireRed, fontSize = 12.sp)
        }
        Phase.DEPARTURE -> DepartureScreen(state, coordinator)
        Phase.TRAVELLING -> DrivingScreen(state, coordinator)
        Phase.INTERVENTION -> PumpScreen(state, coordinator, angle, onAngle)
        Phase.EXTINGUISHING -> HeroCard("INTERVENTION", "Arrêt des équipements", "La pompe, les LED et le ventilateur s’arrêtent. Confirmation en cours…", FireRed) { StatusLine("État des cartes", if (state.ready) "En attente des confirmations" else "Sortie inconnue") }
        Phase.EXTINGUISHED -> HeroCard("SCÈNE SÉCURISÉE", "Feu simulé éteint", "La pompe et les équipements du faux feu sont confirmés à l’arrêt.", SignalLime) {
            StatusLine("Gyrophare", output(state.boards[BoardRole.truck]?.beaconEnabled))
            Button(onClick = coordinator::finish, colors = ButtonDefaults.buttonColors(containerColor = SignalLime, contentColor = Ink), modifier = Modifier.fillMaxWidth().height(56.dp)) { Text("TERMINER L’INTERVENTION", fontWeight = FontWeight.Black) }
        }
        Phase.FINISHING -> HeroCard("RETOUR AU CALME", "Fin de l’intervention", "Arrêt du gyrophare et vérification finale des équipements…", SignalLime) { StatusLine("Confirmation", "En attente des cartes") }
        Phase.FINISHED -> HeroCard("MISSION ACCOMPLIE", "Intervention terminée", "Tous les équipements sont confirmés à l’arrêt. Vous pouvez préparer un nouveau départ.", SignalLime) {
            StatusLine("Pompe", output(state.boards[BoardRole.truck]?.pumpEnabled))
            StatusLine("Gyrophare", output(state.boards[BoardRole.truck]?.beaconEnabled))
            ActionButton("Retour en garde", state.ready && state.records.none { it.status == CommandRecord.Status.PENDING }, coordinator::newIntervention)
        }
    }
}

@Composable
private fun IncomingCallScreen(state: AppState, coordinator: InterventionCoordinator) {
    Column(Modifier.fillMaxWidth().background(Color(0xFF6E2527), RoundedCornerShape(28.dp)).padding(22.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("APPEL ENTRANT", color = Color(0xFFFFD1CB), fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
        Box(Modifier.size(88.dp).background(FireRed, CircleShape), contentAlignment = Alignment.Center) { Text("☎", fontSize = 40.sp, color = Color.White) }
        Text("Centre d’alerte", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("ALERTE INCENDIE !\nUn incendie vient d’être détecté.\nIntervention nécessaire immédiatement.", textAlign = TextAlign.Center, fontSize = 18.sp, lineHeight = 26.sp)
        Button(onClick = coordinator::answerCall, colors = ButtonDefaults.buttonColors(containerColor = SignalLime, contentColor = Ink), shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth().height(58.dp)) { Text("RÉPONDRE", fontWeight = FontWeight.Black, letterSpacing = 1.sp) }
        OutlinedButton(onClick = coordinator::acceptIntervention, enabled = state.controls, shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("Passer l’appel et accepter", color = Color.White) }
        if (!state.controls) Text("Le camion et la scène doivent être connectés pour accepter.", color = Color(0xFFFFD1CB), fontSize = 12.sp, textAlign = TextAlign.Center)
        Text("Appel fictif · aucun appel téléphonique réel", color = Color(0xFFFFD1CB), fontSize = 11.sp)
    }
}

@Composable
private fun DepartureScreen(state: AppState, coordinator: InterventionCoordinator) {
    HeroCard("DÉPART ACCEPTÉ", "Équipe, en route !", "Gyrophare et sirène activés. Prenez le contrôle du camion et confirmez le départ.", SignalLime) {
        StatusLine("Gyrophare", output(state.boards[BoardRole.truck]?.beaconEnabled))
        StatusLine("Sirène", output(state.boards[BoardRole.truck]?.sirenEnabled))
        Button(onClick = coordinator::confirmDeparture, enabled = state.controls && state.boards[BoardRole.truck]?.let { it.beaconEnabled == true && it.sirenEnabled == true } == true, colors = ButtonDefaults.buttonColors(containerColor = SignalLime, contentColor = Ink), modifier = Modifier.fillMaxWidth().height(58.dp)) { Text("CONFIRMER LE DÉPART", fontWeight = FontWeight.Black) }
    }
    RouteProgress(current = 1)
}

@Composable
private fun DrivingScreen(state: AppState, coordinator: InterventionCoordinator) {
    HeroCard("DÉPLACEMENT", "Camion en route", "Conduisez avec les commandes ci-dessous. À l’arrivée, le camion s’immobilise et la pompe reste verrouillée jusqu’à votre intervention.", SignalLime) {
        RouteProgress(current = 2)
        DrivePad(state, coordinator)
        if (state.mode == RunMode.SIMULATION) {
            OutlinedButton(onClick = { coordinator.simulatePresence(true) }, modifier = Modifier.fillMaxWidth().height(48.dp)) { Text("SIMULER L’ARRIVÉE SUR LES LIEUX") }
        }
    }
}

@Composable
private fun DrivePad(state: AppState, coordinator: InterventionCoordinator) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DriveButton("▲", "forward", state, coordinator)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DriveButton("◀", "left", state, coordinator)
            Button(onClick = coordinator::stopDriving, colors = ButtonDefaults.buttonColors(containerColor = PanelRaised), modifier = Modifier.size(72.dp)) { Text("STOP", fontWeight = FontWeight.Black, fontSize = 11.sp) }
            DriveButton("▶", "right", state, coordinator)
        }
        DriveButton("▼", "reverse", state, coordinator)
        Text("Appuyez sur une direction pour conduire. STOP coupe les moteurs.", color = Muted, fontSize = 11.sp, textAlign = TextAlign.Center)
    }
}

@Composable
private fun DriveButton(label: String, direction: String, state: AppState, coordinator: InterventionCoordinator) {
    Button(onClick = { coordinator.drive(direction) }, enabled = state.controls && !state.onScene, colors = ButtonDefaults.buttonColors(containerColor = PanelRaised), modifier = Modifier.size(72.dp)) { Text(label, fontSize = 24.sp, fontWeight = FontWeight.Bold) }
}

@Composable
private fun PumpScreen(state: AppState, coordinator: InterventionCoordinator, angle: Float, onAngle: (Float) -> Unit) {
    HeroCard("SUR LES LIEUX", "Protégez la maison", "Le camion est arrivé. Le gyrophare reste allumé; arrêtez le véhicule puis orientez la lance.", FireRed) {
        StatusLine("Présence sur zone", if (state.onScene) "Détectée" else "Non détectée")
        StatusLine("Gyrophare", output(state.boards[BoardRole.truck]?.beaconEnabled))
        StatusLine("Pompe", output(state.boards[BoardRole.truck]?.pumpEnabled))
        if (state.validRange) {
            Text("Orientation de la lance · ${angle.toInt()}°", color = Muted)
            Slider(value = angle.coerceIn(state.nozzleMinimum, state.nozzleMaximum), onValueChange = onAngle, valueRange = state.nozzleMinimum..state.nozzleMaximum, enabled = state.canAim)
            ActionButton("Appliquer l’orientation", state.canAim) { coordinator.aim(angle.toDouble()) }
        }
        Button(onClick = { coordinator.setPump(state.boards[BoardRole.truck]?.pumpEnabled != true) }, enabled = state.canPump || (state.connections[BoardRole.truck] == Connection.READY && state.boards[BoardRole.truck]?.pumpEnabled == true && !state.emergencyLocked), colors = ButtonDefaults.buttonColors(containerColor = if (state.boards[BoardRole.truck]?.pumpEnabled == true) PanelRaised else FireRed), modifier = Modifier.fillMaxWidth().height(58.dp)) {
            Text(if (state.boards[BoardRole.truck]?.pumpEnabled == true) "ARRÊTER LA POMPE" else "ACTIVER LA POMPE À EAU", fontWeight = FontWeight.Black)
        }
        Text("La pompe peut être arrêtée et redémarrée. L’extinction reste une confirmation manuelle.", color = Muted, fontSize = 12.sp)
        Button(onClick = coordinator::confirmExtinction, enabled = state.canConfirmExtinction, colors = ButtonDefaults.buttonColors(containerColor = SignalLime, contentColor = Ink), modifier = Modifier.fillMaxWidth().height(54.dp)) { Text("CONFIRMER L’EXTINCTION", fontWeight = FontWeight.Black) }
    }
}

@Composable
private fun RouteProgress(current: Int) {
    Row(Modifier.fillMaxWidth().background(Panel, RoundedCornerShape(18.dp)).padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        listOf("Caserne", "En route", "Maison").forEachIndexed { index, label ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(30.dp).background(if (index <= current) SignalLime else PanelRaised, CircleShape), contentAlignment = Alignment.Center) { Text(if (index < current) "✓" else "${index + 1}", color = if (index <= current) Ink else Muted, fontWeight = FontWeight.Bold) }
                Text(label, fontSize = 10.sp, color = if (index <= current) Color.White else Muted)
            }
            if (index < 2) Spacer(Modifier.width(20.dp))
        }
    }
}

@Composable
private fun EmergencyLockedCard(state: AppState, coordinator: InterventionCoordinator) {
    SectionCard("ARRÊT D’URGENCE · COMMANDES VERROUILLÉES") {
        Text(state.message, color = Color.White)
        ActionButton("Réessayer les arrêts", true, coordinator::emergencyStop)
        val canRearm = state.ready && state.records.none { it.status == CommandRecord.Status.PENDING } && BoardRole.entries.all { state.boards[it]?.allStopped(it) == true }
        ActionButton("Réarmer", canRearm, coordinator::rearm)
    }
}

@Composable
private fun HeroCard(eyebrow: String, title: String, body: String, accent: Color, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().background(Panel, RoundedCornerShape(26.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.width(42.dp).height(4.dp).background(accent, CircleShape))
        Text(eyebrow, color = accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.6.sp)
        Text(title, fontSize = 28.sp, lineHeight = 32.sp, fontWeight = FontWeight.Black)
        Text(body, color = Muted, fontSize = 14.sp, lineHeight = 21.sp)
        content()
    }
}

@Composable
private fun SectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().background(Panel, RoundedCornerShape(22.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        content()
    }
}

@Composable
private fun StatusLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = Muted, fontSize = 13.sp)
        Text(value, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, textAlign = TextAlign.End)
    }
}

@Composable
private fun ActionButton(label: String, enabled: Boolean, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = enabled, shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)) { Text(label, fontWeight = FontWeight.SemiBold) }
}

private fun output(value: Boolean?): String = when (value) { true -> "Actif · confirmé"; false -> "Arrêté · confirmé"; null -> "Inconnu" }
