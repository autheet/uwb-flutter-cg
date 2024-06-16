package net.christiangreiner.uwb.oob

import java.nio.ByteBuffer

data class UwbConfig(val uwbRole: Byte, val preambleIndex: Int, val sessionKey: Int, val uwbAddress: ByteArray) {

    companion object {
        fun fromByteArray(byteArray: ByteArray): UwbConfig {
            val uwbRole = byteArray[0]
            val preambleIndex = ByteBuffer.wrap(byteArray, 1, 4).int
            val sessionKey = ByteBuffer.wrap(byteArray, 5, 4).int
            val uwbAddress = byteArray.copyOfRange(9, byteArray.size)
            return UwbConfig(uwbRole, preambleIndex, sessionKey, uwbAddress)
        }
    }

    fun toByteArray(): ByteArray {
        val clientTypeByte = byteArrayOf(uwbRole)
        val preambleIndexBytes = ByteBuffer.allocate(4).putInt(preambleIndex).array()
        val sessionKeyBytes = ByteBuffer.allocate(4).putInt(sessionKey).array()
        return clientTypeByte + preambleIndexBytes + sessionKeyBytes + uwbAddress
    }
}
