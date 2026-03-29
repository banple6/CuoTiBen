import SwiftUI
import UIKit

@main
struct HuiLuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light) // Or .dark for dark mode
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        // Configure appearance
        configureAppearance()
        
        return true
    }
    
    private func configureAppearance() {
        // Navigation bar styling
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        
        // Tab bar styling
        UITabBar.appearance().unselectedItemTintColor = UIColor.systemGray
    }
}
