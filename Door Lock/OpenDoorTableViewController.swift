//
//  OpenDoorTableViewController.swift
//  Door Lock
//
//  Created by Philip Zhan on 12/21/21.
//

import UIKit
import NotificationBannerSwift

class OpenDoorTableViewController: UITableViewController {
    
    @IBOutlet weak var deviceIDLabel: UILabel!
    @IBOutlet weak var useHTTPSSwitch: UISwitch!
    @IBOutlet weak var serverAddressTextField: UITextField!
    
    var banner: NotificationBanner?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        
        deviceIDLabel.text = deviceUUID
        serverAddressTextField.text = getServerAddress()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print(indexPath.row)
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2 {
            if indexPath.row == 0 {
                openDoor(useHTTPS: useHTTPSSwitch.isOn, serverAddress: serverAddressTextField.text ?? "1.1:1")
            } else if indexPath.row == 1 {
                deactivateDevice(useHTTPS: useHTTPSSwitch.isOn, serverAddress: serverAddressTextField.text ?? "1.1:1")
            } else if indexPath.row == 2 {
                
            }
        } else if indexPath.section == 3 {
            if indexPath.row == 0 {
                exportPublicKey()
            } else if indexPath.row == 1 {
                exportPrivateKey()
            }
        }
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    /// Constructs a request URL to the server in fixed format.
    ///
    /// Example request:
    /// ```protocol://serverAddress:8443/apiName```
    ///
    /// URL Parameters:
    /// - ```type```
    /// - ```timestamp```
    /// - ```device_id```
    /// - ```signature```
    ///
    /// Signature is constructed by combining ```requestPrefix```, ```timeMillis```, ```deviceUUID```, ```preSharedSecret``` as one string, taking its sha256 checksum, and signing using stored private key.
    ///
    /// - Returns: Returns the constructed URL to send.
    func constructURL(apiName: String, requestPrefix: String, useHTTPS: Bool, serverAddress: String) -> URL? {
        if !validateServerAddress(serverAddress) {
            banner?.dismiss()
            banner = NotificationBanner(title: "Server address is invalid.", style: .danger)
            banner?.show()
            return nil
        }
        
        let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
        guard let privateKey = getRSAPrivateKey(tag: "com.philipzhan.doorlock.mainkey") else {
            banner?.dismiss()
            banner = NotificationBanner(title: "Unable to retrieve private key.", style: .danger)
            banner?.show()
            return nil
        }
        let timeMillis = Int(Date.now.timeIntervalSince1970 * 1000)
        let dataString = "Open\(timeMillis)\(deviceUUID)\(getPreSharedSecret())"
//        print(dataString)
//        let data: Data = sha256(data: dataString)
        let data = dataString.data(using: .utf8)!
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, data as CFData, &error) as Data? else {
            banner?.dismiss()
            banner = NotificationBanner(title: "Unable to create signature.", subtitle: "\(error?.takeRetainedValue().localizedDescription ?? "")", style: .danger)
            banner?.show()
            return nil
        }
        
//        print(signature.hexEncodedString())
        
        let signatureText = signature.hexEncodedString()
        
        var protocolText = "https"
        if !useHTTPS {
            protocolText = "http"
        }
 
        let url = URL(string: "\(protocolText)://\(serverAddress):8443/\(apiName)?type=iOS&timestamp=\(timeMillis)&device_id=\(deviceUUID)&signature=\(signatureText.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!.replacingOccurrences(of: "+", with: "%2b"))")!
        
