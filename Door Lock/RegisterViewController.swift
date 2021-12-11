//
//  RegisterViewController.swift
//  Door Lock
//
//  Created by Philip Zhan on 11/26/21.
//

import UIKit
import NotificationBannerSwift

class RegisterViewController: UIViewController, UITextViewDelegate {

    @IBOutlet weak var deviceIDLabel: UILabel!
    @IBOutlet weak var protocolSegmentedControl: UISegmentedControl!
    @IBOutlet weak var piAddressTextField: UITextField!
//    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var generateCSRButton: UIButton!
    @IBOutlet weak var responseTextView: UITextView!
    
    var banner: NotificationBanner?
    
    @IBAction func generateCSRAction(_ sender: Any) {
        generateRSAKeyPair(tag: "com.philipzhan.doorlock.mainkey")
        generatePreSharedSecret()
        if let csrText = generateCSR(tag: "com.philipzhan.doorlock.mainkey", name: uuid) {
            UIPasteboard.general.string = csrText
            
            print(csrText)
        }
        hideKeyboard()
    }
    
    @IBAction func shareExistingCSRAction(_ sender: Any) {
        if let csrText = generateCSR(tag: "com.philipzhan.doorlock.mainkey", name: uuid) {
            UIPasteboard.general.string = csrText
            print(csrText)
        }
        generatePreSharedSecret()
        hideKeyboard()
    }
    
    @IBAction func verifyCertificateAction(_ sender: Any) {
        guard let address = piAddressTextField.text else {
            banner?.dismiss()
            banner = NotificationBanner(title: "Server address is invalid.", style: .danger)
            banner?.show()
            return
        }
        
        if !validateServerAddress(address) {
            banner?.dismiss()
            banner = NotificationBanner(title: "Server address is invalid.", style: .danger)
            banner?.show()
            return
        }
        
        if let certificateText = responseTextView.text {
            let caCertificateData = FileManager().contents(atPath: bundleDirectory.appending("/Door_Lock_CA.cer"))
            let caCertificate = SecCertificateCreateWithData(nil, caCertificateData! as CFData)

            var certificateWithoutHeaderFooter = certificateText.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            certificateWithoutHeaderFooter = certificateWithoutHeaderFooter.replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            certificateWithoutHeaderFooter = certificateWithoutHeaderFooter.replacingOccurrences(of: "\n", with: "")
            
            guard let certificateData = Data(base64Encoded: certificateWithoutHeaderFooter) else {
                banner?.dismiss()
                banner = NotificationBanner(title: "Unable to parse certificate data.", style: .danger)
                banner?.show()
                return
            }
            guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
                banner?.dismiss()
                banner = NotificationBanner(title: "Certificate data is invalid.", style: .danger)
                banner?.show()
                return
            }
//            print(certificate)
            
            let policy = SecPolicyCreateBasicX509()
            var optionalTrust: SecTrust?
            let status = SecTrustCreateWithCertificates([certificate, caCertificate] as AnyObject,
                                                        policy,
                                                        &optionalTrust)
            
            guard status == errSecSuccess else {
                banner?.dismiss()
                banner = NotificationBanner(title: "Unable to verify certificate.", subtitle: status.description, style: .danger)
                banner?.show()
                return
                
            }
            let trust = optionalTrust!
            SecTrustSetAnchorCertificates(trust, [caCertificate] as CFArray)
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                // Succeeded.
                let certificatePublicKey = SecCertificateCopyKey(certificate)!
                let storedPublicKey = getRSAPublicKey(tag: "com.philipzhan.doorlock.mainkey")
                if certificatePublicKey == storedPublicKey {
                    banner?.dismiss()
                    banner = NotificationBanner(title: "Certificate is valid.", style: .success)
                    banner?.show()
                    print("Certificate is valid.")
                    
                    var protocolText = "https"
                    if protocolSegmentedControl.selectedSegmentIndex == 1 {
                        protocolText = "http"
                    }
                    
                    let url = URL(string: "\(protocolText)://\(address):8443/register_user?type=iOS&device_id=\(uuid)&pre_shared_secret=\(defaults.string(forKey: "PreSharedSecret")!)&certificate=\(certificateText.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!.replacingOccurrences(of: "+", with: "%2b"))")!
                    let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
                        guard let data = data else { return }
                        print(String(data: data, encoding: .utf8)!)
                    }
                    task.resume()
                } else {
                    banner?.dismiss()
                    banner = NotificationBanner(title: "Certificate is valid, but mismatches with stored key pair.", style: .warning)
                    banner?.show()
                }
            } else {
                banner?.dismiss()
                banner = NotificationBanner(title: "Certificate is invalid.", subtitle: error?.localizedDescription, style: .danger)
                banner?.show()
                print(error)
            }
            
            
            
//            let certificate = SecCertificateCreateWithData(nil, certificateText.data(using: .utf8)! as CFData)
            
        }
    }
    
    @IBAction func clearAllAction(_ sender: Any) {
        clearAllGeneratedKeys()
        hideKeyboard()
//        nameTextField.text = ""
        responseTextView.textColor = .placeholderText
        responseTextView.text = """
Paste response here.
-----BEGIN CERTIFICATE-----
Lorem ipsum dolor sit er elit lamet, consectetaur cillium adipisicing pecu, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. Nam liber te conscient to factor tum poen legum odioque civiuda.
-----END CERTIFICATE-----
"""
    }
    
    @IBAction func singleTap(_ sender: Any) {
        hideKeyboard()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        responseTextView.delegate = self
        
        deviceIDLabel.text = "Your device ID is: " + uuid
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        responseTextView.textColor = .label
        responseTextView.text = UIPasteboard.general.string
    }
    
    func hideKeyboard() {
        piAddressTextField.resignFirstResponder()
//        nameTextField.resignFirstResponder()
        responseTextView.resignFirstResponder()
    }
    
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

}

