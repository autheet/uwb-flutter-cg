package net.christiangreiner.uwb.oob

import DeviceState
import androidx.annotation.NonNull

class Endpoint(
    @NonNull val id: String,
    @NonNull val name: String,
    var state: DeviceState,
) {
    override fun equals(other: Any?): Boolean {
        return other is Endpoint && id == other.id && state == other.state
    }

    override fun hashCode(): Int {
        return id.hashCode()
    }

    override fun toString(): String {
        return "Endpoint(id=$id, name=$name, status=${state.name})"
    }
}