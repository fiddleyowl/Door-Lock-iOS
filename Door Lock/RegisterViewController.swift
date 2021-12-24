//
//  RegisterViewController.swift
//  Door Lock
//
//  Created by Philip Zhan on 11/26/21.
//

import UIKit
import NotificationBannerSwift

class RegisterViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {

    @IBOutlet weak var deviceIDLabel: UILabel!
    @IBOutlet weak var protocolSegmentedControl: UISegmentedControl!
    @IBOutlet weak var serverAddressTextField: UITextField!
    @IBOutlet weak var generateCSRButton: UIButton!
    @IBOutlet weak var responseTextView: UITextView!
    @IBOutlet weak var createNewButton: UIButton!
    @IBOutlet weak var shareExistingButton: UIButton!
    @IBOutlet weak var clearAllButton: UIButton!
    @IBOutlet weak var verifyButton: UIButton!
    
    var banner: NotificationBanner?
    
    @IBAction func generateCSRAction(_ sender: Any) {
        hideKeyboard()
        let _ = generateRSAKeyPair(tag: "com.philipzhan.doorlock.mainkey")
        let _ = generatePreSharedSecret()
        if let csrText = generateCSR(tag: "com.philipzhan.doorlock.mainkey", name: deviceUUID) {
            UIPasteboard.general.string = csrText
            print(csrText)
            let temporaryFileURL = tempDirectory.appendingPathComponent(deviceUUID+".csr")
            let csrData = csrText.data(using: .utf8)!
            do {
                try csrData.write(to: temporaryFileURL, options: .atomic)
                let activityViewController = UIActivityViewController(activityItems: [temporaryFileURL], applicationActivities: nil)
                // Show the share-view
                self.present(activityViewController, animated: true, completion: nil)
            } catch {
                banner?.dismiss()
                banner = NotificationBanner(title: error.localizedDescription, style: .danger)
                banner?.show()
            }
        } else {
            banner?.dismiss()
            banner = NotificationBanner(title: "Cannot generate CSR.", style: .danger)
            banner?.show()
        }
    }
    
    @IBAction func shareExistingCSRAction(_ sender: Any) {
        hideKeyboard()
        if let csrText = generateCSR(tag: "com.philipzhan.doorlock.mainkey", name: deviceUUID) {
            UIPasteboard.general.string = csrText
            print(csrText)
            let temporaryFileURL = tempDirectory.appendingPathComponent(deviceUUID+".csr")
            let csrData = csrText.data(using: .utf8)!
            do {
                try csrData.write(to: temporaryFileURL, options: .atomic)
                let activityViewController = UIActivityViewController(activityItems: [temporaryFileURL], applicationActivities: nil)
                // Show the share-view
                self.present(activityViewController, animated: true, completion: nil)
            } catch {
                banner?.dismiss()
                banner = NotificationBanner(title: error.localizedDescription, style: .danger)
                banner?.show()
            }
        } else {
            banner?.dismiss()
            banner = NotificationBanner(title: "Cannot generate CSR.", style: .danger)
            banner?.show()
        }
    }
    
    @IBAction func verifyCertificateAction(_ sender: Any) {
        disableButtons()
        guard let address = serverAddressTextField.text else {
            banner?.dismiss()
            banner = NotificationBanner(title: "Server address is invalid.", style: .danger)
            banner?.show()
            enableButtons()
            return
        }
        
        if !validateServerAddress(address) {
            banner?.dismiss()
            banner = NotificationBanner(title: "Server address is invalid.", style: .danger)
            banner?.show()
            enableButtons()
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
                enableButtons()
                return
            }
            guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
                banner?.dismiss()
                banner = NotificationBanner(title: "Certificate data is invalid.", style: .danger)
                banner?.show()
                enableButtons()
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
                enableButtons()
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
                    self.verifyButton.setTitle("Registering...", for: .disabled)
                    
                    var protocolText = "https"
                    if protocolSegmentedControl.selectedSegmentIndex == 1 {
                        protocolText = "http"
                    }
                    
                    let url = URL(string: "\(protocolText)://\(address):8443/register_user?type=iOS&device_id=\(deviceUUID)&pre_shared_secret=\(getPreSharedSecret())&certificate=\(certificateText.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!.replacingOccurrences(of: "+", with: "%2b"))")!
                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = 5.0
                    let session = URLSession(configuration: sessionConfig)
                    let task = session.dataTask(with: url) {(data, response, error) in
                        if error == nil {
                            DispatchQueue.main.async {
                                let httpResponse = response as! HTTPURLResponse
                                if data == "Device registered.".data(using: .utf8) {
                                    self.banner?.dismiss()
                                    self.banner = NotificationBanner(title: "Successfully registered your device.", style: .success)
                                    self.banner?.show()
                                    setRegisterationStatus(true)
                                    let openDoorTableViewController = self.storyboard!.instantiateViewController(withIdentifier: "openDoorTableViewController") as! OpenDoorTableViewController
                                    openDoorTableViewController.modalPresentationStyle = .fullScreen
                                    self.present(openDoorTableViewController, animated: true, completion: nil)
                                    #warning("To main view")
                                } else {
                                    let reason = String(data: data!, encoding: .utf8)!
                                    self.banner?.dismiss()
                                    self.banner = NotificationBanner(title: "Failed to register your device.", subtitle: reason, style: .danger)
                                    self.banner?.show()
                                    self.enableButtons()
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.banner?.dismiss()
                                self.banner = NotificationBanner(title: "Unable to register your device.", subtitle: error?.localizedDescription, style: .danger)
                                self.banner?.show()
                                self.verifyButton.setTitle("Verify", for: .normal)
                                self.enableButtons()
                            }
                            
                        }

//                        guard let data = data else { return }
//                        print(String(data: data, encoding: .utf8)!)
                    }
                    task.resume()
                } else {
                    banner?.dismiss()
                    banner = NotificationBanner(title: "Certificate is valid, but mismatches with stored key pair.", style: .warning)
                    banner?.show()
                    verifyButton.setTitle("Verify", for: .normal)
                    enableButtons()
                }
            } else {
                banner?.dismiss()
                banner = NotificationBanner(title: "Certificate is invalid.", subtitle: error?.localizedDescription, style: .danger)
                banner?.show()
                verifyButton.setTitle("Verify", for: .normal)
                enableButtons()
                print(error as Any)
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
        
        serverAddressTextField.delegate = self
        responseTextView.delegate = self
        
        deviceIDLabel.text = "Your device ID is: " + deviceUUID
        
//        protocolSegmentedControl.selectedSegmentIndex = defaults.integer(forKey: "ProtocolIndex")
        serverAddressTextField.text = getServerAddress()
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        setServerAddress(textField.text)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        responseTextView.textColor = .label
        responseTextView.text = UIPasteboard.general.string
    }
    
    func hideKeyboard() {
        serverAddressTextField.resignFirstResponder()
//        nameTextField.resignFirstResponder()
        responseTextView.resignFirstResponder()
    }
    
    func disableButtons() {
        createNewButton.isEnabled = false
        shareExistingButton.isEnabled = false
        clearAllButton.isEnabled = false
        verifyButton.isEnabled = false
        serverAddressTextField.isEnabled = false
        responseTextView.isEditable = false
        protocolSegmentedControl.isEnabled = false
    }
    
    func enableButtons() {
        createNewButton.isEnabled = true
        shareExistingButton.isEnabled = true
        clearAllButton.isEnabled = true
        verifyButton.isEnabled = true
        serverAddressTextField.isEnabled = true
        responseTextView.isEditable = true
        protocolSegmentedControl.isEnabled = true
    }
    
    

}

