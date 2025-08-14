
import Flutter
import UIKit

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = UwbPlugin()
    UwbHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
  }

  public func start(deviceName: String, serviceUUIDDigest: String, completion: @escaping (Result<Void, Error>) -> Void) {
    // Your implementation here
  }

  public func stop(completion: @escaping (Result<Void, Error>) -> Void) {
    // Your implementation here
  }

  public func startIosController(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    // Your implementation here
  }

  public func startIosAccessory(token: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
    // Your implementation here
  }

  public func getAndroidAccessoryConfigurationData(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    // Your implementation here
  }

  public func initializeAndroidController(accessoryConfigurationData: FlutterStandardTypedData, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    // Your implementation here
  }

  public func startAndroidRanging(configData: FlutterStandardTypedData, isController: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    // Your implementation here
  }
}
