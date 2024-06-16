package net.christiangreiner.uwb.oob

import DeviceState
import android.content.Context
import android.util.Log
import com.google.android.gms.common.api.Status
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import com.google.android.gms.tasks.Task


/* Nearby Connection Wrapper
 *
 */
class NearbyManager(appContext: Context, private val serviceId: String) {

    // P2P_CLUSTER uses BLE
    // P2P_POINT_TO_POINT uses Wifi
    private val strategy : Strategy = Strategy.P2P_CLUSTER
    private val LOG_TAG: String = "UWB Discovery"

    // Discovery Callbacks
    var onEndpointFound: ((Endpoint) -> Unit)? = null
    var onEndpointLost: ((Endpoint) -> Unit)? = null

    // Connection Callbacks
    var onEndpointConnectionInitiated: ((Endpoint, Boolean) -> Unit)? = null
    var onEndpointConnected: ((Endpoint) -> Unit)? = null
    var onEndpointConnectionRejected: ((Endpoint) -> Unit)? = null
    var onEndpointConnectionDisconnected: ((Endpoint) -> Unit)? = null
    var onPayloadReceived: ((Endpoint, ByteArray) -> Unit)? = null
    var onConnectionError: ((String, Status) -> Unit)? = null

    private var isDiscovering = false
    private var isAdvertising = false
    private var connectionsClient: ConnectionsClient

    // Used to identify the device by a friendly name
    private lateinit var deviceName: String

    // Endpoint Id to Endpoint Mapping
    private val endpoints: HashMap<String, Endpoint> = HashMap()

    init {
        connectionsClient = Nearby.getConnectionsClient(appContext)
    }

    fun isDiscovering() : Boolean {
        return isDiscovering;
    }

    fun getConnectedEndpoints() : HashMap<String, Endpoint> {
        return endpoints
    }

    private fun connectedToEndpoint(endpointId: String) {
        if (endpoints.containsKey(endpointId)) {
            endpoints[endpointId]?.state = DeviceState.CONNECTED
            onEndpointConnected?.invoke(endpoints[endpointId]!!)
        }
    }

    // Creates a new pending Endpoint
    private fun connectionInitiated(endpointId: String, connectionInfo: ConnectionInfo) {
        if (endpoints.containsKey(endpointId)) {
            endpoints[endpointId]?.state = DeviceState.PENDING
            onEndpointConnectionInitiated?.invoke(endpoints[endpointId]!!, connectionInfo.isIncomingConnection)
        }
    }

    private fun endpointDisconnected(endpointId: String) {
        if (endpoints.containsKey(endpointId)) {
            var disconnectedEndpoint = endpoints.remove(endpointId)!!
            disconnectedEndpoint?.state = DeviceState.DISCONNECTED
            onEndpointConnectionDisconnected?.invoke(disconnectedEndpoint)
        }
    }

