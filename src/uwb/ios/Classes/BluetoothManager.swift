/*
 * @file      BluetoothLECentral.swift
 *
 * @brief     A class that manages connection and data transfer to the accessories using Core Bluetooth.
 *
 * @author    Decawave Applications
 *            Modified by Chrstian Greiner
 *
 * @attention Copyright (c) 2021 - 2022, Qorvo US, Inc.
 *
 * All rights reserved
 * Redistribution and use in source and binary forms, with or without modification,
 *  are permitted provided that the following conditions are met:
 * 1. Redistributions of source code must retain the above copyright notice, this
 *  list of conditions, and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *  this list of conditions and the following disclaimer in the documentation
 *  and/or other materials provided with the distribution.
 * 3. You may only use this software, with or without any modification, with an
 *  integrated circuit developed by Qorvo US, Inc. or any of its affiliates
 *  (collectively, "Qorvo"), or any module that contains such integrated circuit.
 * 4. You may not reverse engineer, disassemble, decompile, decode, adapt, or
 *  otherwise attempt to derive or gain access to the source code to any software
 *  distributed under this license in binary or object code form, in whole or in
 *  part.
 * 5. You may not use any Qorvo name, trademarks, service marks, trade dress,
 *  logos, trade names, or other symbols or insignia identifying the source of
 *  Qorvo's products or services, or the names of any of Qorvo's developers to
 *  endorse or promote products derived from this software without specific prior
 *  written permission from Qorvo US, Inc. You must not call products derived from
 *  this software "Qorvo", you must not have "Qorvo" appear in their name, without
 *  the prior permission from Qorvo US, Inc.
 * 6. Qorvo may publish revised or new version of this license from time to time.
 *  No one other than Qorvo US, Inc. has the right to modify the terms applicable
 *  to the software provided under this license.
 * THIS SOFTWARE IS PROVIDED BY QORVO US, INC. "AS IS" AND ANY EXPRESS OR IMPLIED
 *  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. NEITHER
 *  QORVO, NOR ANY PERSON ASSOCIATED WITH QORVO MAKES ANY WARRANTY OR
 *  REPRESENTATION WITH RESPECT TO THE COMPLETENESS, SECURITY, RELIABILITY, OR
 *  ACCURACY OF THE SOFTWARE, THAT IT IS ERROR FREE OR THAT ANY DEFECTS WILL BE
 *  CORRECTED, OR THAT THE SOFTWARE WILL OTHERWISE MEET YOUR NEEDS OR EXPECTATIONS.
 * IN NO EVENT SHALL QORVO OR ANYBODY ASSOCIATED WITH QORVO BE LIABLE FOR ANY
 *  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 *  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 *  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 *  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *
 * Modified by Chrstian Greiner
 * Use for academic purposes
 */

import Foundation

import Foundation
import NearbyInteraction

import CoreBluetooth
import simd
import os

enum BluetoothLECentralError: Error {
    case noPeripheral
}

struct TransferService {
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let txCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
}

struct QorvoNIService {
    static let serviceUUID = CBUUID(string: "2E938FD0-6A61-11ED-A1EB-0242AC120002")
    
    static let scCharacteristicUUID = CBUUID(string: "2E93941C-6A61-11ED-A1EB-0242AC120002")
    static let rxCharacteristicUUID = CBUUID(string: "2E93998A-6A61-11ED-A1EB-0242AC120002")
    static let txCharacteristicUUID = CBUUID(string: "2E939AF2-6A61-11ED-A1EB-0242AC120002")
}

class BluetoothDevice {
    var blePeripheral: CBPeripheral         // BLE Peripheral instance
    var rxCharacteristic: CBCharacteristic? // Characteristics to be used when receiving data
    var txCharacteristic: CBCharacteristic? // Characteristics to be used when sending data

    var bleUniqueID: String
    var blePeripheralName: String            // Name to display
    var blePeripheralStatus: DeviceState?         // Status to display
    var bleTimestamp: Int64                  // Last time that the device adverstised

    init(peripheral: CBPeripheral, uniqueID: String, peripheralName: String, timeStamp: Int64 ) {
        self.blePeripheral = peripheral
        self.bleUniqueID = uniqueID
        self.blePeripheralName = peripheralName
        self.blePeripheralStatus = DeviceState.found
        self.bleTimestamp = timeStamp
    }
}


enum MessageId: UInt8 {
    // Messages from the accessory.
    case accessoryConfigurationData = 0x1
    case accessoryUwbDidStart = 0x2
    case accessoryUwbDidStop = 0x3
    
