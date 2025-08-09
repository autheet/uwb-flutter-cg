import Flutter
import UIKit
import NearbyInteraction
import os

class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi {
    private var niManager: NISessionManager?

    // This static property is a workaround to hold the FlutterApi instance.
    static var flutterApi: UwbFlutterApi?

    override init() {
        super.init()
        if NISession.isSupported {
            niManager = NISessionManager()
        }
    }

    func isUwbSupported() throws -> Bool {
        return NISession.isSupported
    }

    func getLocalUwbAddress(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        guard let manager = niManager else {
            completion(.failure(FlutterError(code: "UWB_UNSUPPORTED", message: "UWB is not supported on this device.", details: nil)))
            return
        }
        do {
            let tokenData = try manager.getLocalDiscoveryToken()
            completion(.success(FlutterStandardTypedData(bytes: tokenData)))
        } catch {
            completion(.failure(error))
        }
    }

    func startRanging(peerAddress: FlutterStandardTypedData, config: UwbSessionConfig, isAccessory: Bool) throws {
        guard let manager = niManager else {
            throw FlutterError(code: "UWB_UNSUPPORTED", message: "UWB is not supported on this device.", details: nil)
        }
        try manager.startRanging(with: peerAddress.data, config: config, isAccessory: isAccessory)
    }

    func stopRanging(peerAddress: FlutterStandardTypedData) throws {
        guard let manager = niManager else { return }
        manager.stopRanging(with: peerAddress.data)
    }

    func stopUwbSessions() throws {
        guard let manager = niManager else { return }
        manager.stopAllSessions()
    }

    // Static registration method for the plugin.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let api: UwbHostApi & NSObjectProtocol = UwbPlugin()
        UwbHostApiSetup.setUp(binaryMessenger: messenger, api: api)
        UwbPlugin.flutterApi = UwbFlutterApi(binaryMessenger: messenger)
    }
}
