import SwiftUI
import CoreData

import SwiftUI
import CoreData

struct BusStopScheduleListView: View {
    // MARK: - Properties
    let selectedBusStop: BusStop
    @StateObject private var viewModel: BusStopScheduleViewModel
    @Environment(\.dismiss) private var dismiss
    
    // UI State
    @AppStorage("showEstimatedTime") private var showEstimatedTime = true
    @AppStorage("showDate") private var showDate = true
    @State private var selectedBus: ScheduledStop?
    
    // MARK: - Initialization
    init(selectedBusStop: BusStop) {
        self.selectedBusStop = selectedBusStop
        self._viewModel = StateObject(wrappedValue: BusStopScheduleViewModel(stopId: selectedBusStop.number))
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Content
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.scheduledStops.isEmpty {
                        emptyStateView
                    } else {
                        stopInfoCard
                        arrivalsList
                    }
                }
                .padding()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .navigationBarHidden(true)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("Retry", action: { Task { await viewModel.refresh() } })
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.error ?? "Unknown error")
        }
        .task {
            await viewModel.refresh()
        }
    }
    
    // MARK: - Subviews
    private var headerView: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedBusStop.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("\(selectedBusStop.direction) - Stop #\(selectedBusStop.number)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        )
    }
    
    private var stopInfoCard: some View {
        VStack(spacing: 16) {
            // Features Row
            FeatureIconsView(features: viewModel.stopFeatures)
            
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private var arrivalsList: some View {
        ForEach(viewModel.scheduledStops) { stop in
            ArrivalCard(
                stop: stop,
                showEstimatedTime: showEstimatedTime,
                showDate: showDate,
                onReminderTap: {
                    viewModel.setReminder(for: stop)
                }
            )
            .onTapGesture {
                selectedBus = stop
            }
        }
    }
    
    private var loadingView: some View {
        LoadingView()
    }
    
    private var emptyStateView: some View {
        EmptyStateView(onRefresh: {
            Task {
                await viewModel.refresh()
            }
        })
    }
}



struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading schedules...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

struct EmptyStateView: View {
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bus.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No scheduled buses")
                .font(.headline)
            
            Text("Pull to refresh or check back later")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}


// MARK: - ViewModel
class BusStopScheduleViewModel: ObservableObject {
    @Published private(set) var scheduledStops: [ScheduledStop] = []
    @Published private(set) var stopFeatures: [BusStopFeature] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var showError = false

    private let stopId: Int
    private let scheduledStopProvider: ScheduledStopProvider
    private let featuresProvider: BusStopFeatures

    init(stopId: Int) {
        self.stopId = stopId
        self.scheduledStopProvider = ScheduledStopProvider(stopId: stopId)
        self.featuresProvider = BusStopFeatures(stopId: stopId)
    }

    func setReminder(for stop: ScheduledStop) {
        // Implement reminder functionality
        NotificationManager.shared.scheduleNotification(for: stop)
    }

    @MainActor
    func refresh() async {
        isLoading = true
        error = nil
        
        do {
            scheduledStops = try await scheduledStopProvider.fetchScheduledStops()
            stopFeatures = try await featuresProvider.fetchBusStopFeatures(stopId: stopId)
        } catch {
            self.error = error.localizedDescription
            self.showError = true
        }
        
        isLoading = false
    }
}

// MARK: - Model Extensions
extension ScheduledStopProvider {
    func fetchScheduledStops() async throws -> [ScheduledStop] {
        return await withCheckedContinuation { continuation in
            self.fetchScheduledStops()
            continuation.resume(returning: self.scheduledStops)
        }
    }
}

extension BusStopFeatures {
    func fetchBusStopFeatures(stopId: Int) async throws -> [BusStopFeature] {
        return await withCheckedContinuation { continuation in
            self.fetchBusStopFeatures(stopId: stopId)
            continuation.resume(returning: self.busStopFeatures)
        }
    }
}
