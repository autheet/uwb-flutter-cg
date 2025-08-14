
import Flutter
import UIKit
import NearbyInteraction
import MultipeerConnectivity

// By default, FlutterError does not conform to the Swift Error protocol.
// We can make it conform by adding an extension.
extension FlutterError: Error {}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi, NISessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    
    var advertiser: MCNearbyServiceAdvertiser?
    var browser: MCNearbyServiceBrowser?
    var mcSession: MCSession?
    var niSession: NISession?
    var peerID: MCPeerID?
    
    var flutterApi: UwbFlutterApi?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = UwbPlugin()
        UwbHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        instance.flutterApi = UwbFlutterApi(binaryMessenger: registrar.messenger())
    }

    public func start(deviceName: String, serviceUUIDDigest: String, completion: @escaping (Result<Void, Error>) -> Void) {
        peerID = MCPeerID(displayName: deviceName)
        mcSession = MCSession(peer: peerID!, securityIdentity: nil, encryptionPreference: .required)
        mcSession?.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: peerID!, discoveryInfo: nil, serviceType: "uwb-test")
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        browser = MCNearbyServiceBrowser(peer: peerID!, serviceType: "uwb-test")
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        niSession = NISession()
        niSession?.delegate = self
        
        completion(.success(Void()))
    }

    public func stop(completion: @escaping (Result<Void, Error>) -> Void) {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        mcSession?.disconnect()
        niSession?.invalidate()
        completion(.success(Void()))
    }

    public func startIosController(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        guard let discoveryToken = niSession?.discoveryToken else {
            return completion(.failure(FlutterError(code: "uwb", message: "Missing discovery token", details: nil)))
        }
        guard let tokenData = discoveryToken.toFlutterStandardTypedData() else {
            return completion(.failure(FlutterError(code: "uwb", message: "Failed to convert discovery token to data", details: nil)))
        }
        completion(.success(tokenData))
    }

    public func startIosAccessory(token: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = NIDiscoveryToken.fromFlutterStandardTypedData(token) else {
            return completion(.failure(FlutterError(code: "uwb", message: "Invalid token", details: nil)))
        }
        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession?.run(config)
        completion(.success(Void()))
    }

    public func getAndroidAccessoryConfigurationData(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        completion(.failure(FlutterError(code: "uwb", message: "This method is for Android only.", details: nil)))
    }

    public func initializeAndroidController(accessoryConfigurationData: FlutterStandardTypedData, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        completion(.failure(FlutterError(code: "uwb", message: "This method is for Android only.", details: nil)))
    }

    public func startAndroidRanging(configData: FlutterStandardTypedData, isController: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(FlutterError(code: "uwb", message: "This method is for Android only.", details: nil)))
    }
    
    // MARK: - NISessionDelegate
    
    public func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            guard let tokenData = object.discoveryToken.toFlutterStandardTypedData() else {
                continue
            }
            let result = RangingResult(
                peerAddress: tokenData.data.toHexString(),
                deviceName: "",
                distance: Double(object.distance ?? 0),
                azimuth: Double(object.direction?.x ?? 0),
                elevation: Double(object.direction?.y ?? 0)
            )
            flutterApi?.onRangingResult(result: result, completion: { _ in })
        }
    }
    
    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        for object in nearbyObjects {
            guard let tokenData = object.discoveryToken.toFlutterStandardTypedData() else {
                continue
            }
            flutterApi?.onPeerLost(deviceName: "", peerAddress: tokenData.data.toHexString(), completion: { _ in })
        }
    }
    
    public func sessionWasSuspended(_ session: NISession) {
        
    }
    
    public func sessionSuspensionEnded(_ session: NISession) {
        
    }
    
    public func session(_ session: NISession, didInvalidateWith error: Error) {
        flutterApi?.onRangingError(error: error.localizedDescription, completion: { _ in })
    }
    
    // MARK: - MCNearbyServiceAdvertiserDelegate
    
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, mcSession)
    }
    
    // MARK: - MCNearbyServiceBrowserDelegate
    
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: mcSession!, withContext: nil, timeout: 10)
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        
    }
    
    // MARK: - MCSessionDelegate
    
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .connected {
            flutterApi?.onPeerDiscovered(deviceName: peerID.displayName, peerAddress: "", completion: { _ in })
        } else if state == .notConnected {
            flutterApi?.onPeerLost(deviceName: peerID.displayName, peerAddress: "", completion: { _ in })
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        
    }
    
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
    }
    
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        
    }
    
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        
    }
}

extension NIDiscoveryToken {
    func toFlutterStandardTypedData() -> FlutterStandardTypedData? {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
            return FlutterStandardTypedData(bytes: data)
        } catch {
            print("UwbPlugin: Failed to archive discovery token: \(error)")
            return nil
        }
    }
    
    static func fromFlutterStandardTypedData(_ data: FlutterStandardTypedData) -> NIDiscoveryToken? {
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data.data)
        } catch {
            print("UwbPlugin: Failed to unarchive discovery token: \(error)")
            return nil
        }
    }
}

extension Data {
    func toHexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
