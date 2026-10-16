package fr.pimpon.firecontrol.core

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

data class AppState(
    val mode: RunMode = RunMode.SIMULATION, val phase: Phase = Phase.PREPARATION,
    val connections: Map<BoardRole, Connection> = BoardRole.entries.associateWith { Connection.DISCONNECTED },
    val boards: Map<BoardRole, BoardState> = emptyMap(), val errors: Map<BoardRole, String> = emptyMap(),
    val records: List<CommandRecord> = emptyList(), val message: String = "Remplissez physiquement le réservoir avant la démonstration.",
    val emergencyLocked: Boolean = false, val paused: Boolean = false, val pumpUsed: Boolean = false,
    val truckAddress: String = "ws://192.168.1.50:81", val houseAddress: String = "ws://192.168.1.51:81",
    val nozzleMinimum: Float = 60f, val nozzleMaximum: Float = 120f, val hardwareRangeValidated: Boolean = false
) {
    val ready get() = BoardRole.entries.all { connections[it] == Connection.READY }
    val onScene get() = boards[BoardRole.truck]?.onScene == true
    val controls get() = ready && !paused && !emergencyLocked
    val validRange get() = nozzleMinimum >= 0 && nozzleMaximum <= 180 && nozzleMinimum < nozzleMaximum
    val canPump get() = controls && phase == Phase.INTERVENTION && onScene && records.none { it.role == BoardRole.truck && it.action == Action.setPump && it.status == CommandRecord.Status.PENDING }
    val canAim get() = canPump && validRange && (mode == RunMode.SIMULATION || hardwareRangeValidated) && records.none { it.role == BoardRole.truck && it.action == Action.setNozzleAngle && it.status == CommandRecord.Status.PENDING }
    val canConfirmExtinction get() = controls && phase == Phase.INTERVENTION && pumpUsed
}

