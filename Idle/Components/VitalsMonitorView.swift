import SwiftUI

struct VitalsMonitorView: View {
    @EnvironmentObject var vitalsManager: VitalsManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                
                Text("Vitals Monitor")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                StatusIndicator(isActive: vitalsManager.isMonitoring)
            }
            
            // Vitals Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                VitalCard(
                    icon: "heart.fill",
                    value: vitalsManager.currentHeartRate > 0
                        ? "\(Int(vitalsManager.currentHeartRate))"
                        : "--",
                    unit: "bpm",
                    label: "Heart Rate",
                    color: .red
                )
                
                VitalCard(
                    icon: "wind",
                    value: vitalsManager.currentBreathingRate > 0
                        ? String(format: "%.1f", vitalsManager.currentBreathingRate)
                        : "--",
                    unit: "rpm",
                    label: "Breathing",
                    color: .blue
                )
                
                VitalCard(
                    icon: "waveform.path.ecg",
                    value: "\(vitalsManager.signalQuality)",
                    unit: "%",
                    label: "Signal",
                    color: signalColor
                )
                
                VitalCard(
                    icon: "moon.zzz.fill",
                    value: "\(Int(vitalsManager.driftScore))",
                    unit: "%",
                    label: "Drift",
                    color: .cyan
                )
            }
            
            // Signal Quality Bar
            if vitalsManager.isMonitoring {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signal Quality")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    ProgressView(value: Double(vitalsManager.signalQuality) / 100)
                        .tint(signalColor)
                        .scaleEffect(y: 2)
                    
                    Text(signalQualityText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
            }
        }
        .padding()
    }
    
    private var signalColor: Color {
        switch vitalsManager.signalQuality {
        case 0..<30:
            return .red
        case 30..<60:
            return .orange
        case 60..<80:
            return .yellow
        default:
            return .green
        }
    }
    
    private var signalQualityText: String {
        switch vitalsManager.signalQuality {
        case 0..<30:
            return "Poor - Adjust camera position"
        case 30..<60:
            return "Fair - Hold steady"
        case 60..<80:
            return "Good - Monitoring active"
        default:
            return "Excellent - Clear signal"
        }
    }
}

struct VitalCard: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(color)
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                Text(unit)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct StatusIndicator: View {
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(isActive ? "Active" : "Inactive")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .green : .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.05))
        )
    }
}

#Preview {
    VitalsMonitorView()
        .environmentObject(VitalsManager())
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.15, green: 0.05, blue: 0.25)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
}
