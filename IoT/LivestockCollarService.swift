//
//  LivestockCollarService.swift
//  IoT
//
//  Created by Parth Patel on 2026-11-05.
//

import Foundation
import CoreLocation
import UIKit
import AudioToolbox
import CocoaMQTT

struct FenceCoordinate: Identifiable {
	let id = UUID()
	let latitude: Double
	let longitude: Double
	var coordinate: CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}
}

@Observable
class LivestockCollarService: NSObject, CLLocationManagerDelegate {
	var isConnected = false
	var isRunning = false
	var currentCueStatus = "Safe"
	var cueIntensity = 0
	var lastSpeed = 0.0
	var currentLocation: CLLocation?
	var activeFenceCoordinates: [FenceCoordinate] = []
	
		// Connection Settings
	let collarID = "cow_ios_01"
	private let brokerHost = AppConfig.brokerHost
	private let brokerPort: UInt16 = AppConfig.brokerPort
	private let mqttUser = AppConfig.mqttUser
	private let mqttPass = AppConfig.mqttPass
	
	private let locationManager = CLLocationManager()
	private var mqttClient: CocoaMQTT?
	private var transmissionTimer: Timer?
	
		// Fallback speed calculation tracking
	private var previousLocation: CLLocation?
	
	override init() {
		super.init()
		UIDevice.current.isBatteryMonitoringEnabled = true
		setupLocation()
		setupMQTT()
	}
	
	private func setupLocation() {
		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
		locationManager.distanceFilter = kCLDistanceFilterNone
		locationManager.activityType = .fitness
		locationManager.allowsBackgroundLocationUpdates = true
		locationManager.pausesLocationUpdatesAutomatically = false
		locationManager.requestWhenInUseAuthorization()
	}
	
	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		if manager.authorizationStatus == .authorizedWhenInUse {
			manager.requestAlwaysAuthorization()
		}
		manager.startUpdatingLocation()
	}
	
	private func setupMQTT() {
		let clientID = "iOS-Collar-" + UUID().uuidString.prefix(6)
		mqttClient = CocoaMQTT(clientID: String(clientID), host: brokerHost, port: brokerPort)
		mqttClient?.username = mqttUser
		mqttClient?.password = mqttPass
		mqttClient?.keepAlive = 60
		mqttClient?.delegate = self
		_ = mqttClient?.connect()
	}
	
	func startCollar() {
		isRunning = true
		locationManager.startUpdatingLocation()
		transmissionTimer?.invalidate()
		transmissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			self?.publishTelemetry()
		}
	}
	
	func stopCollar() {
		isRunning = false
		transmissionTimer?.invalidate()
		transmissionTimer = nil
		previousLocation = nil
	}
	
	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
		
		var calculatedSpeed: Double = 0.0
		
			// 1. Use native hardware speed if available (returns >= 0 when valid)
		if loc.speed >= 0 {
			calculatedSpeed = loc.speed
		} else if let prev = previousLocation {
				// 2. Fallback: calculate delta distance / delta time
			let timeDelta = loc.timestamp.timeIntervalSince(prev.timestamp)
			if timeDelta > 0.1 && timeDelta < 10.0 {
				let distanceDelta = loc.distance(from: prev)
					// Filter out micro-jitter while stationary
				if distanceDelta > 0.5 {
					calculatedSpeed = distanceDelta / timeDelta
				}
			}
		}
		
		self.previousLocation = loc
		self.currentLocation = loc
		
		DispatchQueue.main.async {
			self.lastSpeed = round(calculatedSpeed * 100.0) / 100.0
		}
	}
	
	private func publishTelemetry() {
		guard isConnected, let loc = currentLocation else { return }
		
		let now = Date()
		let formatter = ISO8601DateFormatter()
		formatter.timeZone = .current
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		let timestampString = formatter.string(from: now)
		
		let batteryPct = Double(max(0.0, UIDevice.current.batteryLevel * 100.0))
		
		let payload: [String: Any] = [
			"collar_id": collarID,
			"timestamp": now.timeIntervalSince1970,
			"timestamp_str": timestampString,
			"latitude": loc.coordinate.latitude,
			"longitude": loc.coordinate.longitude,
			"speed": self.lastSpeed,
			"battery_level": round(batteryPct * 10.0) / 10.0
		]
		
		guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
			  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
		
		let topic = "livestock/collars/\(collarID)/telemetry"
		mqttClient?.publish(topic, withString: jsonString, qos: .qos1)
	}
	
		/// Generates and pushes a hazard zone to the Python analytics engine.
		/// - Parameters:
		///   - offsetNorthMeters: Defaults to 2.0 meters North of current position.
		///   - offsetEastMeters: Defaults to 0.0 meters.
		///   - sizeMeters: Side length of the box (defaults to 3.0 meters wide).
	func deployHazardZone(offsetNorthMeters: Double = 2.0, offsetEastMeters: Double = 0.0, sizeMeters: Double = 3.0) {
		guard let loc = currentLocation else { return }
		
		let centerLat = loc.coordinate.latitude + (offsetNorthMeters / 111_000.0)
		let centerLon = loc.coordinate.longitude + (offsetEastMeters / (111_000.0 * cos(loc.coordinate.latitude * .pi / 180.0)))
		
		let halfSize = sizeMeters / 2.0
		let latDelta = halfSize / 111_000.0
		let lonDelta = halfSize / (111_000.0 * cos(centerLat * .pi / 180.0))
		
		let vertices: [(Double, Double)] = [
			(centerLat - latDelta, centerLon - lonDelta),
			(centerLat - latDelta, centerLon + lonDelta),
			(centerLat + latDelta, centerLon + lonDelta),
			(centerLat + latDelta, centerLon - lonDelta)
		]
		
		self.activeFenceCoordinates = vertices.map { FenceCoordinate(latitude: $0.0, longitude: $0.1) }
		
		let payload: [String: Any] = [
			"coordinates": vertices.map { ["lat": $0.0, "lon": $0.1] }
		]
		
		if let data = try? JSONSerialization.data(withJSONObject: payload),
		   let jsonStr = String(data: data, encoding: .utf8) {
			mqttClient?.publish("livestock/config/hazard_zone", withString: jsonStr, qos: .qos1)
			print("🗺️ Deployed 3m hazard zone, 2m North of current location.")
		}
	}
}

	// MARK: - CocoaMQTTDelegate
extension LivestockCollarService: CocoaMQTTDelegate {
	func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
		if ack == .accept {
			DispatchQueue.main.async { self.isConnected = true }
			mqtt.subscribe("livestock/collars/\(collarID)/cue_command", qos: .qos1)
		}
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
		guard let data = message.string?.data(using: .utf8),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let intensity = json["cue_intensity"] as? Int,
			  let status = json["status"] as? String else { return }
		
		DispatchQueue.main.async {
			self.cueIntensity = intensity
			self.currentCueStatus = status
			
			if intensity >= 100 {
				AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
				AudioServicesPlaySystemSound(1005)
			} else if intensity >= 50 {
				UINotificationFeedbackGenerator().notificationOccurred(.warning)
			}
		}
	}
	
	func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
		DispatchQueue.main.async { self.isConnected = false }
	}
	
	func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
	func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
	func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
	func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
	func mqttDidPing(_ mqtt: CocoaMQTT) {}
	func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}
