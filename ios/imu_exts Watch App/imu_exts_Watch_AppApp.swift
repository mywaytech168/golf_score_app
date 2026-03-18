import SwiftUI

@main
struct imu_exts_Watch_AppApp: App {
    init() {
        WatchConnectivityManager.shared.activate()
        // IMU 不自動啟動，等 iPhone 發送指令
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @ObservedObject var motion = MotionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(motion.isRunning ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(motion.isRunning ? "傳輸中" : "等待連線")
                        .font(.headline)
                }

                if motion.isRunning {
                    Divider()

                    Text("加速度 (m/s²)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("X: \(motion.ax, specifier: "%.3f")")
                        .font(.caption2)
                    Text("Y: \(motion.ay, specifier: "%.3f")")
                        .font(.caption2)
                    Text("Z: \(motion.az, specifier: "%.3f")")
                        .font(.caption2)

                    Divider()

                    Text("角速度 (rad/s)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("X: \(motion.gx, specifier: "%.3f")")
                        .font(.caption2)
                    Text("Y: \(motion.gy, specifier: "%.3f")")
                        .font(.caption2)
                    Text("Z: \(motion.gz, specifier: "%.3f")")
                        .font(.caption2)
                } else {
                    Text("請從 iPhone App 啟動連線")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top)
                }

                Spacer()
            }
            .padding()
        }
    }
}
