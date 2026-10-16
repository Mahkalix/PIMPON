package fr.pimpon.app

import org.java_websocket.WebSocket
import org.java_websocket.handshake.ClientHandshake
import org.java_websocket.server.WebSocketServer
import org.java_websocket.client.WebSocketClient
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.URI

/** Small same-Wi-Fi relay for the classroom demonstration; the host app must remain open. */
class AlertRelay {
    private var server: WebSocketServer? = null
    private var client: WebSocketClient? = null

    fun startHost(onStatus: (String) -> Unit, onRemoteStatus: (String) -> Unit) {
        stop()
        val relay = object : WebSocketServer(InetSocketAddress("0.0.0.0", PORT)) {
            override fun onOpen(conn: WebSocket, handshake: ClientHandshake) { onStatus("Téléphone pompier connecté") }
            override fun onClose(conn: WebSocket, code: Int, reason: String, remote: Boolean) { onStatus("Téléphone pompier déconnecté") }
            override fun onMessage(conn: WebSocket, message: String) {
                if (message == ACK) onStatus("Alerte reçue par le téléphone pompier")
                else if (message.startsWith(STATUS_PREFIX)) onRemoteStatus(message.removePrefix(STATUS_PREFIX))
            }
            override fun onError(conn: WebSocket?, ex: Exception) { onStatus("Erreur de liaison : ${ex.message ?: "inconnue"}") }
            override fun onStart() { onStatus("Relais actif sur le Wi-Fi") }
        }
        server = relay
        relay.start()
    }

    fun sendEmergencyCall(): Boolean {
        val host = server
        if (host != null) {
            if (host.connections.isEmpty()) return false
            host.broadcast(CALL)
            return true
        }
        val peer = client
        if (peer?.isOpen == true) { peer.send(CALL); return true }
        return false
    }

    fun isHosting(): Boolean = server != null
    fun sendStatus(value: String) { if (client?.isOpen == true) client?.send(STATUS_PREFIX + value) }

    fun connectToAdmin(address: String, onStatus: (String) -> Unit, onAlert: () -> Unit) {
        stop()
        val raw = address.trim().removePrefix("ws://").removePrefix("wss://").trimEnd('/')
        val uri = runCatching { URI(if (raw.substringAfterLast(':').toIntOrNull() != null) "ws://$raw" else "ws://$raw:$PORT") }.getOrElse {
            onStatus("Adresse du centre invalide")
            return
        }
        if (uri.host.isNullOrBlank()) { onStatus("Adresse du centre invalide"); return }
        val peer = object : WebSocketClient(uri) {
            override fun onOpen(handshakedata: org.java_websocket.handshake.ServerHandshake) { onStatus("Connecté au centre de secours") }
            override fun onMessage(message: String) {
                if (message == CALL) { send(ACK); onAlert() }
            }
            override fun onClose(code: Int, reason: String, remote: Boolean) { onStatus("Connexion au centre de secours fermée") }
            override fun onError(ex: Exception) { onStatus("Connexion impossible : ${ex.message ?: "vérifiez le Wi-Fi et l’adresse"}") }
        }
        client=peer
        peer.connect()
    }

    fun stop() {
        runCatching { client?.close() }; client=null
        runCatching { server?.stop(500) }; server=null
    }

    companion object {
        const val PORT = 8765
        const val CALL = "PIMPON_EMERGENCY_CALL"
        const val ACK = "PIMPON_CALL_RECEIVED"
        const val STATUS_PREFIX = "PIMPON_STATUS|"
        fun localIpv4(): String? = runCatching {
            NetworkInterface.getNetworkInterfaces().toList().asSequence()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList().asSequence() }
                .filterIsInstance<Inet4Address>()
                .firstOrNull { !it.isLoopbackAddress && !it.isLinkLocalAddress }
                ?.hostAddress
        }.getOrNull()
    }
}
