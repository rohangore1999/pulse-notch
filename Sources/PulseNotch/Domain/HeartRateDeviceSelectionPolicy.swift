import Foundation

struct ApprovedHeartRateDeviceRecord: Equatable {
    let identifier: UUID
    let name: String
}

enum HeartRateDeviceSelectionPolicy {
    static let unknownRSSI = 127
    static let pickerScanDuration: TimeInterval = 15

    static func displayName(
        identifier: UUID,
        peripheralName: String?,
        advertisementLocalName: String?,
        approvedDeviceID: UUID?,
        approvedDeviceName: String?
    ) -> String {
        if let name = normalizedName(peripheralName) {
            return name
        }
        if let name = normalizedName(advertisementLocalName) {
            return name
        }
        if identifier == approvedDeviceID,
           let name = normalizedName(approvedDeviceName) {
            return name
        }

        let compactIdentifier = identifier.uuidString
            .replacingOccurrences(of: "-", with: "")
        return "Heart-rate monitor · \(compactIdentifier.suffix(4))"
    }

    static func precedes(
        lhsID: UUID,
        lhsName: String,
        lhsRSSI: Int,
        rhsID: UUID,
        rhsName: String,
        rhsRSSI: Int
    ) -> Bool {
        let lhsKnown = lhsRSSI != unknownRSSI
        let rhsKnown = rhsRSSI != unknownRSSI
        if lhsKnown != rhsKnown {
            return lhsKnown
        }
        if lhsRSSI != rhsRSSI {
            return lhsRSSI > rhsRSSI
        }

        let nameOrder = lhsName.localizedCaseInsensitiveCompare(rhsName)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhsID.uuidString < rhsID.uuidString
    }

    static func shouldAutomaticallyReconnect(
        candidateID: UUID,
        approvedDeviceID: UUID?,
        isExplicitPickerScan: Bool
    ) -> Bool {
        !isExplicitPickerScan && candidateID == approvedDeviceID
    }

    static func isValidLiveSample(bpm: Int) -> Bool {
        (20...260).contains(bpm)
    }

    static func restoredApprovedDevice(
        identifierString: String?,
        name: String?
    ) -> ApprovedHeartRateDeviceRecord? {
        guard let identifierString,
              let identifier = UUID(uuidString: identifierString),
              let name = normalizedName(name) else {
            return nil
        }
        return ApprovedHeartRateDeviceRecord(identifier: identifier, name: name)
    }

    static func shouldRetryApprovedDevice(
        failedDeviceID: UUID,
        approvedDeviceID: UUID?,
        userWantsMonitoring: Bool,
        bluetoothIsPoweredOn: Bool
    ) -> Bool {
        userWantsMonitoring
            && bluetoothIsPoweredOn
            && failedDeviceID == approvedDeviceID
    }

    static func reconnectDelay(attempt: Int) -> TimeInterval {
        min(30, pow(2, Double(max(0, attempt - 1))))
    }

    static func shouldProcessConnectionEnd(
        isCurrentPeripheral: Bool,
        wasCancellation: Bool,
        callbackDeviceID: UUID,
        pendingTerminationDeviceID: UUID?
    ) -> Bool {
        isCurrentPeripheral
            && (!wasCancellation || pendingTerminationDeviceID == callbackDeviceID)
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}
