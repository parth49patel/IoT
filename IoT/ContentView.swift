//
//  ContentView.swift
//  IoT
//
//  Created by Parth Patel on 2026-11-05.
//

import SwiftUI
import MapKit

struct ContentView: View {
	@State private var collarService = LivestockCollarService()
	@State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
	
	var body: some View {
		ZStack(alignment: .bottom) {
				// MARK: - 1. Fullscreen Background Map
			Map(position: $cameraPosition) {
				UserAnnotation()
				
					// Hazard exclusion zone polygon overlay
				if !collarService.activeFenceCoordinates.isEmpty {
					MapPolygon(coordinates: collarService.activeFenceCoordinates.map(\.coordinate))
						.foregroundStyle(Color.red.opacity(0.35))
						.stroke(Color.red, lineWidth: 2)
				}
			}
			.mapControls {
				MapUserLocationButton()
				MapCompass()
			}
			//.ignoresSafeArea()
			
				// MARK: - 2. Bottom Consolidated Console Card
			VStack(spacing: 12) {
					// Header row: Title & Connection pill
				HStack {
					Text("Virtual Collar Node")
						.font(.subheadline.bold())
					
					Spacer()
					
					HStack(spacing: 5) {
						Circle()
							.fill(collarService.isConnected ? Color.green : Color.red)
							.frame(width: 7, height: 7)
						Text(collarService.isConnected ? "MQTT Connected" : "Disconnected")
							.font(.caption2.bold())
					}
					.padding(.horizontal, 8)
					.padding(.vertical, 3)
					.background(Color(.systemBackground).opacity(0.85))
					.clipShape(Capsule())
				}
				
				Divider()
				
					// Telemetry Metrics Row
				HStack {
					VStack(alignment: .leading, spacing: 2) {
						Text("Zone Status")
							.font(.caption2)
							.foregroundStyle(.secondary)
						Text(collarService.currentCueStatus)
							.font(.headline.bold())
							.foregroundStyle(
								collarService.cueIntensity == 100 ? .red :
									(collarService.cueIntensity == 50 ? .orange : .green)
							)
					}
					
					Spacer()
					
					VStack(alignment: .center, spacing: 2) {
						Text("Intensity")
							.font(.caption2)
							.foregroundStyle(.secondary)
						Text("\(collarService.cueIntensity)%")
							.font(.headline.bold())
							.foregroundStyle(collarService.cueIntensity > 0 ? .red : .primary)
					}
					
					Spacer()
					
					VStack(alignment: .trailing, spacing: 2) {
						Text("Speed")
							.font(.caption2)
							.foregroundStyle(.secondary)
						Text("\(String(format: "%.1f", collarService.lastSpeed)) m/s")
							.font(.headline.monospaced())
					}
				}
				
					// GPS Coordinates Line
				HStack {
					Image(systemName: "location.fill")
						.font(.caption2)
						.foregroundStyle(.secondary)
					
					if let loc = collarService.currentLocation {
						Text("\(String(format: "%.5f", loc.coordinate.latitude)), \(String(format: "%.5f", loc.coordinate.longitude))")
							.font(.caption2.monospaced())
							.foregroundStyle(.secondary)
					} else {
						Text("Acquiring GPS fix...")
							.font(.caption2)
							.foregroundStyle(.orange)
					}
					Spacer()
				}
				
					// MARK: - Side-by-Side Action Buttons
				HStack(spacing: 10) {
						// Set Hazard Button
					Button {
						collarService.deployHazardZone(offsetNorthMeters: 2.0, offsetEastMeters: 0.0, sizeMeters: 3.0)
					} label: {
						HStack(spacing: 5) {
							Image(systemName: "arrow.up.circle.fill")
							Text("Set 2m Hazard")
						}
						.font(.footnote.bold())
						.frame(maxWidth: .infinity)
						.padding(.vertical, 10)
						.background(Color.blue)
						.foregroundStyle(.white)
						.cornerRadius(10)
					}
					.disabled(collarService.currentLocation == nil)
					
						// Dynamic Stream Toggle Button
					Button {
						if collarService.isRunning {
							collarService.stopCollar()
						} else {
							collarService.startCollar()
						}
					} label: {
						HStack(spacing: 5) {
							Image(systemName: collarService.isRunning ? "stop.fill" : "play.fill")
							Text(collarService.isRunning ? "Stop Stream" : "Start Stream")
						}
						.font(.footnote.bold())
						.frame(maxWidth: .infinity)
						.padding(.vertical, 10)
						.background(collarService.isRunning ? Color.red : Color.green)
						.foregroundStyle(.white)
						.cornerRadius(10)
					}
				}
			}
			.padding(14)
			.background(.regularMaterial)
			.clipShape(RoundedRectangle(cornerRadius: 18))
			.shadow(color: .black.opacity(0.15), radius: 8, y: -2)
			.padding(.horizontal, 14)
			.padding(.bottom, 24)
		}
	}
}

#Preview {
    ContentView()
}
