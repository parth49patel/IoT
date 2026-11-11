//
//  AppConfig.swift
//  IoT
//
//  Created by Parth Patel on 2026-11-11.
//

import Foundation

enum AppConfig {
	private static let infoDictionary: [String: Any] = {
		guard let dict = Bundle.main.infoDictionary else {
			fatalError("Info.plist not found")
		}
		return dict
	}()
	
	static let brokerHost: String = {
		guard let host = infoDictionary["MQTTBrokerHost"] as? String, !host.isEmpty else {
			fatalError("MQTTBrokerHost not set in Secrets.xcconfig")
		}
		return host
	}()
	
	static let brokerPort: UInt16 = {
		guard let portStr = infoDictionary["MQTTBrokerPort"] as? String,
			  let port = UInt16(portStr) else {
			return 1883
		}
		return port
	}()
	
	static let mqttUser: String = {
		return infoDictionary["MQTTUser"] as? String ?? ""
	}()
	
	static let mqttPass: String = {
		return infoDictionary["MQTTPass"] as? String ?? ""
	}()
}
