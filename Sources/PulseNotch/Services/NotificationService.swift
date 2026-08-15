import Foundation
import UserNotifications

final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendThresholdAlert(bpm: Int, zone: HeartRateZone, configuration: AlertConfiguration) {
        guard !UserDefaults.standard.bool(forKey: "pulseNotch.presentationPrivacy.v1") else {
            return
        }
        guard UserDefaults.standard.bool(forKey: "pulseNotch.notificationsEnabled.v1") else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Heart-rate reminder"
        switch configuration.mode {
        case .bpm:
            content.body = "Your heart rate has stayed above \(configuration.bpmThreshold) BPM. Consider pausing for a moment."
        case .zone:
            content.body = "Your heart rate has stayed in \(configuration.zoneThreshold.shortName) or higher. Consider pausing for a moment."
        }
        content.subtitle = "Currently \(bpm) BPM · \(zone.shortName)"
        if UserDefaults.standard.object(forKey: "pulseNotch.alertSound.v1") == nil
            || UserDefaults.standard.bool(forKey: "pulseNotch.alertSound.v1") {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "heart-rate-threshold-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