    // Messages to the accessory.
    case initialize = 0xA
    case configureAndStart = 0xB
    case stop = 0xC
    
    // User defined/notification messages
    case getReserved = 0x20
    case setReserved = 0x21

    case iOSNotify = 0x2F
}

class BluetoothManager: NSObject {
    
    var centralManager: CBCentralManager!
    var bluetoothDevices = [BluetoothDevice?]()

    var writeIterationsComplete = 0
    var connectionIterationsComplete = 0
    var bluetoothReady = false
    var shouldStartWhenReady = false
    
    // The number of times to retry scanning for accessories.
    // Change this value based on your app's testing use case.
    let defaultIterations = 5
    
    var accessoryLostHandler: ((Peer) -> Void)?
    var accessoryDiscoveryHandler: ((Peer) -> Void)?
    var accessoryConnectedHandler: ((Peer) -> Void)?
    var accessoryDisconnectedHandler: ((Peer) -> Void)?
    var accessoryDataHandler: ((Data, Peer) -> Void)?

    private let logger = os.Logger(subsystem: "uwb_plugin", category: "BluetoothDiscovery")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        
        // Initialises the Timer used for Haptic and Sound feedbacks
        _ = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(timerHandler), userInfo: nil, repeats: true)
    }
    
    deinit {
        centralManager.stopScan()
        logger.info("Scanning stopped.")
    }
    
    // Clear peripherals in qorvoDevices[] if not responding for more than one second
    @objc func timerHandler() {
        var index = 0
        
        bluetoothDevices.forEach { (accessory) in
            
            if accessory!.blePeripheralStatus == DeviceState.found {
                // Get current timestamp
                let timeStamp = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                
                // Remove device if timestamp is bigger than 5000 msec
                if timeStamp > (accessory!.bleTimestamp + 5000) {
                    
                    //logger.info("Device \(accessory?.blePeripheralName ?? "Unknown") timed-out removed at index \(index)")
                    //logger.info("Device timestamp: \(accessory!.bleTimestamp) Current timestamp: \(timeStamp) ")
                    if bluetoothDevices.indices.contains(index) {
                        bluetoothDevices.remove(at: index)
                    }
                    
                    if let handler = accessoryLostHandler {
                        handler(Peer(id: accessory!.bleUniqueID, name: accessory!.blePeripheralName))
                    }
                }
            }
            
            index = index + 1
        }
    }
    
    public func start() {
        if bluetoothReady {
            logger.info("Scanning started.")
            centralManager.scanForPeripherals(
                withServices: [TransferService.serviceUUID, QorvoNIService.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        } else {
            shouldStartWhenReady = true
        }
    }

    public func stop() {
        self.centralManager.stopScan()
    }
    
    public func connectPeripheral(deviceId: String) throws {
        if let deviceToConnect = getDeviceFromUniqueID(deviceId: deviceId) {
            if deviceToConnect.blePeripheralStatus != DeviceState.found {
                return
            }
            // Connect to the peripheral.
            logger.info("Connecting to Peripheral \(deviceToConnect.blePeripheral)")
            deviceToConnect.blePeripheralStatus = DeviceState.connected
            centralManager.connect(deviceToConnect.blePeripheral, options: nil)
        }
        else {
            throw BluetoothLECentralError.noPeripheral
        }
    }
    
    public func disconnectPeripheral(deviceId: String) {
        if let deviceToDisconnect = getDeviceFromUniqueID(deviceId: deviceId) {
            if deviceToDisconnect.blePeripheralStatus == DeviceState.found {
                return
            }
            // Disconnect from peripheral.
            logger.info("Disconnecting from Peripheral \(deviceToDisconnect.blePeripheral)")
            centralManager.cancelPeripheralConnection(deviceToDisconnect.blePeripheral)
        }
    }
    
    public func sendData(data: Data, deviceId: String) throws {
        let str = String(format: "Sending Data to device %d", deviceId)
        logger.info("\(str)")
        
        if getDeviceFromUniqueID(deviceId: deviceId) != nil {
            writeData(data: data, deviceId: deviceId)
        }
        else {
            throw BluetoothLECentralError.noPeripheral
        }
    }
    
    // Sends data to the peripheral.
    private func writeData(data: Data, deviceId: String) {
        
        let qorvoDevice = getDeviceFromUniqueID(deviceId: deviceId)

        guard let discoveredPeripheral = qorvoDevice?.blePeripheral
        else { return }
        
        guard let transferCharacteristic = qorvoDevice?.rxCharacteristic
        else { return }
        
        logger.info("Getting TX Characteristics from device \(deviceId).")
        
        let mtu = discoveredPeripheral.maximumWriteValueLength(for: .withResponse)

        let bytesToCopy: size_t = min(mtu, data.count)

        var rawPacket = [UInt8](repeating: 0, count: bytesToCopy)
        data.copyBytes(to: &rawPacket, count: bytesToCopy)
        let packetData = Data(bytes: &rawPacket, count: bytesToCopy)

        let stringFromData = packetData.map { String(format: "0x%02x, ", $0) }.joined()
        logger.info("Writing \(bytesToCopy) bytes: \(String(describing: stringFromData))")

        discoveredPeripheral.writeValue(packetData, for: transferCharacteristic, type: .withResponse)

        writeIterationsComplete += 1
    }
    
    private func getDeviceFromUniqueID(deviceId: String) -> BluetoothDevice? {
        if let index = bluetoothDevices.firstIndex(where: {$0?.bleUniqueID == deviceId}) {
            return bluetoothDevices[index]
        }
        return nil
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    /*
     * When Bluetooth is powered, starts Bluetooth operations.
     *
     * The protocol requires a `centralManagerDidUpdateState` implementation.
     * Ensure you can use the Central by checking whether the its state is
     * `poweredOn`. Your app can check other states to ensure availability such
     * as whether the current device supports Bluetooth LE.
     */
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {

        switch central.state {
            
        // Begin communicating with the peripheral.
        case .poweredOn:
            logger.info("CBManager is powered on")
            bluetoothReady = true
            if shouldStartWhenReady {
                start()
            }
        // In your app, deal with the following states as necessary.
        case .poweredOff:
            logger.error("CBManager is not powered on")
            return
        case .resetting:
            logger.error("CBManager is resetting")
            return
        case .unauthorized:
            handleCBUnauthorized()
            return
        case .unknown:
            logger.error("CBManager state is unknown")
            return
        case .unsupported:
            logger.error("Bluetooth is not supported on this device")
            return
        @unknown default:
            logger.error("A previously unknown central manager state occurred")
            return
        }
    }

    // Reacts to the varying causes of Bluetooth restriction.
    internal func handleCBUnauthorized() {
        
        // Require Permission
        switch CBManager.authorization {
        case .denied:
            // In your app, consider sending the user to Settings to change authorization.
            logger.error("The user denied Bluetooth access.")
        case .restricted:
            logger.error("Bluetooth is restricted")
        default:
            logger.error("Unexpected authorization")
        }
    }

    // Reacts to transfer service UUID discovery.
    // Consider checking the RSSI value before attempting to connect.
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        let timeStamp = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        
        // Check if peripheral is already discovered
        if let qorvoDevice = getDeviceFromUniqueID(deviceId: peripheral.hashValue.description) {
            
            // if yes, update the timestamp
            qorvoDevice.bleTimestamp = timeStamp
            
            return
        }
        
        // If not discovered, include peripheral to bluetoothDevices[]
        // let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let accessory = BluetoothDevice(
            peripheral: peripheral,
            uniqueID: peripheral.hashValue.description,
            peripheralName: peripheral.name ?? "Unknown",
            timeStamp: timeStamp
        )
        bluetoothDevices.append(accessory)
        
        if let newPeripheral = bluetoothDevices.last {
            let nameToPrint = newPeripheral?.blePeripheralName
            logger.info("Peripheral \(nameToPrint ?? "Unknown") included in bluetoothDevices with unique ID")
        }
        
        if let handler = accessoryDiscoveryHandler {
            handler(
                Peer(id: "\(accessory.bleUniqueID)", name: accessory.blePeripheralName)
            )
        }
    }

    // Reacts to connection failure.
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect to \(peripheral). \( String(describing: error))")
    }

    // Discovers the services and characteristics to find the 'TransferService'
    // characteristic after peripheral connection.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Peripheral Connected")

        // Set the iteration info.
        connectionIterationsComplete += 1
        writeIterationsComplete = 0

        // Set the `CBPeripheral` delegate to receive callbacks for its services discovery.
        peripheral.delegate = self

        // Search only for services that match the service UUID.
        peripheral.discoverServices([TransferService.serviceUUID, QorvoNIService.serviceUUID])
    }

    // Cleans up the local copy of the peripheral after disconnection.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("Peripheral Disconnected")
        
        let uniqueID = peripheral.hashValue.description
        let accessory = getDeviceFromUniqueID(deviceId: uniqueID)
        
        // Update Timestamp to avoid premature disconnection
        let timeStamp = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        accessory!.bleTimestamp = timeStamp
        accessory!.blePeripheralStatus = DeviceState.found
        
        bluetoothDevices = bluetoothDevices.filter {$0?.bleUniqueID != uniqueID}
        
        if let handler = accessoryDisconnectedHandler {
            handler(
                Peer(
                    id: "\(accessory!.bleUniqueID)",
                    name: accessory!.blePeripheralName
                 )
            )
        }
    }
}

