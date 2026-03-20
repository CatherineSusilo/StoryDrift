import SwiftUI
import Charts

struct StorySummaryView: View {
    let story: Story
    let driftHistory: [Double]
    let duration: TimeInterval
    let onDismiss: () -> Void
    
    private var chartData: [ChartDataPoint] {
        driftHistory.enumerated().map { index, score in
            ChartDataPoint(time: index, score: score)
        }
    }
    
    private var sleepOnsetTime: String {
        if let sleepTime = story.sleepOnsetTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: sleepTime)
        }
        return "N/A"
    }
    
    private var formattedDuration: String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Sweet Dreams!")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Story Complete")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 40)
                
                // Story Info
                VStack(spacing: 16) {
                    Text(story.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 12) {
                        ForEach(story.themes, id: \.self) { theme in
                            Text(theme)
                                .font(.system(size: 14))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                }
                
                // Stats Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(
                        icon: "timer",
                        value: formattedDuration,
                        label: "Duration",
                        color: .blue
                    )
                    
                    StatCard(
                        icon: "moon.zzz.fill",
                        value: sleepOnsetTime,
                        label: "Sleep Time",
                        color: .purple
                    )
                    
                    StatCard(
                        icon: "book.fill",
                        value: "\(story.paragraphs.count)",
                        label: "Paragraphs",
                        color: .orange
                    )
                    
                    StatCard(
                        icon: "chart.line.uptrend.xyaxis",
                        value: "\(Int(driftHistory.last ?? 0))%",
                        label: "Final Drift",
                        color: .green
                    )
                }
                .padding(.horizontal)
                
                // Drift Chart
                VStack(alignment: .leading, spacing: 16) {
                    Text("Drift Progress")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if #available(iOS 16.0, *) {
                        Chart(chartData) { point in
                            LineMark(
                                x: .value("Time", point.time),
                                y: .value("Drift", point.score)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .interpolationMethod(.catmullRom)
                            
                            AreaMark(
                                x: .value("Time", point.time),
                                y: .value("Drift", point.score)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple.opacity(0.3), .blue.opacity(0.2), .cyan.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel()
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .frame(height: 200)
                    } else {
                        SimpleDriftChart(data: chartData)
                            .frame(height: 200)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("Back to Dashboard")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                    }
                    
                    Button(action: {
                        // Share summary
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Summary")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.15, green: 0.05, blue: 0.25)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Int
    let score: Double
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
}

struct SimpleDriftChart: View {
    let data: [ChartDataPoint]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }
                
                let maxValue = data.map(\.score).max() ?? 100
                let stepX = geometry.size.width / CGFloat(max(data.count - 1, 1))
                
                for (index, point) in data.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - point.score / maxValue)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                LinearGradient(
                    colors: [.purple, .blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 3
            )
        }
    }
}

#Preview {
    StorySummaryView(
        story: Story(
            id: "1",
            childId: "child1",
            title: "The Magical Forest Adventure",
            themes: ["Adventure", "Nature", "Magic"],
            generatedAt: Date(),
            completed: true,
            sleepOnsetTime: Date(),
            paragraphs: [],
            images: [],
            initialState: .normal,
            duration: 900,
            driftScores: []
        ),
        driftHistory: [0, 15, 25, 40, 55, 68, 78, 85, 92, 95],
        duration: 900,
        onDismiss: {}
    )
}
