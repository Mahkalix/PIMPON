package fr.pimpon.firecontrol.core

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.*
import java.util.concurrent.TimeUnit

sealed interface TransportEvent {
    data object Opened : TransportEvent
    data class Closed(val reason: String) : TransportEvent
    data class Message(val value: WireMessage) : TransportEvent
}

interface BoardTransport {
    val events: kotlinx.coroutines.flow.SharedFlow<TransportEvent>
    fun connect()
    fun disconnect()
    fun send(command: Command)
}

class SimulationTransport(private val role: BoardRole) : BoardTransport {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutableEvents = MutableSharedFlow<TransportEvent>(extraBufferCapacity = 32)
    override val events = mutableEvents.asSharedFlow()
    private var state = BoardState.safe(role)
    private var revision = 0
    private var connected = false
    private var epoch = 0

    override fun connect() { connected = true; epoch++; mutableEvents.tryEmit(TransportEvent.Opened) }
    override fun disconnect() {
        connected = false; epoch++; stop(); mutableEvents.tryEmit(TransportEvent.Closed("Connexion simulée coupée ; sécurité locale appliquée."))
    }
    fun setPresence(present: Boolean) {
        if (role != BoardRole.truck || !connected) return
        state = state.copy(onScene = present, pumpEnabled = if (present) state.pumpEnabled else false)
        emit("event", event = "presenceChanged")
    }
    override fun send(command: Command) {
        if (!connected) return
        val requestEpoch = epoch
        scope.launch {
            delay(180)
            if (connected && epoch == requestEpoch) apply(command)
        }
    }
    private fun stop() {
        state = if (role == BoardRole.truck) state.copy(pumpEnabled=false, beaconEnabled=false, sirenEnabled=false, servoStopped=true, drivingDirection=null, emergencyLocked=true)
        else state.copy(fireEnabled=false, fanEnabled=false, alarmEnabled=false, emergencyLocked=true)
    }
    private fun apply(c: Command) {
        val action = Action.entries.firstOrNull { it.name == c.action }
        var error: String? = null
        val allowed = if (role == BoardRole.truck) setOf(Action.getState, Action.drive, Action.stopDrive, Action.setPump, Action.setBeacon, Action.setSiren, Action.setNozzleAngle, Action.emergencyStop, Action.rearm) else setOf(Action.getState, Action.startFire, Action.stopFire, Action.setFan, Action.setAlarm, Action.emergencyStop, Action.rearm)
        if (action == null || action !in allowed) error = "Commande incompatible avec le rôle."
        else if (state.emergencyLocked && action !in setOf(Action.getState, Action.emergencyStop, Action.rearm)) error = "Carte verrouillée : réarmement requis."
        else when (action) {
            Action.getState -> Unit
            Action.emergencyStop -> stop()
            Action.rearm -> if (state.allStopped(role)) state = state.copy(emergencyLocked=false) else error = "Arrêtez d’abord les sorties."
            Action.drive -> if (c.payload.direction !in setOf("forward","reverse","left","right")) error="Direction invalide." else if (state.onScene==true && c.payload.direction in setOf("forward","reverse")) error="Le camion est arrivé ; déplacement bloqué." else state=state.copy(drivingDirection=c.payload.direction)
            Action.stopDrive -> state=state.copy(drivingDirection=null)
            Action.setPump -> if (c.payload.enabled == true && state.onScene != true) error = "Pompe interdite hors zone." else state = state.copy(pumpEnabled=c.payload.enabled)
            Action.setBeacon -> state = state.copy(beaconEnabled=c.payload.enabled)
            Action.setSiren -> state = state.copy(sirenEnabled=c.payload.enabled)
            Action.setNozzleAngle -> { val a=c.payload.angle; if (a == null || !a.isFinite() || a !in 0.0..180.0) error="Angle invalide." else state=state.copy(nozzleAngle=a, servoStopped=false) }
            Action.startFire -> state = state.copy(fireEnabled=true, fanEnabled=true, alarmEnabled=true)
            Action.stopFire -> state = state.copy(fireEnabled=false, fanEnabled=false)
            Action.setFan -> state = state.copy(fanEnabled=c.payload.enabled)
            Action.setAlarm -> state = state.copy(alarmEnabled=c.payload.enabled)
        }
        emit("ack", id=c.id, success=error == null, error=error)
    }
    private fun emit(type: String, id: String? = null, success: Boolean? = null, error: String? = null, event: String? = null) {
        revision++; mutableEvents.tryEmit(TransportEvent.Message(WireMessage(type, role.name, id, success, error, event, revision, state)))
    }
}

class WebSocketTransport(private val address: String) : BoardTransport {
    private val mutableEvents = MutableSharedFlow<TransportEvent>(extraBufferCapacity = 64)
    override val events = mutableEvents.asSharedFlow()
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val client = OkHttpClient.Builder().pingInterval(1, TimeUnit.SECONDS).build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var heartbeat: Job? = null
    private var socket: WebSocket? = null
    override fun connect() {
        val request = Request.Builder().url(address).build()
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                mutableEvents.tryEmit(TransportEvent.Opened)
                heartbeat?.cancel()
                heartbeat = scope.launch { while (isActive) { webSocket.send("{\"type\":\"heartbeat\"}"); delay(1_000) } }
            }
            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching { json.decodeFromString<WireMessage>(text) }
                    .onSuccess { mutableEvents.tryEmit(TransportEvent.Message(it)) }
                    .onFailure { mutableEvents.tryEmit(TransportEvent.Closed("Message JSON invalide : ${it.message}")) }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { mutableEvents.tryEmit(TransportEvent.Closed(t.message ?: "Erreur WebSocket")) }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { mutableEvents.tryEmit(TransportEvent.Closed(reason.ifBlank { "Connexion fermée." })) }
        })
    }
    override fun disconnect() { heartbeat?.cancel(); heartbeat=null; socket?.close(1000, "Fermeture demandée"); socket = null }
    override fun send(command: Command) { runCatching { json.encodeToString(Command.serializer(), command) }.onSuccess { socket?.send(it) } }
}
