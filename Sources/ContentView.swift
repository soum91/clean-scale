import SwiftUI

struct ContentView: View {
    @StateObject private var scale = BLEScaleManager()
    @State private var useMetric = true
    @State private var showRaw = false
    @State private var showProfile = false

    @AppStorage("sexRaw") private var sexRaw = 1
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
        useMetric ? String(format: "%.2f", kg) : String(format: "%.1f", kg / 0.45359237)
    }
    private func massText(_ kg: Double) -> String {
        useMetric ? String(format: "%.1f", kg) : String(format: "%.1f", kg / 0.45359237)
    }
    private var unit: String { useMetric ? "kg" : "lb" }

    var body: some View {
        ZStack {
            T.ink.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 26) {
                        hero
                        connection
                        results
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 44)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showProfile) { profileSheet.preferredColorScheme(.dark) }
        .sheet(isPresented: $showRaw) { rawSheet.preferredColorScheme(.dark) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(T.amber).frame(width: 10, height: 10)
            Text("Scale")
                .font(.system(size: 19, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(T.text)
            Spacer()
            iconButton("person.crop.circle") { showProfile = true }
            iconButton("terminal") { showRaw = true }
        }
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(T.muted)
                .frame(width: 36, height: 36)
                .background(Circle().fill(T.surface))
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scale.latest.map { weightText($0.weightKg) } ?? "0.00")
                    .font(.system(size: 76, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(scale.latest == nil ? T.muted.opacity(0.4) : T.text)
                Text(unit)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(T.muted)
            }
            .padding(.top, 10)

            statusPill
            unitToggle
        }
    }

    private var statusPill: some View {
        let live = scale.latest?.stable == true
        return HStack(spacing: 7) {
            Circle()
                .fill(live ? T.mint : T.muted)
                .frame(width: 7, height: 7)
            Text(scale.status)
                .font(.footnote)
                .foregroundStyle(T.muted)
        }
    }

    private var unitToggle: some View {
        HStack(spacing: 0) {
            unitButton("kg", metric: true)
            unitButton("lb", metric: false)
        }
        .padding(3)
        .background(Capsule().fill(T.surface))
        .overlay(Capsule().strokeBorder(T.line, lineWidth: 1))
    }

    private func unitButton(_ title: String, metric: Bool) -> some View {
        let on = useMetric == metric
        return Button { useMetric = metric } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? T.ink : T.muted)
                .padding(.vertical, 6)
                .padding(.horizontal, 22)
                .background(Capsule().fill(on ? T.amber : .clear))
        }
    }

    // MARK: Connection

    @ViewBuilder
    private var connection: some View {
        if scale.connectedName == nil {
            VStack(spacing: 12) {
                Button {
                    scale.scanning ? scale.stopScan() : scale.startScan()
                } label: {
                    Text(scale.scanning ? "Stop scanning" : "Scan for scale")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(scale.scanning ? T.text : T.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(scale.scanning ? T.surface : T.amber)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(scale.scanning ? T.line : .clear, lineWidth: 1)
                        )
                }
                .opacity(scale.bluetoothReady ? 1 : 0.4)
                .disabled(!scale.bluetoothReady)

                if !scale.discovered.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(scale.discovered.enumerated()), id: \.element.identifier) { idx, p in
                            Button { scale.connect(p) } label: {
                                HStack {
                                    Text(p.name ?? "Unknown device")
                                        .foregroundStyle(T.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(T.muted)
                                }
                                .padding(.vertical, 14)
                            }
                            if idx < scale.discovered.count - 1 {
                                Rectangle().fill(T.line).frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(T.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(T.line, lineWidth: 1))
                }
            }
        } else {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(T.mint)
                    Text(scale.connectedName ?? "Connected")
                        .foregroundStyle(T.text)
                }
                .font(.subheadline)
                Spacer()
                Button("Disconnect") { scale.disconnect() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(T.amber)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(T.line, lineWidth: 1))
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if let c = comp {
            VStack(spacing: 22) {
                bodyFatGauge(c.bodyFatPct, estimate: !c.usedImpedance)
                metricsGrid(c)
                Text(c.usedImpedance
                     ? "Estimated from your weight and impedance using open equations (Kyle 2001, Mifflin-St Jeor). Close to the OKOK app, not identical, and not a medical measurement."
                     : "Body fat here is a BMI-based estimate. To read it from the sensor, open the log, step on, and share the raw bytes so impedance decoding can be set for this scale.")
                    .font(.caption2)
                    .foregroundStyle(T.muted)
            }
        } else if scale.latest?.stable == true && !profile.isSet {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 26))
                    .foregroundStyle(T.muted)
                Text("Add your age, sex and height to see body composition.")
                    .font(.footnote)
                    .foregroundStyle(T.muted)
                    .multilineTextAlignment(.center)
                Button("Set up profile") { showProfile = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(T.amber)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(T.line, lineWidth: 1))
        }
    }

    private func bodyFatGauge(_ pct: Double, estimate: Bool) -> some View {
        let lo = 5.0, hi = 45.0
        let frac = min(1, max(0, (min(hi, max(lo, pct)) - lo) / (hi - lo)))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Body fat")
                    .font(.subheadline)
                    .foregroundStyle(T.muted)
                Spacer()
                Text(String(format: "%.1f%%", pct))
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(T.text)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(T.surface).frame(height: 10)
                    Capsule().fill(T.amber).frame(width: max(10, w * frac), height: 10)
                    Circle()
                        .fill(T.text)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(T.ink, lineWidth: 4))
                        .offset(x: min(w - 16, max(0, w * frac - 8)))
                }
            }
            .frame(height: 18)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.surface.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(T.line, lineWidth: 1))
    }

    private func metricsGrid(_ c: BodyComposition) -> some View {
        let tiles: [(String, String, String)] = [
            ("figure.arms.open",   massText(c.muscleMassKg) + " " + unit, "Muscle"),
            ("drop.fill",          String(format: "%.1f%%", c.waterPct),   "Body water"),
            ("scalemass",          massText(c.fatFreeMassKg) + " " + unit, "Fat-free mass"),
            ("ruler",              String(format: "%.1f", c.bmi),          "BMI"),
            ("flame.fill",         String(format: "%.0f", c.bmr),          "BMR kcal/day"),
            ("circle.hexagongrid", massText(c.boneMassKg) + " " + unit,    "Bone")
        ]
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(tiles, id: \.2) { t in
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: t.0)
                        .font(.system(size: 15))
                        .foregroundStyle(T.muted)
                    Text(t.1)
                        .font(.system(size: 21, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(T.amber)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(t.2)
                        .font(.caption)
                        .foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(RoundedRectangle(cornerRadius: 16).fill(T.surface))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(T.line, lineWidth: 1))
            }
        }
    }

    // MARK: Sheets

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
                        .frame(width: 70)
                    Text("cm").foregroundStyle(.secondary)
                }
                Section {
                    Text("These feed the body-composition math. The scale only sends weight and impedance; everything else is worked out here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showProfile = false }.foregroundStyle(T.amber)
                }
            }
        }
    }

    private var rawSheet: some View {
        NavigationStack {
            Group {
                if scale.rawLog.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 26)).foregroundStyle(T.muted)
                        Text("Connect and step on the scale.\nEvery byte it sends shows up here.")
                            .font(.footnote).foregroundStyle(T.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(scale.rawLog, id: \.self) {
                        Text($0).font(.system(.caption2, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Raw BLE log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showRaw = false }.foregroundStyle(T.amber)
                }
            }
        }
    }
}
