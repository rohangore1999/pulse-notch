import SwiftUI

extension HeartRateZone {
    var displayColor: Color {
        switch self {
        case .zone0: Color(red: 0.48, green: 0.52, blue: 0.56)
        case .zone1: Color(red: 0.18, green: 0.58, blue: 0.94)
        case .zone2: Color(red: 0.10, green: 0.84, blue: 0.47)
        case .zone3: Color(red: 1.00, green: 0.82, blue: 0.16)
        case .zone4: Color(red: 1.00, green: 0.48, blue: 0.08)
        case .zone5: Color(red: 1.00, green: 0.16, blue: 0.22)
        }
    }
}
