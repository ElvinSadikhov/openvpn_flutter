//
//  PacketTunnelProvider.swift
//  VPNExtension
//
//  Created by Mochamad Nizwar Syafuan on 31/12/21.
//

import NetworkExtension
import SkVPNAdapter
import os.log

extension NEPacketTunnelFlow: SkVPNAdapterPacketFlow {}

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    lazy var vpnAdapter: SkVPNAdapter = {
        let adapter = SkVPNAdapter()
        adapter.delegate = self
        return adapter
    }()
    
    let vpnReachability = SkVPNReachability()
    var providerManager: NETunnelProviderManager!
    
    var startHandler: ((Error?) -> Void)?
    var stopHandler: (() -> Void)?
    var groupIdentifier: String?
    
    static var connectionIndex = 0;
    static var timeOutEnabled = true;
    
    func loadProviderManager(completion:@escaping (_ error : Error?) -> Void)  {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error)  in
            if error == nil {
                self.providerManager = managers?.first ?? NETunnelProviderManager()
                completion(nil)
            } else {
                completion(error)
            }
        }
    }
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) { 
        guard
            let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
            let providerConfiguration = protocolConfiguration.providerConfiguration
        else {
            fatalError()
        }
        guard let ovpnFileContent: Data = providerConfiguration["config"] as? Data else {
            fatalError()
        }
        
        guard let groupIdentifier: Data = providerConfiguration["groupIdentifier"] as? Data else{
            fatalError()
        }
        self.groupIdentifier = String(decoding: groupIdentifier, as: UTF8.self)
                    
        let configuration = SkVPNConfiguration()
        configuration.fileContent = ovpnFileContent
        configuration.tunPersist = false
        
        // Apply SkVPN configuration.
        let properties: SkVPNConfigurationEvaluation
        do {
            properties = try vpnAdapter.apply(configuration: configuration)
        } catch {
            completionHandler(error)
            return
        }
        
        if !properties.autologin {
            guard let username = options?["username"] as? String, let password = options?["password"] as? String else {
                fatalError()
            }
            let credentials = SkVPNCredentials()
            credentials.username = username
            credentials.password = password
            do {
                try vpnAdapter.provide(credentials: credentials)
            } catch {
                completionHandler(error)
                return
            }
        }
        
        vpnReachability.startTracking { [weak self] status in
            guard status == .reachableViaWiFi else { return }
            self?.vpnAdapter.reconnect(afterTimeInterval: 5)
        }
        startHandler = completionHandler
        vpnAdapter.connect(using: packetFlow)
    }
    
    @objc func stopVPN() {
        loadProviderManager { (err :Error?) in
            if err == nil {
                self.providerManager.connection.stopVPNTunnel();
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopHandler = completionHandler
        if vpnReachability.isTracking {
            vpnReachability.stopTracking()
        }
        vpnAdapter.disconnect()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        if String(data: messageData, encoding: .utf8) == "OPENVPN_STATS" {            
            var toSave = ""
            let formatter = DateFormatter();
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss";            
            toSave += UserDefaults.init(suiteName: groupIdentifier)?.string(forKey: "connected_on") ?? ""
            toSave+="_"
            toSave += String(vpnAdapter.interfaceStatistics.packetsIn)
            toSave+="_"
            toSave += String(vpnAdapter.interfaceStatistics.packetsOut)
            toSave+="_"
            toSave += String(vpnAdapter.interfaceStatistics.bytesIn)
            toSave+="_"
            toSave += String(vpnAdapter.interfaceStatistics.bytesOut)
            UserDefaults.init(suiteName: groupIdentifier)?.setValue(toSave, forKey: "connectionUpdate")
        }
    }
}

extension PacketTunnelProvider: SkVPNAdapterDelegate {
    func skVPNAdapter(_ skVPNAdapter: SkVPNAdapter, configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?, completionHandler: @escaping (Error?) -> Void) {
        networkSettings?.dnsSettings?.matchDomains = [""]
        setTunnelNetworkSettings(networkSettings, completionHandler: completionHandler)
    }
     
    
    func _updateEvent(_ event: SkVPNAdapterEvent, skVPNAdapter: SkVPNAdapter) {
        var toSave = ""
        let formatter = DateFormatter();
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss";
        switch event {
        case .connected:
            toSave = "CONNECTED"
            UserDefaults.init(suiteName: groupIdentifier)?.setValue(formatter.string(from: Date.now), forKey: "connected_on")
            break
        case .disconnected:
            toSave = "DISCONNECTED"
            break
        case .connecting:
            toSave = "CONNECTING"
            break
        case .reconnecting:
            toSave = "RECONNECTING"
            break
        case .info:
            toSave = "CONNECTED"
            break
        default:
            UserDefaults.init(suiteName: groupIdentifier)?.removeObject(forKey: "connected_on")
            toSave = "INVALID"
        }
        UserDefaults.init(suiteName: groupIdentifier)?.setValue(toSave, forKey: "vpnStage")
    }
    
    func skVPNAdapter(_ skVPNAdapter: SkVPNAdapter, handleEvent event: SkVPNAdapterEvent, message: String?) {
        PacketTunnelProvider.timeOutEnabled = true;
        _updateEvent(event, skVPNAdapter: skVPNAdapter)
        switch event {
        case .connected:
            PacketTunnelProvider.timeOutEnabled = false;
            if reasserting {
                reasserting = false
            }
            guard let startHandler = startHandler else { return }
            startHandler(nil)
            self.startHandler = nil
            break
        case .disconnected:
            PacketTunnelProvider.timeOutEnabled = false;
            guard let stopHandler = stopHandler else { return }
            if vpnReachability.isTracking {
                vpnReachability.stopTracking()
            }
            stopHandler()
            self.stopHandler = nil
            break
        case .reconnecting:
            reasserting = true
            break
        default:
            break
        }
    }
    
    func skVPNAdapter(_ skVPNAdapter: SkVPNAdapter, handleError error: Error) {
        guard let fatal = (error as NSError).userInfo[SkVPNAdapterErrorFatalKey] as? Bool, fatal == true else {
            return
        }
        if vpnReachability.isTracking {
            vpnReachability.stopTracking()
        }
        if let startHandler = startHandler {
            startHandler(error)
            self.startHandler = nil
        } else {
            cancelTunnelWithError(error)
        }
    }
    
    func skVPNAdapter(_ skVPNAdapter: SkVPNAdapter, handleLogMessage logMessage: String) {
    }
}