    // A new endpoint was found
    private fun endpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
        val foundEndpoint = Endpoint(endpointId, info.endpointName, DeviceState.FOUND)
        endpoints[endpointId] = foundEndpoint
        onEndpointFound?.invoke(foundEndpoint)
    }

    private fun endpointLost(endpointId: String) {
        if (endpoints.containsKey(endpointId)) {
            var lostEndpoint = endpoints.remove(endpointId)!!
            lostEndpoint?.state = DeviceState.LOST
            onEndpointLost?.invoke(lostEndpoint)
        }
    }

    /**
     * Restarts discovery only if its already discovering.
     */
    fun restartDiscovery() {
        if (isDiscovering) {
            this.stopDiscovery()
            this.stopAdvertising()
            this.startDiscovery()
            this.startAdvertising(this.deviceName)
        }
    }

     fun startDiscovery(): Task<Void> {
        val discoveryOptions =
            DiscoveryOptions.Builder().setStrategy(strategy).build()

        return connectionsClient.startDiscovery(
            serviceId,
            endpointDiscoveryCallback,
            discoveryOptions
        )
        .addOnSuccessListener { isDiscovering = true }
        .addOnFailureListener { e ->
            Log.d(
                LOG_TAG,
                "Discovery failed: $e"
            )
            isDiscovering = false
        }
    }

    fun disconnectFromAll() {
        this.connectionsClient.stopAllEndpoints()
    }

     fun startAdvertising(deviceName: String) : Task<Void> {

        // TODO: Validate deivceName
        
        val advertisingOptions =
            AdvertisingOptions.Builder().setStrategy(strategy).build()

        this.deviceName = deviceName

        return connectionsClient.startAdvertising(
            deviceName,
            serviceId,
            connectionLifecycleCallback,
            advertisingOptions
        ).addOnSuccessListener { isAdvertising = true }
        .addOnFailureListener { e ->
            Log.d(
                LOG_TAG,
                "Advertising failed:  $e"
            )
            isAdvertising = false
        }
    }

    fun sendData(endpoint: Endpoint, payload: Payload) : Task<Void> {
        return connectionsClient
        .sendPayload(endpoint.id, payload)
        .addOnFailureListener { e ->
            Log.d(
                LOG_TAG,
                "Send Payload to ${endpoint.id} failed: $e"
            )
        }
    }

    fun stopDiscovery() {
        connectionsClient.stopDiscovery()
        isDiscovering = false
    }

    fun stopAdvertising() {
        connectionsClient.stopAdvertising()
        isAdvertising = false
    }

    fun connect(endpointId: String) : Task<Void> {
        // Disconnect to trigger connection life cycle again
        connectionsClient.disconnectFromEndpoint(endpointId)

        return connectionsClient.requestConnection(
            this.deviceName,
            endpointId,
            connectionLifecycleCallback,
        )
        .addOnFailureListener { e ->
            Log.d(
                LOG_TAG,
                "Connect with Endpoint $endpointId failed:  $e"
            )
        }
    }

    fun acceptConnection(endpointId: String) : Task<Void> {
        return connectionsClient.acceptConnection(endpointId, payloadCallback)
            .addOnFailureListener { e ->
            Log.d(
                LOG_TAG,
                "Accept with Endpoint $endpointId failed:  $e"
            )
        }
    }

    fun disconnect(endpointId: String) {
        connectionsClient.disconnectFromEndpoint(endpointId)
        endpointDisconnected(endpointId)
    }

    fun rejectConnection(endpointId: String) : Task<Void> {
        return connectionsClient.rejectConnection(endpointId)
        .addOnFailureListener { e ->
            Log.d(
                LOG_TAG,
                "Endpoint rejected failed:  $e"
            )
        }
    }

    /** Callbacks for payloads (bytes of data) sent from another device to us.  */
    private val payloadCallback: PayloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            Log.d(
                LOG_TAG,
                "(onPayloadReceived) Payload received from $endpointId. "
            )
            val endpoint = endpoints[endpointId] ?: return
            val bytes = payload.asBytes() ?: return
            if (bytes != null && endpoint != null) {
                onPayloadReceived?.invoke(endpoint, bytes)
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {}
    }

    /** Callbacks for connections to other devices. */
    private val endpointDiscoveryCallback: EndpointDiscoveryCallback =
        object : EndpointDiscoveryCallback() {
            override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
                if (serviceId == info.serviceId) {
                    Log.d(
                        LOG_TAG,
                        "Endpoint(id=$endpointId, name=${info.endpointName}) found."
                    )
                    endpointFound(endpointId, info)
                }
            }

            override fun onEndpointLost(endpointId: String) {
                Log.d(
                    LOG_TAG,
                    "Endpoint(id=$endpointId) lost."
                )
                endpointLost(endpointId)
            }
        }

    /** Callbacks for connections to other devices. */
    private val connectionLifecycleCallback: ConnectionLifecycleCallback =
        object : ConnectionLifecycleCallback() {

            override fun onConnectionInitiated(endpointId: String, connectionInfo: ConnectionInfo) {
                Log.d(
                    LOG_TAG,
                    "Connection initiated by Endpoint(id=$endpointId)"
                )
                connectionInitiated(endpointId, connectionInfo)
            }

            override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
               Log.d(LOG_TAG, "onConnectionResult Status: ${result.status}")
                when (result.status.statusCode) {
                    ConnectionsStatusCodes.STATUS_OK -> {
                        Log.d(
                            LOG_TAG,
                            "Connection with Endpoint(id=$endpointId) successfully."
                        )
                        connectedToEndpoint(endpointId)
                    }
                    ConnectionsStatusCodes.STATUS_CONNECTION_REJECTED -> {
                        Log.i(
                            LOG_TAG,
                            "Connection with Endpoint(endpointId=$endpointId) rejected."
                        )
                        val endpoint = endpoints[endpointId]
                        if (endpoint != null) onEndpointConnectionRejected?.invoke(endpoint)
                    }
                    else -> {
                        onConnectionError?.invoke(endpointId, result.status)
                    }
                }
            }

            // Endpoint disconnects from the device
            override fun onDisconnected(endpointId: String) {
                Log.d(
                    LOG_TAG,
                    "Endpoint(endpointId=$endpointId) disconnected."
                )
                endpointDisconnected(endpointId)
            }
        }
}