package net.christiangreiner.uwb.oob

// A simple data class to hold UWB configuration parameters within the native Android code.
data class UwbConfig(val preambleIndex: Int, val sessionKey: Int, val uwbAddress: ByteArray)