// An extention to implement `CBPeripheralDelegate` methods.
extension BluetoothManager: CBPeripheralDelegate {
    
    // Reacts to peripheral services invalidation.
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {

        for service in invalidatedServices where service.uuid == TransferService.serviceUUID {
            logger.error("Transfer service is invalidated - rediscover services")
            peripheral.discoverServices([TransferService.serviceUUID])
        }
        for service in invalidatedServices where service.uuid == QorvoNIService.serviceUUID {
            logger.error("Qorvo NI service is invalidated - rediscover services")
            peripheral.discoverServices([QorvoNIService.serviceUUID])
        }
    }

    // Reacts to peripheral services discovery.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logger.error("Error discovering services: \(error.localizedDescription)")
            return
        }

        logger.info("discovered service. Now discovering characteristics")
        // Check the newly filled peripheral services array for more services.
        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            peripheral.discoverCharacteristics([TransferService.rxCharacteristicUUID,
                                                TransferService.txCharacteristicUUID,
                                                QorvoNIService.rxCharacteristicUUID,
                                                QorvoNIService.txCharacteristicUUID], for: service)
        }
    }

    // Subscribes to a discovered characteristic, which lets the peripheral know we want the data it contains.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Deal with errors (if any).
        if let error = error {
            logger.error("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        let uniqueID = peripheral.hashValue.description
        let accessory = getDeviceFromUniqueID(deviceId: uniqueID)
        
        // Check the newly filled peripheral services array for more services.
        guard let serviceCharacteristics = service.characteristics else { return }
        
        // Assign RX Characteristic to the device structure
        for characteristic in serviceCharacteristics where characteristic.uuid == TransferService.rxCharacteristicUUID {
            // Subscribe to the transfer service's `rxCharacteristic`.
            accessory?.rxCharacteristic = characteristic
            logger.info("discovered characteristic: \(characteristic)")
        }
        
        for characteristic in serviceCharacteristics where characteristic.uuid == QorvoNIService.rxCharacteristicUUID {
            // Subscribe to the transfer service's `rxCharacteristic`.
            accessory?.rxCharacteristic = characteristic
            logger.info("discovered characteristic: \(characteristic)")
        }
        
        // Assign TX Characteristic to the device structure
        for characteristic in serviceCharacteristics where characteristic.uuid == TransferService.txCharacteristicUUID {
            // Subscribe to the transfer service's `txCharacteristic`.
            accessory?.txCharacteristic = characteristic
            logger.info("discovered characteristic: \(characteristic)")
            peripheral.setNotifyValue(true, for: characteristic)
        }
        
        for characteristic in serviceCharacteristics where characteristic.uuid == QorvoNIService.txCharacteristicUUID {
            // Subscribe to the transfer service's `txCharacteristic`.
            accessory?.txCharacteristic = characteristic
            logger.info("discovered characteristic: \(characteristic)")
            peripheral.setNotifyValue(true, for: characteristic)
        }
        
        // Wait for the peripheral to send data.
        if let handler = accessoryConnectedHandler {
            handler(Peer(id: "\(accessory!.bleUniqueID)", name: accessory!.blePeripheralName))
        }
    }

    // Reacts to data arrival through the characteristic notification.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Check if the peripheral reported an error.
        if let error = error {
            logger.error("Error discovering characteristics:\(error.localizedDescription)")
            return
        }
        guard let characteristicData = characteristic.value else { return }
    
        let str = characteristicData.map { String(format: "0x%02x, ", $0) }.joined()
        logger.info("Received \(characteristicData.count) bytes: \(str)")
        
        let uniqueID = peripheral.hashValue.description
        let accessory = getDeviceFromUniqueID(deviceId: uniqueID)
        
        if let handler = self.accessoryDataHandler {
            handler(
                characteristicData,
                Peer(id: accessory!.bleUniqueID, name: accessory!.blePeripheralName)
            )
        }
    }

    // Reacts to the subscription status.
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Check if the peripheral reported an error.
        if let error = error {
            logger.error("Error changing notification state: \(error.localizedDescription)")
            return
        }

        if characteristic.isNotifying {
            // Indicates the notification began.
            logger.info("Notification began on \(characteristic)")
        } else {
            // Because the notification stopped, disconnect from the peripheral.
            logger.info("Notification stopped on \(characteristic). Disconnecting")
        }
    }
}
