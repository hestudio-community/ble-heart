//
//  ContentView.swift
//  BLE Heart
//
//  Created by undefined on 2025/10/28.
//

import SwiftUI
import Combine
import CoreBluetooth

struct ContentView: View {
    @StateObject private var ble = BLEHeartRateManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BLE 心率监测")
                .font(.title2)

            HStack {
                Image(systemName: "heart.fill").symbolRenderingMode(.multicolor)
                Text(ble.heartRate.map { String($0) } ?? "--")
                    .monospacedDigit()
                Text("BPM")
                    .foregroundStyle(.secondary)
            }
            .font(.largeTitle)

            GroupBox("设备") {
                if bleDevices.isEmpty {
                    Text("未发现设备")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bleDevices, id: \.identifier) { p in
                        HStack {
                            Text(p.name ?? "未知设备")
                            Spacer()
                            if ble.selectedPeripheral?.identifier == p.identifier {
                                Text("已连接")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("连接") { ble.selectPeripheral(p) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            HStack {
                Button(ble.isScanning ? "停止扫描" : "开始扫描") {
                    if ble.isScanning { ble.stopScan() } else { ble.startScan() }
                }
                if ble.selectedPeripheral != nil {
                    Button("断开连接") { ble.disconnect() }
                }
            }

            Spacer()
        }
        .padding()
    }

    private var bleDevices: [CBPeripheral] { ble.devices }
}

#Preview {
    ContentView()
}
