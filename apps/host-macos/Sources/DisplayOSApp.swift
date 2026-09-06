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

struct Receiver: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let endpoint: String
    let version: String
    let resolution: String
    let transport: String
    let serviceType: String
    let serviceDomain: String?
}

@MainActor
final class ReceiverDiscovery: ObservableObject {
    @Published var receivers: [Receiver] = []
    @Published var status = "Searching for DisplayOS receivers…"
    private var browser: NWBrowser?

    init() { start() }

    func start() {
        let params = NWParameters.tcp
        let browser = NWBrowser(for: .bonjour(type: "_displayos._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Receiver? in
                guard case let .service(name: name, type: type, domain: domain, interface: interface) = result.endpoint else { return nil }
                return Receiver(name: name, endpoint: interface?.name ?? "Network", version: "0.1.0", resolution: "2560 × 1440 @ 60 Hz", transport: "Ethernet / LAN", serviceType: type, serviceDomain: domain)
            }.sorted { $0.name < $1.name }
            Task { @MainActor in
                self?.receivers = found
                self?.status = found.isEmpty ? "No receivers found. Check the cable and receiver boot screen." : "(found.count) receiver\(found.count == 1 ? "" : "s") available"
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { Task { @MainActor in self?.status = "Discovery unavailable: \(error.localizedDescription)" } }
        }
        browser.start(queue: .main)
        self.browser = browser
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
            Text(discovery.status).foregroundStyle(.secondary)
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
