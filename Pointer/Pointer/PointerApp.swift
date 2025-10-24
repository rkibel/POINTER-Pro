//
//  PointerApp.swift
//  Pointer
//
//  Created by Ron Kibel on 10/20/25.
//

import SwiftUI

@main
struct PointerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

// App delegate to handle orientation locking
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
