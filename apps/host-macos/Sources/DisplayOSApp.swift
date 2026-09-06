import SwiftUI
import Network

@main
struct DisplayOSApp: App {
    @StateObject private var discovery = ReceiverDiscovery()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(discovery)
                .frame(minWidth: 720, minHeight: 500)
        }
    }
}

struct Receiver: Identifiable, Equatable, Sendable {
    let name: String
    let endpoint: String
    let version: String
    let resolution: String
    let transport: String
    let serviceType: String
    let serviceDomain: String?

    var id: String { "\(name)|\(serviceType)|\(serviceDomain ?? "")" }
}

@MainActor
final class ReceiverDiscovery: ObservableObject {
    @Published var receivers: [Receiver] = []
    @Published var status = "Searching for DisplayOS receivers…"
    private var browser: NWBrowser?
    private var candidates: [String: Receiver] = [:]
    private var probes: [String: NWConnection] = [:]

    init() { start() }

    func start() {
        browser?.cancel()
        browser = nil
        probes.values.forEach { $0.cancel() }
        probes = [:]
        candidates = [:]
        receivers = []
        status = "Searching for DisplayOS receivers…"

        let params = NWParameters.tcp
        let browser = NWBrowser(for: .bonjour(type: "_displayos._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Receiver? in
                guard case let .service(name: name, type: type, domain: domain, interface: interface) = result.endpoint else { return nil }
                let address = "\(name).\(domain) · TCP 9877"
                return Receiver(name: name, endpoint: address, version: "0.1.0", resolution: "2560 × 1440 @ 60 Hz", transport: interface?.name ?? "Network", serviceType: type, serviceDomain: domain)
            }.sorted { $0.name < $1.name }
            Task { @MainActor [weak self] in
                guard self?.browser === browser else { return }
                self?.checkReachability(of: found)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            guard case .failed(let error) = state else { return }
            let message = "Discovery unavailable: \(error.localizedDescription)"
            Task { @MainActor [weak self] in
                guard self?.browser === browser else { return }
                self?.status = message
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func checkReachability(of found: [Receiver]) {
        let nextCandidates = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        let removedProbeIDs = probes.keys.filter { nextCandidates[$0] == nil }
        for id in removedProbeIDs {
            probes[id]?.cancel()
            probes[id] = nil
        }
        candidates = nextCandidates
        receivers.removeAll { nextCandidates[$0.id] == nil }

        for receiver in found where probes[receiver.id] == nil && !receivers.contains(receiver) {
            probe(receiver)
        }
        updateStatus()
    }

    private func probe(_ receiver: Receiver) {
        let endpoint = NWEndpoint.service(name: receiver.name, type: receiver.serviceType, domain: receiver.serviceDomain ?? "local.", interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)
        let id = receiver.id
        probes[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                connection?.cancel()
                Task { @MainActor [weak self] in self?.finishProbe(id: id, receiver: receiver, reachable: true) }
            case .failed:
                Task { @MainActor [weak self] in self?.finishProbe(id: id, receiver: receiver, reachable: false) }
            default:
                break
            }
        }
        connection.start(queue: .main)
        Task { @MainActor [weak self, weak connection] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, let connection, self.probes[id] === connection else { return }
            connection.cancel()
            self.finishProbe(id: id, receiver: receiver, reachable: false)
        }
    }

    private func finishProbe(id: String, receiver: Receiver, reachable: Bool) {
        guard probes[id] != nil else { return }
        probes[id] = nil
        if reachable, candidates[id] != nil, !receivers.contains(receiver) {
            receivers.append(receiver)
            receivers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        updateStatus()
    }

    private func updateStatus() {
        if candidates.isEmpty {
            status = "No receivers found. Check the cable and receiver boot screen."
        } else if !probes.isEmpty {
            status = "Checking \(candidates.count) discovered receiver\(candidates.count == 1 ? "" : "s")…"
        } else if receivers.isEmpty {
            status = "No reachable receivers found."
        } else {
            status = "\(receivers.count) reachable receiver\(receivers.count == 1 ? "" : "s")"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var discovery: ReceiverDiscovery
    @State private var selectedTab = 0
    @State private var connected: Receiver?
    @StateObject private var streaming = StreamingManager()
    @State private var showingRemoveConfirmation = false

    var body: some View {
        TabView(selection: $selectedTab) {
            receiversView.tabItem { Label("Displays", systemImage: "display") }.tag(0)
            ImagerView().tabItem { Label("Create bootable USB", systemImage: "externaldrive") }.tag(1)
        }
        .padding(20)
    }

    private var receiversView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("DisplayOS").font(.largeTitle.weight(.bold))
            HStack {
                Text(discovery.status).foregroundStyle(.secondary)
                Spacer()
                Button {
                    discovery.start()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Search again for available receivers")
            }
            if discovery.receivers.isEmpty {
                ContentUnavailableView("Waiting for a receiver", systemImage: "display.trianglebadge.exclamationmark", description: Text("Boot the iMac from the DisplayOS USB image, then connect it by Ethernet."))
            } else {
                List(discovery.receivers) { receiver in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(receiver.name).font(.headline)
                            Text("\(receiver.transport) · \(receiver.endpoint)").foregroundStyle(.secondary)
                            Text("\(receiver.resolution) · v\(receiver.version)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if connected?.id == receiver.id {
                            Button("Remove display", role: .destructive) { showingRemoveConfirmation = true }
                        } else {
                            Button("Connect") {
                                connected = receiver
                                streaming.start(receiver: receiver)
                            }
                        }
                    }.padding(.vertical, 5)
                }.listStyle(.inset)
            }
            GroupBox("Streaming status") {
                HStack { Image(systemName: streaming.isStreaming ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(streaming.isStreaming ? Color.green : Color.secondary)
                    Text(streaming.status) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
        }
        .alert("Remove streaming display?", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                streaming.removeDisplay()
                connected = nil
            }
        } message: {
            Text("This stops streaming and removes the virtual display from macOS Displays.")
        }
    }
}
