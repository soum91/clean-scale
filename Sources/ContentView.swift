import SwiftUI

struct ContentView: View {
    @StateObject private var scale = BLEScaleManager()
    @State private var useMetric = true
    @State private var showRaw = false

    private var displayWeight: String {
        guard let kg = scale.latest?.weightKg else { return "--" }
        if useMetric { return String(format: "%.2f kg", kg) }
        return String(format: "%.1f lb", kg / 0.45359237)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(displayWeight)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.top, 32)

                Text(scale.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Units", selection: $useMetric) {
                    Text("kg").tag(true)
                    Text("lb").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                if scale.connectedName == nil {
                    Button(scale.scanning ? "Stop scan" : "Scan for scale") {
                        scale.scanning ? scale.stopScan() : scale.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!scale.bluetoothReady)

                    if !scale.discovered.isEmpty {
                        List(scale.discovered, id: \.identifier) { p in
                            Button(p.name ?? "Unknown") { scale.connect(p) }
                        }
                        .frame(maxHeight: 220)
                    }
                } else {
                    Button("Disconnect") { scale.disconnect() }
                        .buttonStyle(.bordered)
                }

                if !scale.history.isEmpty {
                    List(scale.history.prefix(10)) { r in
                        HStack {
                            Text(r.date.formatted(date: .omitted, time: .shortened))
                            Spacer()
                            Text(useMetric
                                 ? String(format: "%.2f kg", r.weightKg)
                                 : String(format: "%.1f lb", r.weightKg / 0.45359237))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                    .frame(maxHeight: 180)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Scale")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRaw.toggle() } label: { Image(systemName: "terminal") }
                }
            }
            .sheet(isPresented: $showRaw) {
                NavigationStack {
                    List(scale.rawLog, id: \.self) { Text($0).font(.system(.caption2, design: .monospaced)) }
                        .navigationTitle("Raw BLE log")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showRaw = false }
                            }
                        }
                }
            }
        }
    }
}
