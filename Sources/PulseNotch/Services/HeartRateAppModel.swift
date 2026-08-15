import AppKit
import Combine
import CoreBluetooth
import Foundation

struct DiscoveredHeartRateDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum BLEConnectionStatus: Equatable {
    case waitingForBluetooth
    case bluetoothOff
    case unauthorized
    case idle
    case scanning
    case connecting(String)
    case discovering(String)
    case subscribing(String)
    case live(String)
    case reconnecting(String, Int)
    case incompatible(String)
    case failed(String)

    var text: String {
        switch self {
        case .waitingForBluetooth: "Checking Bluetooth…"
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorized: "Bluetooth permission required"
        case .idle: "Not connected"
        case .scanning: "Scanning for heart-rate monitors…"
        case let .connecting(name): "Connecting to \(name)…"
        case let .discovering(name): "Discovering \(name)…"
        case let .subscribing(name): "Starting live HR from \(name)…"
        case let .live(name): "Live from \(name)"
        case let .reconnecting(name, attempt): "Reconnecting to \(name) · attempt \(attempt)"
        case let .incompatible(message): message
        case let .failed(message): message
        }
    }

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }
}

private enum BLEConnectionTermination {
    case failed(message: String, retryApprovedDevice: Bool)
    case incompatible(message: String)
}

private struct PendingBLEConnectionTermination {
    let peripheralID: UUID
    let outcome: BLEConnectionTermination
}

final class HeartRateAppModel: NSObject, ObservableObject {
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurementCharacteristic = CBUUID(string: "2A37")

    @Published private(set) var bpm: Int?
    @Published private(set) var samples: [HeartRateSample] = []
    @Published private(set) var expandedChartSamples: [HeartRateSample] = []
    @Published private(set) var devices: [DiscoveredHeartRateDevice] = []
    @Published private(set) var approvedDeviceID: UUID?
    @Published private(set) var approvedDeviceName: String?
    @Published private(set) var connectedDeviceID: UUID?
    @Published private(set) var connectingDeviceID: UUID?
    @Published private(set) var isScanningForDevices = false
    @Published private(set) var connectionStatus: BLEConnectionStatus = .waitingForBluetooth {
        didSet {
            if connectionStatus != oldValue {
                updateFocusState(at: Date())
            }
        }
    }
    @Published private(set) var isStale = true
    @Published private(set) var focusState: FocusDotSemanticState = .disconnected
    @Published private(set) var sensorContactDetected: Bool?
    @Published var isExpanded = false

    let settings: SettingsStore

    private var centralManager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var advertisementLocalNames: [UUID: String] = [:]
    private var appOwnedPeripheralIDs: Set<UUID> = []
    private var cancellingPeripheralIDs: Set<UUID> = []
    private var selectedPeripheral: CBPeripheral?
    private var measurementCharacteristic: CBCharacteristic?
    private var autoReconnectApprovedDeviceID: UUID?
    private var connectionGeneration: UInt = 0
    private var desiredRunning = true
    private var connectWatchdog: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?
    private var scanStopWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var pendingTermination: PendingBLEConnectionTermination?
    private var freshnessTimer: Timer?
    private var lastSampleDate: Date?
    private var expandedHistoryDeviceID: UUID?
    private var staleReconnectRequested = false
    private var thresholdEngine = ThresholdEngine()
    private let notifications = NotificationService()
    private var cancellables: Set<AnyCancellable> = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = SettingsStore(defaults: defaults)
        super.init()

