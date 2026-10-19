import Foundation

// Body-composition estimates from the scale's two real measurements (weight and
// bioimpedance) plus the user's profile. These use PUBLISHED, open equations, not
// OKOK's proprietary formula, so numbers land in the same ballpark but will not match
// their app to the decimal. Everything here is an estimate, not a clinical measurement.

enum Sex: Int, CaseIterable, Identifiable {
    case male = 1, female = 0
    var id: Int { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

struct BodyProfile {
    var sex: Sex
    var age: Int
    var heightCm: Double
    var isSet: Bool { heightCm > 50 && age > 0 }
}

struct BodyComposition {
    let weightKg: Double
    let bmi: Double
    let bodyFatPct: Double
    let fatMassKg: Double
    let fatFreeMassKg: Double
    let muscleMassKg: Double   // approximate: FFM minus bone
    let boneMassKg: Double      // rough proportional estimate
    let tbwKg: Double           // total body water
    let waterPct: Double
    let bmr: Double             // kcal/day
    let usedImpedance: Bool     // true = impedance-based, false = BMI-based fallback
}

enum BodyCompEngine {

    // Kyle et al. (2001): FFM = -4.104 + 0.518*(H^2/R) + 0.231*W + 0.130*X + 4.229*sex
    // H in cm, R (resistance) and X (reactance) in ohms, W in kg, sex: male=1 / female=0.
    // Foot-to-foot consumer scales report a single impedance magnitude Z, not R and X.
    // At ~50 kHz, Z is approximately R (reactance is small), so Z is treated as R and X is
    // estimated from a nominal 6-degree phase angle (X = R*tan(6)). Approximation.
    static func ffmKyle(weightKg w: Double, heightCm h: Double, impedanceZ z: Double, sex: Sex) -> Double {
        let r = z
        let x = r * tan(6.0 * .pi / 180.0)
        let index = (h * h) / r
        return -4.104 + 0.518 * index + 0.231 * w + 0.130 * x + 4.229 * Double(sex.rawValue)
    }

    // Deurenberg et al. (1991) BMI-based body-fat %, used only when no impedance is read.
    // BF% = 1.20*BMI + 0.23*age - 10.8*sex - 5.4   (sex: male=1 / female=0)
    static func bodyFatDeurenberg(bmi: Double, age: Int, sex: Sex) -> Double {
        1.20 * bmi + 0.23 * Double(age) - 10.8 * Double(sex.rawValue) - 5.4
    }

    // Mifflin-St Jeor resting metabolic rate (kcal/day).
    static func bmr(weightKg w: Double, heightCm h: Double, age: Int, sex: Sex) -> Double {
        let base = 10 * w + 6.25 * h - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    static func compute(weightKg w: Double, profile p: BodyProfile, impedanceZ z: Double?) -> BodyComposition {
        let hM = p.heightCm / 100.0
        let bmi = hM > 0 ? w / (hM * hM) : 0

        let ffm: Double
        let used: Bool
        if let z, z > 50, z < 1500 {
            ffm = max(1, ffmKyle(weightKg: w, heightCm: p.heightCm, impedanceZ: z, sex: p.sex))
            used = true
        } else {
            let bf = min(60, max(3, bodyFatDeurenberg(bmi: bmi, age: p.age, sex: p.sex)))
            ffm = w * (1 - bf / 100.0)
            used = false
        }

        let fatMass = max(0, w - ffm)
        let bf = w > 0 ? fatMass / w * 100 : 0
        let tbw = 0.73 * ffm                 // standard ~73% hydration of FFM
        let bone = 0.0407 * ffm              // rough proportion; real value is vendor-specific
        let muscle = max(0, ffm - bone)

        return BodyComposition(
            weightKg: w,
            bmi: bmi,
            bodyFatPct: bf,
            fatMassKg: fatMass,
            fatFreeMassKg: ffm,
            muscleMassKg: muscle,
            boneMassKg: bone,
            tbwKg: tbw,
            waterPct: w > 0 ? tbw / w * 100 : 0,
            bmr: bmr(weightKg: w, heightCm: p.heightCm, age: p.age, sex: p.sex),
            usedImpedance: used
        )
    }
}
