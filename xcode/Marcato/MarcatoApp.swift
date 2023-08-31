//
//  Marcato.swift
//  Marcato
//
//  Created by Lucas Xie on 8/28/23.
//

import SwiftUI
import CryptoKit
import AuthenticationServices
import UserNotifications


@main
struct Marcato: App {
    @StateObject private var apiManager: ApiManager = ApiManager()
    
    
        var body: some Scene {
            MenuBarExtra("marcato", systemImage: "radio") {
                VStack {
                    Text("Token: \(apiManager.token)")//.multilineTextAlignment(TextAlignment.leading)
                    Button("Settings") {
                        
                    }
                    
                }.padding([.leading, .trailing], 90)
                    .padding([.bottom, .top], 20)
                    .onAppear() {
                        apiManager.fetchToken(clientId: Constants.API.SPOTIFY_CLIENT_ID, clientSecret: Constants.API.SPOTIFY_CLIENT_SECRET)
                        apiManager.requestUserAuthorisation(clientId: Constants.API.SPOTIFY_CLIENT_ID)
                        showNotification()
                    }
                
                
            }.menuBarExtraStyle(.window)
            
            
        }
    
    
    func showNotification() {
        let notifCenter = UNUserNotificationCenter.current()

        // Provisional authorisation
                notifCenter.requestAuthorization(options: [.alert, .provisional]) { (granted, error) in
                    if let error = error {
                        print("Provisional notif auth failed.")
                    } else { print ("PNOTIF SUCCESS") }
                }
        
        // Customize notification based on settings
        notifCenter.getNotificationSettings { settings in
            guard (settings.authorizationStatus == .provisional) || (settings.authorizationStatus == .authorized) else {return}
            
            
            // Send notification
            let content = UNMutableNotificationContent()
            content.title = "Current song"
            content.body = "Lorem Ipsum - Dolor"
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let uuid = UUID().uuidString
            let request = UNNotificationRequest(identifier: uuid, content: content, trigger: trigger)
            
            notifCenter.add(request) { (error) in
                if error != nil {
                    print("Notification request error.")
                }
            }
            
            
        }
    }
    }
    
    struct AccessToken: Codable {
        var access_token, token_type: String
        var expires_in: UInt32
    }
    
    class ApiManager: ObservableObject {
        @Published var token: String = ""
        
        func fetchToken(clientId: String, clientSecret: String) {
            requestToken(clientId: clientId, clientSecret: clientSecret, {
                (result) in
                DispatchQueue.main.async {
                    self.token = result
                }
            })
        }
        
        func requestToken(clientId: String, clientSecret: String, _ completionHandler: @escaping (String) -> Void) {
            
            let url = URL(string: "https://accounts.spotify.com/api/token")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            let body = "grant_type=client_credentials&client_id=\(clientId)&client_secret=\(clientSecret)"
            let finalBody = body.data(using: .utf8)
            
            request.httpBody = finalBody
            
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode), error == nil
                else {
                    // Do error stuff
                    print("Error when fetching Spotify token: \(error) & \(response)")
                    return
                }
                
                if let data = data {
                    if let accessToken = try? JSONDecoder().decode(AccessToken.self, from: data) {
                        completionHandler(accessToken.access_token)
                    }
                    else {
                        print("FAIL")
                    }
                }
            }
            
            task.resume()
        }
        
        // https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
        func generateRandomString(length: UInt) -> String {
            var text = ""
            
            let possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            for _ in 1...length {
                let index = Int.random(in: 0..<possible.count)
                text += String(possible[possible.index(possible.startIndex, offsetBy: index)]) // Tip: generally better to use .startIndex and offset than just assume 0 = startIndex.
            }
            
            return text
        }
        
        
        func generateCodeChallenge(codeVerifier: String) -> String {
            let data = codeVerifier.data(using: .utf8)!
            
            // Assisted by GPT3.5
            let digest = SHA256.hash(data: data) // Generate hash digest (32 bytes)
            /*  let hashString = hashed.compactMap { String(format: "%02x", $0) }.joined() // Convert to hexa string (compactMap removes nils, S.format converts ($0 refers to current array value like Ruby)) <- ONLY NEEDED IF YOU WANT A CONVERTED VERSION!!*/
            
            
            return Data(digest).base64EncodedString() // Convert to Data, get base64 encoded
        }
        
        func requestUserAuthorisation(clientId: String) {
            let queryItemClientId = URLQueryItem(name: "client_id", value: clientId)
            let queryItemResponseType = URLQueryItem(name: "response_type", value: "code")
            let queryItemRedirectUri = URLQueryItem(name: "redirect_uri", value: "marcato://auth")
            let queryItemState = URLQueryItem(name: "state", value: generateRandomString(length: 16))
            let queryItemScope = URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state playlist-read-private user-read-recently-played user-library-read")
            let queryItemCodeChallengeMethod = URLQueryItem(name: "code_challenge_method", value: "S256")
            let queryItemCodeChallenge = URLQueryItem(name: "code_challenge", value: generateCodeChallenge(codeVerifier: generateRandomString(length: 128)))
            
            var components = URLComponents()
            components.scheme = "https"
            components.host = "accounts.spotify.com"
            components.path = "/authorize"
            components.queryItems = [queryItemClientId, queryItemResponseType, queryItemRedirectUri, queryItemState, queryItemScope, queryItemCodeChallengeMethod, queryItemCodeChallenge]
            
            /* guard let authUrl = URL(string: "https://accounts.spotify.com/authorize?client_id=\(clientId)&response_type=\(responseType)&redirect_uri=\(redirectUri)&state=\(state)&scope=\(scope)&code_challenge_method=\(codeChallengeMethod)&code_challenge=\(codeChallenge)") else {return} */
            
            
            // Browser tab view
            if let authUrl = components.url {
                print(authUrl)
                NSWorkspace.shared.open(authUrl)
            }
            
            /* // In-window view
             let session = ASWebAuthenticationSession(url: authUrl, callbackURLScheme: "marcato", completionHandler: {(callbackURL, error) in
             
             guard error == nil, let callbackURL = callbackURL else { return }
             
             // The callback URL format depends on the provider
             let queryItems = URLComponents(string: callbackURL.absoluteString)?.queryItems
             let code = queryItems?.filter({ $0.name == "code" }).first?.value
             })
             session.start()*/
            
        }
    }

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, account, security, notifications, advanced, about
    }
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)
            
            
        }
        
        
    }

}

struct GeneralSettingsView: View {
    @AppStorage("bootOnStart") private var bootOnStart = false
    @AppStorage("fontSize") private var fontSize = 12.0
    
    var body: some View {
        Form {
            Toggle("Boot on Startup", isOn: $bootOnStart)
            Slider(value: $fontSize, in: 9...20) {
                Text("Font Size(\(fontSize, specifier: "%.0f") pts)")
            }
        }
        .padding(20)
        .frame(width: 350, height: 100)
    }
}

struct AccountSettingsView: View {
    @AppStorage("spotifyLink") private var spotifyLink = false
    @AppStorage("appleMusicLink") private var appleMusicLink = false
    @AppStorage("youtubeLink") private var youtubeLink = false
    
    var body: some View {
        Form {
            Button("Link Spotify") {
                print("sp")
            }
            
            Button("Link Apple Music") {
                print("am")
            }
            
        
            Button("Link Youtube Music") {
                print("ym")
            }
        }
        .padding(20)
        .frame(width: 350, height: 100)
    }
}

