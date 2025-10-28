import SwiftUI
import CoreBluetooth

@main
struct HeartRateMenuBarApp: App {
    @StateObject private var ble = BLEHeartRateManager()

    var body: some Scene {
        MenuBarExtra(content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("心率: \(ble.heartRate ?? 0) BPM")
                    .lineLimit(1)
                    .allowsTightening(true)
                    .monospacedDigit()

                Section {
                    let devices = ble.devices
                    if devices.isEmpty {
                        Text("未发现设备")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(devices, id: \.identifier) { peripheral in
                            Button(action: { ble.selectPeripheral(peripheral) }) {
                                HStack {
                                    Text(peripheral.name ?? "未知设备")
                                    if ble.selectedPeripheral?.identifier == peripheral.identifier {
                                        Spacer()
                                        Text("已选择")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("设备")
                }

                HStack {
                    Button(ble.isScanning ? "停止扫描" : "开始扫描") {
                        if ble.isScanning { ble.stopScan() } else { ble.startScan() }
                    }
                    if ble.selectedPeripheral != nil {
                        Button("断开连接") { ble.disconnect() }
                    }
                }

                Divider()
                Button("退出") { NSApp.terminate(nil) }
            }
            .padding(8)
        }, label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .symbolRenderingMode(.multicolor)
                if let bpm = ble.heartRate {
                    Text("\(bpm)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                }
            }
        })
    }
}
