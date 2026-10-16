package fr.pimpon.firecontrol.core

import kotlinx.serialization.Serializable

enum class BoardRole { truck, house }
enum class RunMode(val label: String) { SIMULATION("Simulation"), HARDWARE("Matériel") }
enum class Phase(val label: String) {
    PREPARATION("Préparation"), STARTING("Déclenchement du feu"), INCOMING_CALL("Centre d’alerte"),
    BRIEFING("Message d’intervention"), DEPARTURE("Départ"), TRAVELLING("Camion en route"),
    INTERVENTION("Intervention"), EXTINGUISHING("Arrêts en cours"), EXTINGUISHED("Feu simulé éteint"),
    FINISHING("Fin en cours"), FINISHED("Intervention terminée")
}
enum class Connection(val label: String) { DISCONNECTED("Déconnecté"), CONNECTING("Connexion en cours"), READY("Connecté, état reçu") }
enum class Action { getState, drive, stopDrive, setPump, setBeacon, setSiren, setNozzleAngle, startFire, stopFire, setFan, setAlarm, emergencyStop, rearm }

@Serializable
data class Payload(val enabled: Boolean? = null, val angle: Double? = null, val direction: String? = null)

@Serializable
data class Command(val type: String = "command", val id: String, val action: String, val payload: Payload = Payload()) {
    companion object { fun create(action: Action, enabled: Boolean? = null, angle: Double? = null, direction: String? = null) = Command(id = java.util.UUID.randomUUID().toString(), action = action.name, payload = Payload(enabled, angle, direction)) }
}

@Serializable
data class BoardState(
    val emergencyLocked: Boolean = false,
    val pumpEnabled: Boolean? = null, val beaconEnabled: Boolean? = null, val sirenEnabled: Boolean? = null,
    val nozzleAngle: Double? = null, val servoStopped: Boolean? = null, val onScene: Boolean? = null, val drivingDirection: String? = null,
    val temperatureCelsius: Double? = null,
    val fireEnabled: Boolean? = null, val fanEnabled: Boolean? = null, val alarmEnabled: Boolean? = null
) {
    fun complete(role: BoardRole) = if (role == BoardRole.truck) pumpEnabled != null && beaconEnabled != null && sirenEnabled != null && nozzleAngle?.isFinite() == true && servoStopped != null && onScene != null else fireEnabled != null && fanEnabled != null && alarmEnabled != null
    fun allStopped(role: BoardRole) = if (role == BoardRole.truck) pumpEnabled == false && beaconEnabled == false && sirenEnabled == false && servoStopped == true && drivingDirection == null else fireEnabled == false && fanEnabled == false && alarmEnabled == false
    companion object {
        fun safe(role: BoardRole) = if (role == BoardRole.truck) BoardState(pumpEnabled=false, beaconEnabled=false, sirenEnabled=false, nozzleAngle=90.0, servoStopped=true, onScene=false, drivingDirection=null) else BoardState(fireEnabled=false, fanEnabled=false, alarmEnabled=false)
    }
}

@Serializable
data class WireMessage(val type: String, val role: String, val id: String? = null, val success: Boolean? = null,
                       val error: String? = null, val event: String? = null, val revision: Int, val state: BoardState)

data class CommandRecord(val id: String, val role: BoardRole, val action: Action, val payload: Payload, val status: Status, val detail: String) {
    enum class Status { PENDING, CONFIRMED, FAILED }
}
