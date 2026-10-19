import SwiftUI

struct ContentView: View {
    @StateObject private var scale = BLEScaleManager()
    @State private var useMetric = true
    @State private var showRaw = false
    @State private var showProfile = false

    // Profile (needed by the body-composition formulas)
    @AppStorage("sexRaw") private var sexRaw = 1          // 1 male, 0 female
    @AppStorage("age") private var age = 30
    @AppStorage("heightCm") private var heightCm = 170.0

    private var profile: BodyProfile {
        BodyProfile(sex: Sex(rawValue: sexRaw) ?? .male, age: age, heightCm: heightCm)
    }

    private var comp: BodyComposition? {
        guard let r = scale.latest, r.stable, profile.isSet else { return nil }
        return BodyCompEngine.compute(weightKg: r.weightKg, profile: profile, impedanceZ: r.impedance)
    }

    private func weightText(_ kg: Double) -> String {
        useMetric ? String(format: "%.2f kg", kg) : String(format: "%.1f lb", kg / 0.45359237)
    }

    private func massText(_ kg: Double) -> String {
        useMetric ? String(format: "%.1f kg", kg) : String(format: "%.1f lb", kg / 0.45359237)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text(scale.latest.map { weightText($0.weightKg) } ?? "--")
                        .font(.system(size: 60, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .padding(.top, 20)

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
                            VStack(spacing: 0) {
                                ForEach(scale.discovered, id: \.identifier) { p in
                                    Button(p.name ?? "Unknown") { scale.connect(p) }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 10)
                                    Divider()
                                }
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        Button("Disconnect") { scale.disconnect() }
                            .buttonStyle(.bordered)
                    }

                    if let c = comp {
                        metricsPanel(c)
                    } else if scale.latest?.stable == true && !profile.isSet {
                        Text("Set your age, sex and height (gear icon) to see body composition.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Scale")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: { Image(systemName: "person.crop.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRaw = true } label: { Image(systemName: "terminal") }
                }
            }
            .sheet(isPresented: $showProfile) { profileSheet }
            .sheet(isPresented: $showRaw) { rawSheet }
        }
    }

    @ViewBuilder
    private func metricsPanel(_ c: BodyComposition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metricRow("BMI", String(format: "%.1f", c.bmi))
            metricRow("Body fat", String(format: "%.1f %%", c.bodyFatPct))
            metricRow("Fat mass", massText(c.fatMassKg))
            metricRow("Fat-free mass", massText(c.fatFreeMassKg))
            metricRow("Muscle mass", massText(c.muscleMassKg))
            metricRow("Body water", String(format: "%.1f %%", c.waterPct))
            metricRow("Bone mass", massText(c.boneMassKg))
            metricRow("BMR", String(format: "%.0f kcal/day", c.bmr))

            Text(c.usedImpedance
                 ? "Estimates from open formulas (Kyle 2001, Mifflin-St Jeor). Not identical to the OKOK app, and not a medical measurement."
                 : "No impedance detected from this scale yet, so body fat here is a BMI-based estimate only. Open the raw log and send it to lock in impedance decoding.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.08)))
        .padding(.horizontal)
    }

    private func metricRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private var profileSheet: some View {
        NavigationStack {
            Form {
                Picker("Sex", selection: $sexRaw) {
                    Text("Male").tag(1)
                    Text("Female").tag(0)
                }
                Stepper("Age: \(age)", value: $age, in: 10...100)
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("cm", value: $heightCm, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("cm").foregroundStyle(.secondary)
                }
                Section {
                    Text("These feed the body-composition math. The scale only sends weight and impedance; everything else is computed here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showProfile = false }
                }
            }
        }
    }

    private var rawSheet: some View {
        NavigationStack {
            List(scale.rawLog, id: \.self) {
                Text($0).font(.system(.caption2, design: .monospaced))
            }
            .navigationTitle("Raw BLE log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showRaw = false }
                }
            }
        }
    }
}