class InterventionCoordinator(
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
) {
    private val mutable = MutableStateFlow(AppState())
    val state: StateFlow<AppState> = mutable.asStateFlow()
    private val transports = mutableMapOf<BoardRole, BoardTransport>()
    private val collectors = mutableMapOf<BoardRole, Job>()
    private val pending = mutableMapOf<String, Pair<BoardRole, Command>>()
    private val revisions = mutableMapOf<BoardRole, Int>()
    private val lastSeen = mutableMapOf<BoardRole, Long>()
    private var rearming = false
    private var awaitingResume = false
    private var pumpActivated = false
    private var watchdog: Job? = null

    fun updateAddress(role: BoardRole, value: String) { mutable.update { if (role == BoardRole.truck) it.copy(truckAddress=value) else it.copy(houseAddress=value) } }
    fun configure(mode: RunMode) {
        if (state.value.phase != Phase.PREPARATION || state.value.emergencyLocked) return
        collectors.values.forEach { it.cancel() }; collectors.clear()
        transports.values.forEach { it.disconnect() }; transports.clear(); pending.clear(); revisions.clear()
        mutable.update { it.copy(mode=mode, boards=emptyMap(), errors=emptyMap(), paused=false, connections=BoardRole.entries.associateWith { Connection.DISCONNECTED }) }
    }
    fun connect() {
        BoardRole.entries.forEach { role ->
            if (state.value.connections[role] == Connection.READY || state.value.connections[role] == Connection.CONNECTING) return@forEach
            val transport = if (state.value.mode == RunMode.SIMULATION) (transports[role] as? SimulationTransport) ?: SimulationTransport(role)
            else {
                val address=if (role == BoardRole.truck) state.value.truckAddress else state.value.houseAddress
                val uri=runCatching { java.net.URI(address) }.getOrNull()
                if(uri==null || uri.scheme !in setOf("ws","wss") || uri.host.isNullOrBlank()) {
                    mutable.update { it.copy(errors=it.errors+(role to "Adresse WebSocket invalide (ws:// ou wss://).")) }
                    return@forEach
                }
                WebSocketTransport(address)
            }
            install(role, transport)
        }
        watchdog?.cancel()
        watchdog=scope.launch {
            while (isActive) {
                delay(1_000)
                if (state.value.mode == RunMode.HARDWARE) BoardRole.entries.filter { state.value.connections[it] == Connection.READY }.forEach { role ->
                    if (System.currentTimeMillis() - (lastSeen[role] ?: 0L) > 5_000) handle(role, TransportEvent.Closed("Heartbeat absent depuis 5 secondes."))
                }
            }
        }
    }
    private fun install(role: BoardRole, transport: BoardTransport) {
        collectors.remove(role)?.cancel()
        transports[role]?.disconnect(); transports[role]=transport; revisions.remove(role); lastSeen.remove(role)
        mutable.update { it.copy(connections=it.connections + (role to Connection.CONNECTING), boards=it.boards - role, errors=it.errors-role) }
        collectors[role]=scope.launch { transport.events.collect { handle(role, it) } }
        transport.connect()
    }
    private fun handle(role: BoardRole, event: TransportEvent) {
        when (event) {
            TransportEvent.Opened -> send(role, Action.getState)
            is TransportEvent.Closed -> {
                invalidate(role, event.reason)
                mutable.update { old -> old.copy(connections=old.connections+(role to Connection.DISCONNECTED), boards=old.boards-role, errors=old.errors+(role to event.reason), paused=old.phase !in setOf(Phase.PREPARATION, Phase.FINISHED), message=if(old.phase !in setOf(Phase.PREPARATION,Phase.FINISHED)) "Scénario en pause. Arrêts non confirmés sur la carte déconnectée." else old.message) }
                if (role == BoardRole.house && state.value.connections[BoardRole.truck] == Connection.READY) send(BoardRole.truck, Action.setPump, false)
            }
            is TransportEvent.Message -> receive(role,event.value)
        }
    }
    private fun receive(role: BoardRole, m: WireMessage) {
        val phase = state.value.phase
        if (state.value.connections[role] == Connection.DISCONNECTED) return
        if (m.role != role.name || !m.state.complete(role) || m.revision < 0 || m.type !in setOf("ack","event","state")) {
            handle(role, TransportEvent.Closed("Message invalide ou rôle de carte incorrect.")); return
        }
        lastSeen[role]=System.currentTimeMillis()
        var ack: Command? = null
        if (m.type == "ack") {
            val pair = m.id?.let { pending[it] } ?: return
            if (pair.first != role) return
            val (target, command) = pair
            if (m.success != true) { fail(command.id,m.error ?: "Commande refusée."); mutable.update { it.copy(errors=it.errors+(role to (m.error ?: "Commande refusée."))) }; return }
            if (!matches(command,m.state,role)) { fail(command.id,"Réponse incohérente : sortie demandée non confirmée."); return }
            ack=command; pending.remove(command.id)
            mutable.update { old -> old.copy(errors=old.errors-role, records=old.records.map { if(it.id==command.id) it.copy(status=CommandRecord.Status.CONFIRMED, detail="Sortie appliquée par la carte, sans mesure physique indépendante.") else it }) }
        }
        val fresh=m.revision>(revisions[role] ?: -1)
        val wasHere=state.value.onScene
        if(fresh) { revisions[role]=m.revision; mutable.update { it.copy(boards=it.boards+(role to m.state)) } }
        if (ack?.action == Action.getState.name) mutable.update { it.copy(connections=it.connections+(role to Connection.READY), errors=it.errors-role) }
        if(fresh && m.state.emergencyLocked && phase !in setOf(Phase.FINISHING,Phase.FINISHED)) mutable.update { it.copy(emergencyLocked=true) }
        if(fresh && role==BoardRole.truck && wasHere && !state.value.onScene && phase==Phase.INTERVENTION && !state.value.emergencyLocked) {
            mutable.update { it.copy(message="Camion hors zone. Pompe bloquée ; une nouvelle activation sera nécessaire au retour.") }; send(role,Action.setPump,false)
        }
        if(fresh && role==BoardRole.truck && state.value.phase==Phase.INTERVENTION && m.state.pumpEnabled==true && state.value.onScene) { pumpActivated=true; mutable.update { it.copy(pumpUsed=true) } }
        if(awaitingResume && ack?.action==Action.setPump.name && ack.payload.enabled==false && state.value.boards[BoardRole.truck]?.pumpEnabled==false) {
            awaitingResume=false; mutable.update { it.copy(paused=false,message="Reprise explicite. Aucun équipement n’a été réactivé.") }
        }
        advance()
    }
    private fun matches(c: Command,s:BoardState,r:BoardRole):Boolean = when(c.action) {
        Action.getState.name -> true
        Action.drive.name -> s.drivingDirection==c.payload.direction
        Action.stopDrive.name -> s.drivingDirection==null
        Action.setPump.name -> s.pumpEnabled==c.payload.enabled
        Action.setBeacon.name -> s.beaconEnabled==c.payload.enabled
        Action.setSiren.name -> s.sirenEnabled==c.payload.enabled
        Action.setAlarm.name -> s.alarmEnabled==c.payload.enabled
        Action.setFan.name -> s.fanEnabled==c.payload.enabled
        Action.setNozzleAngle.name -> s.nozzleAngle==c.payload.angle
        Action.startFire.name -> s.fireEnabled==true && s.fanEnabled==true && s.alarmEnabled==true
        Action.stopFire.name -> s.fireEnabled==false && s.fanEnabled==false
        Action.emergencyStop.name -> s.emergencyLocked && s.allStopped(r)
        Action.rearm.name -> !s.emergencyLocked && s.allStopped(r)
        else -> false
    }
    private fun send(role:BoardRole,action:Action,enabled:Boolean?=null,angle:Double?=null,direction:String?=null) {
        val s=state.value
        if(s.connections[role]!=Connection.READY && !(action==Action.getState && s.connections[role]==Connection.CONNECTING)) { mutable.update { it.copy(errors=it.errors+(role to "Commande ${action.name} non envoyée : carte indisponible.")) }; return }
        if(action==Action.setPump && enabled==false) pending.filterValues { it.first==role && it.second.action==Action.setPump.name && it.second.payload.enabled==true }.keys.toList().forEach { fail(it,"Activation remplacée par une demande d’arrêt.") }
        if(pending.values.any { it.first==role && it.second.action==action.name }) return
        val c=Command.create(action,enabled,angle,direction); pending[c.id]=role to c
        mutable.update { old -> old.copy(records=(old.records+CommandRecord(c.id,role,action,c.payload,CommandRecord.Status.PENDING,"Demandée, sans confirmation de sortie.")).takeLast(100)) }
        transports[role]?.send(c)
        scope.launch { delay(4_000); if(pending.containsKey(c.id)) { fail(c.id,"Confirmation absente : sortie inconnue."); handle(role,TransportEvent.Closed("Délai de confirmation dépassé.")); transports[role]?.disconnect() } }
    }
    private fun fail(id:String,reason:String) { pending.remove(id); mutable.update { it.copy(records=it.records.map { r-> if(r.id==id) r.copy(status=CommandRecord.Status.FAILED,detail=reason) else r }) } }
    private fun invalidate(role:BoardRole,reason:String) { pending.filterValues { it.first==role }.keys.toList().forEach { fail(it,reason) } }
    private fun advance() {
        val s=state.value
        if(rearming && s.ready && pending.isEmpty() && BoardRole.entries.all { s.boards[it]?.let { b->!b.emergencyLocked&&b.allStopped(it) }==true }) { mutable.update { it.copy(emergencyLocked=false,paused=false,phase=Phase.PREPARATION,pumpUsed=false,message="Réarmé. Préparez à nouveau le réservoir et le camion.") }; rearming=false; pumpActivated=false; return }
        if(!s.controls) return
        val house=s.boards[BoardRole.house]
        if(s.phase==Phase.STARTING && house?.fireEnabled==true && house.fanEnabled==true && house.alarmEnabled==true && pending.values.none { it.second.action==Action.startFire.name }) mutable.update { it.copy(phase=Phase.INCOMING_CALL,message="Faux feu confirmé actif. Appel entrant fictif du centre d’alerte.") }
        if(state.value.phase==Phase.TRAVELLING && state.value.onScene) { mutable.update { it.copy(phase=Phase.INTERVENTION,message="Camion sur place. Le déplacement est bloqué.") }; send(BoardRole.truck,Action.stopDrive); send(BoardRole.truck,Action.setSiren,false); send(BoardRole.house,Action.setAlarm,false) }
        val now=state.value
        if(now.phase==Phase.EXTINGUISHING && extinctionConfirmed()) mutable.update { it.copy(phase=Phase.EXTINGUISHED,message="Pompe, LED et ventilateur confirmés à l’arrêt.") }
        if(now.phase==Phase.FINISHING && pending.isEmpty() && BoardRole.entries.all { now.boards[it]?.allStopped(it)==true }) mutable.update { it.copy(phase=Phase.FINISHED,message="Tous les équipements connectés sont confirmés à l’arrêt.") }
    }
    private fun extinctionConfirmed()=state.value.ready && state.value.boards[BoardRole.truck]?.pumpEnabled==false && state.value.boards[BoardRole.house]?.let { it.fireEnabled==false&&it.fanEnabled==false }==true

    fun startFire() { val s=state.value; if(!s.controls||s.phase!=Phase.PREPARATION||BoardRole.entries.any { s.boards[it]?.allStopped(it)!=true }) return; pumpActivated=false; mutable.update { it.copy(phase=Phase.STARTING,message="Activation du faux feu demandée à la maison.") }; send(BoardRole.house,Action.startFire) }
    fun receiveRemoteCall() {
        val s=state.value
        if(s.phase!=Phase.PREPARATION||s.emergencyLocked)return
        if(s.controls&&BoardRole.entries.all { s.boards[it]?.allStopped(it)==true }) startFire()
        else mutable.update { it.copy(phase=Phase.INCOMING_CALL,message="Appel entrant du centre de secours. Vérifiez les connexions avant d’accepter l’intervention.") }
    }
    fun answerCall() { if(state.value.phase==Phase.INCOMING_CALL) mutable.update { it.copy(phase=Phase.BRIEFING) } }
    fun acceptIntervention() { if(state.value.phase !in setOf(Phase.INCOMING_CALL,Phase.BRIEFING)||!state.value.controls)return; mutable.update { it.copy(phase=Phase.DEPARTURE,message="Attendez les confirmations du gyrophare et de la sirène, puis confirmez le départ.") }; if(state.value.boards[BoardRole.house]?.fireEnabled!=true)send(BoardRole.house,Action.startFire); send(BoardRole.truck,Action.setBeacon,true); send(BoardRole.truck,Action.setSiren,true) }
    fun confirmDeparture() { val s=state.value; if(s.phase==Phase.DEPARTURE&&s.controls&&s.boards[BoardRole.truck]?.let { it.beaconEnabled==true&&it.sirenEnabled==true }==true) { mutable.update { it.copy(phase=Phase.TRAVELLING,message="Conduisez avec la télécommande. L’application attend la présence dans la zone.") }; advance() } }
    fun drive(direction:String) { val s=state.value; if(s.controls&&s.phase==Phase.TRAVELLING&&!s.onScene&&direction in setOf("forward","reverse","left","right"))send(BoardRole.truck,Action.drive,direction=direction) }
    fun stopDriving() { if(state.value.phase==Phase.TRAVELLING&&state.value.connections[BoardRole.truck]==Connection.READY)send(BoardRole.truck,Action.stopDrive) }
    fun setBeacon(value:Boolean) { if(state.value.controls&&state.value.phase in setOf(Phase.DEPARTURE,Phase.TRAVELLING)) send(BoardRole.truck,Action.setBeacon,value) }
    fun setSiren(value:Boolean) { if(state.value.controls&&state.value.phase in setOf(Phase.DEPARTURE,Phase.TRAVELLING)) send(BoardRole.truck,Action.setSiren,value) }
    fun setPump(value:Boolean) { val s=state.value; if(value && s.controls&&s.phase==Phase.INTERVENTION&&s.onScene) send(BoardRole.truck,Action.setPump,true) else if(!value&&s.connections[BoardRole.truck]==Connection.READY&&!s.emergencyLocked)send(BoardRole.truck,Action.setPump,false) }
    fun aim(angle:Double) { val s=state.value; if(s.controls&&s.phase==Phase.INTERVENTION&&s.onScene&&s.validRange&&(s.mode==RunMode.SIMULATION||s.hardwareRangeValidated)&&angle in s.nozzleMinimum.toDouble()..s.nozzleMaximum.toDouble())send(BoardRole.truck,Action.setNozzleAngle,angle=angle) }
    fun confirmExtinction() { val s=state.value; if(!s.controls||s.phase!=Phase.INTERVENTION||!s.pumpUsed)return; mutable.update { it.copy(phase=Phase.EXTINGUISHING,message="Extinction demandée : attente des sorties arrêtées sur les deux cartes.") }; retryStops() }
    fun retryStops() { val s=state.value; if(s.emergencyLocked){emergencyStop();return}; if(s.phase !in setOf(Phase.INTERVENTION,Phase.EXTINGUISHING,Phase.EXTINGUISHED,Phase.FINISHING))return; send(BoardRole.truck,Action.setPump,false); send(BoardRole.truck,Action.setSiren,false); send(BoardRole.house,Action.setAlarm,false); if(s.phase!=Phase.INTERVENTION)send(BoardRole.house,Action.stopFire); if(s.phase==Phase.FINISHING)send(BoardRole.truck,Action.setBeacon,false) }
    fun finish() { if(state.value.phase!=Phase.EXTINGUISHED||!state.value.controls||!extinctionConfirmed())return; mutable.update { it.copy(phase=Phase.FINISHING) }; send(BoardRole.truck,Action.emergencyStop); send(BoardRole.house,Action.emergencyStop) }
    fun emergencyStop() { mutable.update { it.copy(emergencyLocked=true,message="Arrêt d’urgence verrouillé. Arrêtez la voiture avec sa télécommande : ses moteurs sont indépendants.") }; BoardRole.entries.forEach { invalidate(it,"Annulée par l’arrêt d’urgence ; état à vérifier."); send(it,Action.emergencyStop) } }
    fun rearm() { val s=state.value; if(!s.ready||pending.isNotEmpty()||BoardRole.entries.any { s.boards[it]?.allStopped(it)!=true })return; mutable.update { it.copy(emergencyLocked=true) }; rearming=true; send(BoardRole.truck,Action.rearm); send(BoardRole.house,Action.rearm) }
    fun newIntervention() { if(state.value.phase==Phase.FINISHED)rearm() }
    fun resume() { val s=state.value; if(!s.paused||!s.ready||s.emergencyLocked||BoardRole.entries.any { s.boards[it]?.emergencyLocked!=false })return; awaitingResume=true; send(BoardRole.truck,Action.setPump,false) }
    fun retryStart() { if(state.value.phase==Phase.STARTING&&state.value.controls)send(BoardRole.house,Action.startFire) }
    fun simulatePresence(present:Boolean) { if(state.value.mode==RunMode.SIMULATION&&state.value.phase in setOf(Phase.TRAVELLING,Phase.INTERVENTION))(transports[BoardRole.truck] as? SimulationTransport)?.setPresence(present) }
    fun simulateDisconnect(role:BoardRole) { if(state.value.mode==RunMode.SIMULATION)transports[role]?.disconnect() }
    fun setMode(mode:RunMode) { configure(mode); connect() }
    fun applyHardwareAddresses() {
        if(state.value.phase!=Phase.PREPARATION || state.value.mode!=RunMode.HARDWARE) return
        collectors.values.forEach { it.cancel() }; collectors.clear()
        transports.values.forEach { it.disconnect() }; transports.clear()
        mutable.update { it.copy(connections=BoardRole.entries.associateWith { Connection.DISCONNECTED }, boards=emptyMap(), errors=emptyMap()) }
        connect()
    }
    fun setNozzleRange(min:Float,max:Float) { mutable.update { it.copy(nozzleMinimum=min.coerceIn(0f,180f),nozzleMaximum=max.coerceIn(0f,180f)) } }
    fun validateHardwareRange(value:Boolean) { mutable.update { it.copy(hardwareRangeValidated=value) } }
}