        return url
    }

    func openDoor(useHTTPS: Bool, serverAddress: String) {
        guard let url = constructURL(apiName: "open_door", requestPrefix: "Open", useHTTPS: useHTTPS, serverAddress: serverAddress) else {
            return
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 5.0
        let session = URLSession(configuration: sessionConfig)
        let task = session.dataTask(with: url) {(data, response, error) in
            if error == nil {
                DispatchQueue.main.async {
//                    let httpResponse = response as! HTTPURLResponse
                    if data == "Door opening.".data(using: .utf8) {
                        self.banner?.dismiss()
                        self.banner = NotificationBanner(title: "Door opening.", style: .success)
                        self.banner?.show()
                    } else {
                        let reason = String(data: data!, encoding: .utf8)!
                        self.banner?.dismiss()
                        self.banner = NotificationBanner(title: "Failed to open the door.", subtitle: reason, style: .danger)
                        self.banner?.show()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.banner?.dismiss()
                    self.banner = NotificationBanner(title: "Unable to open door.", subtitle: error?.localizedDescription, style: .danger)
                    self.banner?.show()
                }
                
            }
        }
        task.resume()
        
    }
    
    func deactivateDevice(useHTTPS: Bool, serverAddress: String) {
        guard let url = constructURL(apiName: "deactivate_device", requestPrefix: "Deactivate", useHTTPS: useHTTPS, serverAddress: serverAddress) else {
            return
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 5.0
        let session = URLSession(configuration: sessionConfig)
        let task = session.dataTask(with: url) {(data, response, error) in
            if error == nil {
                DispatchQueue.main.async {
                    let httpResponse = response as! HTTPURLResponse
                    if data == "Device deactivated.".data(using: .utf8) {
                        self.banner?.dismiss()
                        self.banner = NotificationBanner(title: "Device deactivated.", style: .success)
                        self.banner?.show()
                        defaults.removeObject(forKey: "PreSharedSecret")
                        clearAllGeneratedKeys()
                        setRegisterationStatus(false)
                        let registerViewController = self.storyboard!.instantiateViewController(withIdentifier: "registerViewController") as! RegisterViewController
                        registerViewController.modalPresentationStyle = .fullScreen
                        self.present(registerViewController, animated: true, completion: nil)
                    } else {
                        self.banner?.dismiss()
                        self.banner = NotificationBanner(title: "Failed to deactivate device.", subtitle: "Status Code: \(httpResponse.statusCode)", style: .danger)
                        self.banner?.show()
                    }
                }
                #warning("To register view.")
            } else {
                DispatchQueue.main.async {
                    self.banner?.dismiss()
                    self.banner = NotificationBanner(title: "Unable to deactive device.", subtitle: error?.localizedDescription, style: .danger)
                    self.banner?.show()
                }
                
            }
        }
        task.resume()
    }
    
    func exportPublicKey() {
        let key = getRSAPrivateKey(tag: "com.philipzhan.doorlock.mainkey")!
        guard let pubKey = SecKeyCopyPublicKey(key) else {
            self.banner?.dismiss()
            self.banner = NotificationBanner(title: "Unable to copy public key.",  style: .danger)
            self.banner?.show()
            return
        }
        var error:Unmanaged<CFError>?
        if let cfdata = SecKeyCopyExternalRepresentation(pubKey, &error) {
           let data:Data = cfdata as Data
           let b64KeyString = data.base64EncodedString()
            let output = "-----BEGIN RSA PUBLIC KEY-----\n"+b64KeyString+"\n-----END RSA PUBLIC KEY-----"
            UIPasteboard.general.string = output
            self.banner?.dismiss()
            self.banner = NotificationBanner(title: "Public key copied to clipbard.",  style: .info)
            self.banner?.show()
        }
    }
    
    func exportPrivateKey() {
        let key = getRSAPrivateKey(tag: "com.philipzhan.doorlock.mainkey")!
        var error:Unmanaged<CFError>?
        if let cfdata = SecKeyCopyExternalRepresentation(key, &error) {
           let data:Data = cfdata as Data
           let b64KeyString = data.base64EncodedString()
            let output = "-----BEGIN RSA PRIVATE KEY-----\n"+b64KeyString+"\n-----END RSA PRIVATE KEY-----"
            UIPasteboard.general.string = output
            self.banner?.dismiss()
            self.banner = NotificationBanner(title: "Private key copied to clipbard.",  style: .info)
            self.banner?.show()
        }
    }
    
}
