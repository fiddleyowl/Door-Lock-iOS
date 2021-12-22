//
//  PublicDefinitions.swift
//  Door Lock
//
//  Created by Philip Zhan on 12/8/21.
//

import Foundation
import UIKit

let defaults = UserDefaults.standard
let deviceUUID = (UIDevice.current.identifierForVendor?.uuidString)!
let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
let bundleDirectory = Bundle.main.bundlePath

func validateServerAddress(_ address: String) -> Bool {
    // https://stackoverflow.com/questions/24482958/validate-if-a-string-in-nstextfield-is-a-valid-ip-address-or-domain-name
    var sin = sockaddr_in()
    var sin6 = sockaddr_in6()
    
    if address.withCString({ cstring in inet_pton(AF_INET6, cstring, &sin6.sin6_addr) }) == 1 {
        // IPv6 peer.
        return true
    }
    
    if address.withCString({ cstring in inet_pton(AF_INET, cstring, &sin.sin_addr) }) == 1 {
        // IPv4 peer.
        return true
    }
    
    let hostname = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$"
    
    return address.range(of: hostname,
                              options: .regularExpression,
                              range: nil,
                              locale: nil) != nil
    
}

func setServerAddress(_ address: String?) {
    defaults.set(address, forKey: "ServerAddress")
}

func getServerAddress() -> String? {
    return defaults.string(forKey: "ServerAddress")
}

func setRegisterationStatus(_ registered: Bool) {
    defaults.set(registered, forKey: "IsRegistered")
}

func getRegisterationStatus() -> Bool? {
    return defaults.bool(forKey: "IsRegistered")
}


extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }
}
