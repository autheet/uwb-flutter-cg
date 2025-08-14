import Foundation
import NearbyInteraction
import Flutter

class NISessionManager: NSObject, NISessionDelegate {
    private var session: NISession?
    private let flutterApi: UwbFlutterApi

    init(flutterApi: UwbFlutterApi) {
        self.flutterApi = flutterApi
        super.init()
    }

    // --- Peer Ranging Methods ---

    func getPeerDiscoveryToken() throws -> Data {
        session?.invalidate()
        session = NISession()
        session?.delegate = self

        guard let token = session?.discoveryToken else {
            throw FlutterError(code: "UWB_ERROR", message: "Failed to get discovery token.", details: nil)
        }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func startPeerRanging(tokenData: Data) throws {
        guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
            throw FlutterError(code: "UWB_ERROR", message: "Invalid peer discovery token.", details: nil)
        }
        let config = NINearbyPeerConfiguration(peerToken: token)
        session?.run(config)
    }

    // --- Accessory Ranging Methods ---

    func startControllerRanging(accessoryData: Data) throws -> Data {
        session?.invalidate()
        session = NISession()
        session?.delegate = self

        guard let config = try? NINearbyAccessoryConfiguration(data: accessoryData) else {
            throw FlutterError(code: "UWB_ERROR", message: "Failed to create accessory configuration from data.", details: nil)
        }
        
        session?.run(config)

        guard let shareableData = session?.shareableConfigurationData else {
             throw FlutterError(code: "UWB_ERROR", message: "Failed to get shareable configuration data.", details: nil)
        }

        return shareableData
    }
    
    func startAccessoryRanging(shareableData: Data) throws {
       // On iOS, the session is already running on the controller side after startControllerRanging.
       // This method is primarily for the accessory (Android) to start its session.
       // For iOS-iOS accessory mode (not our primary use case), the logic would go here.
       throw FlutterError(code: "UWB_ERROR", message: "iOS does not act as an accessory in this architecture.", details: nil)
    }
    
    func getAccessoryConfigurationData() throws -> Data {
        throw FlutterError(code: "UWB_ERROR", message: "iOS does not act as an accessory in this architecture.", details: nil)
    }

    func stopRanging() {
        session?.invalidate()
        session = nil
    }

    // MARK: - NISessionDelegate Conformance

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else { return }

        let distance = nearbyObject.distance.map { Double($0) } ?? 0.0
        let azimuth = nearbyObject.direction.map { Double($0.x) } ?? 0.0
        let elevation = nearbyObject.direction.map { Double($0.y) } ?? 0.0

        let result = RangingResult(
            address: nearbyObject.discoveryToken.description,
            distance: distance,
            azimuth: azimuth,
            elevation: elevation
        )
        flutterApi.onRangingResult(result: result) { _ in }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        flutterApi.onRangingError(error: error.localizedDescription) { _ in }
        stopRanging()
    }
    
    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // Handle peer removal if necessary, e.g., notify Flutter
    }
}