        if let approvedDevice = HeartRateDeviceSelectionPolicy.restoredApprovedDevice(
            identifierString: defaults.string(forKey: Keys.approvedPeripheralID),
            name: defaults.string(forKey: Keys.approvedPeripheralName)
        ) {
            approvedDeviceID = approvedDevice.identifier
            approvedDeviceName = approvedDevice.name
        }

        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.$alerts
            .dropFirst()
            .sink { [weak self] _ in
                self?.thresholdEngine.markDataStale()
                self?.updateFocusState(at: Date())
            }
            .store(in: &cancellables)

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )

        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshFreshness()
        }
    }

    var currentZone: HeartRateZone? {
        guard let bpm, settings.zones.isValid else { return nil }
        return settings.zones.zone(for: bpm)
    }

    /// The last reading remains available while stale, but is removed after disconnect.
    var focusBPM: Int? {
        if case .disconnected = focusState { return nil }
        return bpm
    }

    var lastReadingDescription: String {
        guard let lastSampleDate else { return "Waiting for first reading" }
        let age = max(0, Int(Date().timeIntervalSince(lastSampleDate)))
        return age < 2 ? "Updated now" : "Updated \(age)s ago"
    }

    func startScanning() {
        desiredRunning = true
        autoReconnectApprovedDeviceID = nil
        reconnectAttempt = 0
        pendingTermination = nil
        cancelConnectionTasks()
        let keepsLiveConnection = connectionStatus.isLive
            && selectedPeripheral?.state == .connected
        if !keepsLiveConnection {
            clearActiveConnection(cancelOwnedConnection: true)
        }
        beginPickerScan()
    }

    func connect(to identifier: UUID) {
        guard centralManager.state == .poweredOn,
              !cancellingPeripheralIDs.contains(identifier),
              let peripheral = peripherals[identifier] else { return }
        reconnectAttempt = 0
        pendingTermination = nil
        beginConnection(to: peripheral)
    }

    func disconnect() {
        desiredRunning = false
        autoReconnectApprovedDeviceID = nil
        reconnectAttempt = 0
        pendingTermination = nil
        cancelConnectionTasks()
        stopScanning()
        clearExpandedChartHistory()
        clearActiveConnection(cancelOwnedConnection: true)
        connectionStatus = .idle
    }

    func forgetApprovedDevice() {
        defaults.removeObject(forKey: Keys.approvedPeripheralID)
        defaults.removeObject(forKey: Keys.approvedPeripheralName)
        approvedDeviceID = nil
        approvedDeviceName = nil
        desiredRunning = true
        autoReconnectApprovedDeviceID = nil
        reconnectAttempt = 0
        pendingTermination = nil
        cancelConnectionTasks()
        stopScanning()
        clearExpandedChartHistory()
        clearActiveConnection(cancelOwnedConnection: true)
        beginPickerScan()
    }

    func handleWake() {
        guard desiredRunning else { return }
        if selectedPeripheral?.state != .connected || connectedDeviceID == nil {
            reconnectApprovedPeripheralOrStartPicker()
        }
    }

    func shutdown() {
        freshnessTimer?.invalidate()
        disconnect()
    }

    func resetElevation() {
        thresholdEngine.resetElevation()
        updateFocusState(at: Date())
    }

    func snoozeAlerts(for duration: TimeInterval = 15 * 60) {
        let now = Date()
        thresholdEngine.snooze(for: duration, at: now)
        updateFocusState(at: now)
    }

    func resumeAlerts() {
        thresholdEngine.resumeAlerts()
        updateFocusState(at: Date())
    }

    private func ingest(bpm: Int, at date: Date, contact: Bool?, deviceID: UUID) {
        guard (20...260).contains(bpm), settings.zones.isValid else { return }
        let zone = settings.zones.zone(for: bpm)
        let sample = HeartRateSample(timestamp: date, bpm: bpm, zone: zone)

        if expandedHistoryDeviceID != deviceID {
            expandedChartSamples.removeAll(keepingCapacity: true)
            expandedHistoryDeviceID = deviceID
        }

        self.bpm = bpm
        sensorContactDetected = contact
        lastSampleDate = date
        // An explicit no-contact reading may be shown as stale context, but must
        // never advance elevation dwell or trigger an alert.
        isStale = contact == false
        staleReconnectRequested = false
        samples.append(sample)
        let cutoff = date.addingTimeInterval(-HeartRateChartPolicy.compactRetention)
        samples.removeAll { $0.timestamp < cutoff }
        expandedChartSamples = HeartRateChartPolicy.retainedSamples(
            expandedChartSamples,
            appending: sample,
            duration: HeartRateChartPolicy.expandedWindow,
            maximumCount: HeartRateChartPolicy.expandedMaximumSampleCount
        )

        let shouldNotify = thresholdEngine.ingest(
            bpm: bpm,
            zone: zone,
            sensorContactDetected: contact,
            at: date,
            configuration: settings.alerts
        )
        updateFocusState(at: date)

        if shouldNotify {
            notifications.sendThresholdAlert(
                bpm: bpm,
                zone: zone,
                configuration: settings.alerts
            )
        }
    }

    private func refreshFreshness() {
        let now = Date()
        guard let lastSampleDate else {
            updateFocusState(at: now)
            return
        }
        let age = now.timeIntervalSince(lastSampleDate)
        if age > 5 {
            markStale()
        } else {
            updateFocusState(at: now)
        }
        if age > 20, !staleReconnectRequested, desiredRunning,
           let peripheral = selectedPeripheral {
            staleReconnectRequested = true
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    private func markStale() {
        isStale = true
        thresholdEngine.markDataStale()
        updateFocusState(at: Date())
    }

    private func markDisconnected() {
        bpm = nil
        samples.removeAll()
        lastSampleDate = nil
        sensorContactDetected = nil
        isStale = true
        staleReconnectRequested = false
        thresholdEngine.markDataStale()
        if focusState != .disconnected {
            focusState = .disconnected
        }
    }

    private func clearExpandedChartHistory() {
        expandedChartSamples.removeAll(keepingCapacity: true)
        expandedHistoryDeviceID = nil
    }

    private func updateFocusState(at date: Date) {
        let nextState: FocusDotSemanticState
        if !connectionStatus.isLive {
            nextState = .disconnected
        } else if isStale {
            nextState = .stale
        } else {
            nextState = thresholdEngine.semanticState(at: date, configuration: settings.alerts)
        }

        if focusState != nextState {
            focusState = nextState
        }
    }

    private func reconnectApprovedPeripheralOrStartPicker() {
        guard centralManager.state == .poweredOn else {
            isScanningForDevices = false
            connectionStatus = status(for: centralManager.state)
            return
        }

        cancelConnectionTasks()
        clearActiveConnection(cancelOwnedConnection: true)
        mergeConnectedPeripherals()

        guard let identifier = approvedDeviceID else {
            beginPickerScan()
            return
        }

        let peripheral = peripherals[identifier]
            ?? centralManager.retrievePeripherals(withIdentifiers: [identifier]).first

        if let peripheral {
            mergeCandidate(peripheral, advertisementLocalName: nil, rssi: nil)
            beginConnection(to: peripheral)
        } else {
            beginPickerScan(autoReconnect: identifier)
        }
    }

    private func beginConnection(to peripheral: CBPeripheral) {
        if isCurrent(peripheral),
           connectingDeviceID == peripheral.identifier || connectedDeviceID == peripheral.identifier {
            return
        }

        desiredRunning = true
        autoReconnectApprovedDeviceID = nil
        cancelConnectionTasks()
        stopScanning()
        clearActiveConnection(cancelOwnedConnection: true)
        pendingTermination = nil

        connectionGeneration &+= 1
        let generation = connectionGeneration
        selectedPeripheral = peripheral
        connectingDeviceID = peripheral.identifier
        connectedDeviceID = nil
        measurementCharacteristic = nil
        peripheral.delegate = self
        appOwnedPeripheralIDs.insert(peripheral.identifier)
        connectionStatus = .connecting(displayName(for: peripheral))
        centralManager.connect(peripheral)
        armConnectWatchdog(for: peripheral, generation: generation)
    }

    private func beginPickerScan(autoReconnect identifier: UUID? = nil) {
        guard centralManager.state == .poweredOn else {
            autoReconnectApprovedDeviceID = nil
            isScanningForDevices = false
            connectionStatus = status(for: centralManager.state)
            return
        }

        stopScanning()
        mergeConnectedPeripherals()
        autoReconnectApprovedDeviceID = identifier
        if !connectionStatus.isLive {
            connectionStatus = .scanning
        }
        centralManager.scanForPeripherals(
            withServices: [Self.heartRateService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanningForDevices = true
        armScanTimeout(autoReconnect: identifier)
    }

    private func stopScanning() {
        scanStopWorkItem?.cancel()
        scanStopWorkItem = nil
        centralManager.stopScan()
        isScanningForDevices = false
    }

    private func armScanTimeout(autoReconnect identifier: UUID?) {
        scanStopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isScanningForDevices else { return }

            self.centralManager.stopScan()
            self.isScanningForDevices = false
            self.scanStopWorkItem = nil
            let reconnectIdentifier = self.autoReconnectApprovedDeviceID
            self.autoReconnectApprovedDeviceID = nil

            if let identifier,
               reconnectIdentifier == identifier,
               self.approvedDeviceID == identifier,
               self.desiredRunning {
                let name = self.approvedDeviceName ?? "approved heart-rate device"
                self.scheduleApprovedReconnect(identifier: identifier, name: name)
            } else if !self.connectionStatus.isLive, self.selectedPeripheral == nil {
                self.connectionStatus = .idle
            }
        }
        scanStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + HeartRateDeviceSelectionPolicy.pickerScanDuration,
            execute: workItem
        )
    }

    private func mergeConnectedPeripherals() {
        guard centralManager.state == .poweredOn else { return }
        for peripheral in centralManager.retrieveConnectedPeripherals(
            withServices: [Self.heartRateService]
        ) {
            mergeCandidate(peripheral, advertisementLocalName: nil, rssi: nil)
        }
    }

    private func mergeCandidate(
        _ peripheral: CBPeripheral,
        advertisementLocalName: String?,
        rssi: Int?
    ) {
        let identifier = peripheral.identifier
        peripherals[identifier] = peripheral

        if let advertisementLocalName = advertisementLocalName?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            advertisementLocalNames[identifier] = advertisementLocalName
        }

        let previousRSSI = devices.first(where: { $0.id == identifier })?.rssi
        let usableRSSI = rssi == 127 ? nil : rssi
        let candidate = DiscoveredHeartRateDevice(
            id: identifier,
            name: displayName(for: peripheral),
            rssi: usableRSSI ?? previousRSSI ?? HeartRateDeviceSelectionPolicy.unknownRSSI
        )

        if let index = devices.firstIndex(where: { $0.id == identifier }) {
            devices[index] = candidate
        } else {
            devices.append(candidate)
        }

        devices.sort { lhs, rhs in
            HeartRateDeviceSelectionPolicy.precedes(
                lhsID: lhs.id,
                lhsName: lhs.name,
                lhsRSSI: lhs.rssi,
                rhsID: rhs.id,
                rhsName: rhs.name,
                rhsRSSI: rhs.rssi
            )
        }
    }

    private func armConnectWatchdog(for peripheral: CBPeripheral, generation: UInt) {
        connectWatchdog?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.connectionGeneration == generation,
                  self.isCurrent(peripheral),
                  self.connectingDeviceID == peripheral.identifier else { return }
            self.requestTermination(
                .failed(
                    message: "No live heart-rate reading arrived from \(self.displayName(for: peripheral)).",
                    retryApprovedDevice: true
                ),
                for: peripheral
            )
        }
        connectWatchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    private func cancelConnectionTasks() {
        connectWatchdog?.cancel()
        reconnectWorkItem?.cancel()
        connectWatchdog = nil
        reconnectWorkItem = nil
    }

    private func clearActiveConnection(cancelOwnedConnection: Bool) {
        connectionGeneration &+= 1
        connectWatchdog?.cancel()
        connectWatchdog = nil

        let peripheral = selectedPeripheral
        selectedPeripheral = nil
        measurementCharacteristic = nil
        connectingDeviceID = nil
        connectedDeviceID = nil
        pendingTermination = nil

        if let peripheral {
            peripheral.delegate = nil
            if cancelOwnedConnection,
               appOwnedPeripheralIDs.contains(peripheral.identifier),
               peripheral.state != .disconnected {
                cancellingPeripheralIDs.insert(peripheral.identifier)
                centralManager.cancelPeripheralConnection(peripheral)
            }
            appOwnedPeripheralIDs.remove(peripheral.identifier)
        }

        markDisconnected()
    }

    private func requestTermination(
        _ outcome: BLEConnectionTermination,
        for peripheral: CBPeripheral
    ) {
        guard isCurrent(peripheral) else { return }
        connectWatchdog?.cancel()
        connectWatchdog = nil
        pendingTermination = PendingBLEConnectionTermination(
            peripheralID: peripheral.identifier,
            outcome: outcome
        )

        switch outcome {
        case let .failed(message, _):
            connectionStatus = .failed(message)
        case let .incompatible(message):
            connectionStatus = .incompatible(message)
        }

        if peripheral.state == .disconnected {
            finishConnectionEnd(for: peripheral, fallbackMessage: connectionStatus.text)
        } else {
            cancellingPeripheralIDs.insert(peripheral.identifier)
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    private func finishConnectionEnd(
        for peripheral: CBPeripheral,
        fallbackMessage: String
    ) {
        guard isCurrent(peripheral) else { return }
        let identifier = peripheral.identifier
        let name = displayName(for: peripheral)
        let outcome = pendingTermination?.peripheralID == identifier
            ? pendingTermination?.outcome
            : .failed(message: fallbackMessage, retryApprovedDevice: true)

        clearActiveConnection(cancelOwnedConnection: false)

        switch outcome {
        case let .incompatible(message):
            connectionStatus = .incompatible(message)
        case let .failed(message, retryApprovedDevice):
            if retryApprovedDevice,
               HeartRateDeviceSelectionPolicy.shouldRetryApprovedDevice(
                   failedDeviceID: identifier,
                   approvedDeviceID: approvedDeviceID,
                   userWantsMonitoring: desiredRunning,
                   bluetoothIsPoweredOn: centralManager.state == .poweredOn
               ) {
                scheduleApprovedReconnect(identifier: identifier, name: name)
            } else {
                connectionStatus = .failed(message)
            }
        case nil:
            connectionStatus = .failed(fallbackMessage)
        }
    }

    private func scheduleApprovedReconnect(identifier: UUID, name: String) {
        guard HeartRateDeviceSelectionPolicy.shouldRetryApprovedDevice(
            failedDeviceID: identifier,
            approvedDeviceID: approvedDeviceID,
            userWantsMonitoring: desiredRunning,
            bluetoothIsPoweredOn: centralManager.state == .poweredOn
        ) else {
            connectionStatus = desiredRunning ? status(for: centralManager.state) : .idle
            return
        }

        reconnectWorkItem?.cancel()
        reconnectAttempt += 1
        connectionStatus = .reconnecting(name, reconnectAttempt)
        let generation = connectionGeneration
        let delay = HeartRateDeviceSelectionPolicy.reconnectDelay(attempt: reconnectAttempt)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.desiredRunning,
                  self.connectionGeneration == generation,
                  self.selectedPeripheral == nil,
                  self.approvedDeviceID == identifier else { return }

            let peripheral = self.peripherals[identifier]
                ?? self.centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
            if let peripheral {
                self.mergeCandidate(peripheral, advertisementLocalName: nil, rssi: nil)
                self.beginConnection(to: peripheral)
            } else {
                self.beginPickerScan(autoReconnect: identifier)
            }
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func approve(_ peripheral: CBPeripheral) {
        let identifier = peripheral.identifier
        let name = displayName(for: peripheral)
        if approvedDeviceID != identifier || approvedDeviceName != name {
            defaults.set(identifier.uuidString, forKey: Keys.approvedPeripheralID)
            defaults.set(name, forKey: Keys.approvedPeripheralName)
        }
        approvedDeviceID = identifier
        approvedDeviceName = name
        mergeCandidate(peripheral, advertisementLocalName: nil, rssi: nil)
    }

    private func isCurrent(_ peripheral: CBPeripheral) -> Bool {
        guard let selectedPeripheral else { return false }
        return selectedPeripheral === peripheral
            && selectedPeripheral.identifier == peripheral.identifier
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        HeartRateDeviceSelectionPolicy.displayName(
            identifier: peripheral.identifier,
            peripheralName: peripheral.name,
            advertisementLocalName: advertisementLocalNames[peripheral.identifier],
            approvedDeviceID: approvedDeviceID,
            approvedDeviceName: approvedDeviceName
        )
    }

    private func status(for state: CBManagerState) -> BLEConnectionStatus {
        switch state {
        case .poweredOn: .idle
        case .poweredOff: .bluetoothOff
        case .unauthorized: .unauthorized
        case .unsupported: .failed("Bluetooth LE is not supported")
        case .resetting, .unknown: .waitingForBluetooth
        @unknown default: .waitingForBluetooth
        }
    }

    private enum Keys {
        static let approvedPeripheralID = "approvedPeripheralID.v2"
        static let approvedPeripheralName = "approvedPeripheralName.v2"
    }
}

extension HeartRateAppModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            autoReconnectApprovedDeviceID = nil
            reconnectAttempt = 0
            pendingTermination = nil
            cancelConnectionTasks()
            stopScanning()
            clearActiveConnection(cancelOwnedConnection: false)
            connectionStatus = status(for: central.state)
            return
        }

        guard desiredRunning else {
            connectionStatus = .idle
            return
        }
        reconnectApprovedPeripheralOrStartPicker()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        mergeCandidate(
            peripheral,
            advertisementLocalName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue
        )

        if HeartRateDeviceSelectionPolicy.shouldAutomaticallyReconnect(
            candidateID: peripheral.identifier,
            approvedDeviceID: autoReconnectApprovedDeviceID,
            isExplicitPickerScan: autoReconnectApprovedDeviceID == nil
        ),
           selectedPeripheral == nil {
            beginConnection(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isCurrent(peripheral) else {
            peripheral.delegate = nil
            cancellingPeripheralIDs.insert(peripheral.identifier)
            central.cancelPeripheralConnection(peripheral)
            appOwnedPeripheralIDs.remove(peripheral.identifier)
            return
        }
        connectedDeviceID = peripheral.identifier
        connectionStatus = .discovering(displayName(for: peripheral))
        peripheral.delegate = self
        peripheral.discoverServices([Self.heartRateService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        appOwnedPeripheralIDs.remove(peripheral.identifier)
        let wasCancellation = cancellingPeripheralIDs.remove(peripheral.identifier) != nil
        guard HeartRateDeviceSelectionPolicy.shouldProcessConnectionEnd(
            isCurrentPeripheral: isCurrent(peripheral),
            wasCancellation: wasCancellation,
            callbackDeviceID: peripheral.identifier,
            pendingTerminationDeviceID: pendingTermination?.peripheralID
        ) else { return }
        finishConnectionEnd(
            for: peripheral,
            fallbackMessage: "Could not connect to \(displayName(for: peripheral))."
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        appOwnedPeripheralIDs.remove(peripheral.identifier)
        let wasCancellation = cancellingPeripheralIDs.remove(peripheral.identifier) != nil
        guard HeartRateDeviceSelectionPolicy.shouldProcessConnectionEnd(
            isCurrentPeripheral: isCurrent(peripheral),
            wasCancellation: wasCancellation,
            callbackDeviceID: peripheral.identifier,
            pendingTerminationDeviceID: pendingTermination?.peripheralID
        ) else { return }
        finishConnectionEnd(
            for: peripheral,
            fallbackMessage: "The live heart-rate connection to \(displayName(for: peripheral)) ended."
        )
    }
}

extension HeartRateAppModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isCurrent(peripheral) else { return }
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.heartRateService }) else {
            requestTermination(
                .incompatible(message: "This device does not provide the Bluetooth Heart Rate Service."),
                for: peripheral
            )
            return
        }
        connectionStatus = .subscribing(displayName(for: peripheral))
        peripheral.discoverCharacteristics([Self.heartRateMeasurementCharacteristic], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard isCurrent(peripheral) else { return }
        guard error == nil,
              let characteristic = service.characteristics?.first(where: {
                  $0.uuid == Self.heartRateMeasurementCharacteristic
              }),
              characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            requestTermination(
                .incompatible(message: "This device does not provide a compatible live heart-rate stream."),
                for: peripheral
            )
            return
        }
        measurementCharacteristic = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard isCurrent(peripheral),
              let measurementCharacteristic,
              measurementCharacteristic === characteristic else { return }
        guard error == nil, characteristic.isNotifying else {
            requestTermination(
                .failed(
                    message: "Pulse Notch could not subscribe to this device’s live heart rate.",
                    retryApprovedDevice: true
                ),
                for: peripheral
            )
            return
        }
        connectionStatus = .subscribing(displayName(for: peripheral))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard isCurrent(peripheral),
              let measurementCharacteristic,
              measurementCharacteristic === characteristic,
              error == nil,
              let data = characteristic.value,
              let measurement = try? HeartRateMeasurementParser.parse(data),
              HeartRateDeviceSelectionPolicy.isValidLiveSample(bpm: measurement.bpm) else { return }
        connectWatchdog?.cancel()
        connectWatchdog = nil
        reconnectAttempt = 0
        connectingDeviceID = nil
        connectedDeviceID = peripheral.identifier
        approve(peripheral)
        connectionStatus = .live(displayName(for: peripheral))
        ingest(
            bpm: measurement.bpm,
            at: Date(),
            contact: measurement.sensorContactDetected,
            deviceID: peripheral.identifier
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard isCurrent(peripheral),
              invalidatedServices.contains(where: { $0.uuid == Self.heartRateService }) else { return }
        measurementCharacteristic = nil
        connectingDeviceID = peripheral.identifier
        connectionStatus = .discovering(displayName(for: peripheral))
        connectionGeneration &+= 1
        armConnectWatchdog(for: peripheral, generation: connectionGeneration)
        peripheral.discoverServices([Self.heartRateService])
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
