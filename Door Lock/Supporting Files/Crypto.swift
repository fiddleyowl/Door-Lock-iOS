//
//  Crypto.swift
//  Door Lock
//
//  Created by Philip Zhan on 12/8/21.
//

import Foundation
import Security
import CertificateSigningRequest
import LocalAuthentication
import CryptoKit

func generateRSAKeyPair(tag: String) -> SecKey? {
    print("generateRSAKeyPair")
    
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.userPresence], &error) else {
        print("Failed to setup secure access.")
//        print(error)
        return nil
    }
    
    clearAllGeneratedKeys()
    
    let generateAttributes: [String: Any] = [kSecClass as String: kSecClassKey,
                                     kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                     kSecAttrKeySizeInBits as String: 2048,
                                     kSecPublicKeyAttrs as String: [
                                        kSecAttrIsPermanent as String: true,
                                        kSecAttrApplicationTag as String: (tag+".public").data(using: .utf8)!,
                                     ],
                                     kSecPrivateKeyAttrs as String: [
                                        kSecAttrIsPermanent as String: true,
                                        kSecAttrApplicationTag as String: (tag+".private").data(using: .utf8)!,
                                        kSecAttrAccessControl as String: access
                                     ]]
   
    
    guard let privateKey = SecKeyCreateRandomKey(generateAttributes as CFDictionary, &error) else {
        print("Failed to generate RSA private key.")
//        print(error)
        return nil
    }
    
    return privateKey
}

func clearAllGeneratedKeys() {
    let secItemClasses = [kSecClassCertificate, kSecClassKey]
    for itemClass in secItemClasses {
        let spec: NSDictionary = [kSecClass: itemClass]
        SecItemDelete(spec)
    }
}

func getRSAPrivateKey(tag: String) -> SecKey? {
    print("getRSAPrivateKey")
    let getquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                   kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                   kSecReturnRef as String: true,
                                   kSecAttrApplicationTag as String: (tag+".private").data(using: .utf8)!]
    var key: CFTypeRef?
    let status = SecItemCopyMatching(getquery as CFDictionary, &key)
    if status == errSecSuccess {
        let privateKey = key as! SecKey
        return privateKey
    } else {
        print("Failed to get RSA private key.")
        print(status)
        return nil
    }
}

func getRSAPublicKey(tag: String) -> SecKey? {
    print("getRSAPublicKey")
    let getquery: [String: Any] = [kSecClass as String: kSecClassKey,
                                   kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                   kSecReturnRef as String: true,
                                   kSecAttrApplicationTag as String: (tag+".public").data(using: .utf8)!]
    var key: CFTypeRef?
    let status = SecItemCopyMatching(getquery as CFDictionary, &key)
    if status == errSecSuccess {
        let publicKey = key as! SecKey
        return publicKey
    } else {
        print("Failed to get RSA public key.")
        print(status)
        return nil
    }
}

func generateCSR(tag: String, name: String) -> String? {
    print("generateCSR")
    let algorithm = KeyAlgorithm.rsa(signatureType: .sha256)
    let csr = CertificateSigningRequest(commonName: name, organizationName: "Southern University of Science and Technology", countryName: "CN", stateOrProvinceName: "Guangdong", localityName: "Shenzhen", keyAlgorithm: algorithm)

    guard let privateKey = getRSAPrivateKey(tag: tag) else {
        print("Failed to get private key.")
        return nil
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
        print("Failed to get public key from private key.")
        return nil
    }

    // Ask keychain to provide the publicKey in bits
    let query: [String: Any] = [kSecClass as String: kSecClassKey,
                                   kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                   kSecReturnData as String: true,
                                   kSecAttrApplicationTag as String: (tag+".public").data(using: .utf8)!]

    var tempPublicKeyBits:CFTypeRef?
    var _ = SecItemCopyMatching(query as CFDictionary, &tempPublicKeyBits)

    guard let keyBits = tempPublicKeyBits as? Data else {
        print("Failed to parse public key.")
        return nil
    }
    
    let builtCSR = csr.buildCSRAndReturnString(keyBits, privateKey: privateKey, publicKey: publicKey)
    return builtCSR
}

func generatePreSharedSecret() -> String {
    let str = randomString(length: 10)
    defaults.set(str, forKey: "PreSharedSecret")
    return str
}

func getPreSharedSecret() -> String {
    return defaults.string(forKey: "PreSharedSecret")!
}

func randomString(length: Int) -> String {
  let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  return String((0..<length).map{ _ in letters.randomElement()! })
}

func sha256(data: Data) -> Data {
    return Data.init(SHA256.hash(data: data))
}

func sha256(data: String) -> Data {
    let rawData = data.data(using: .utf8)!
    return sha256(data: rawData)
}

func sha256(data: Data) -> String {
    return sha256(data: data).hexEncodedString()
}
