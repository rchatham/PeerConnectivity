//
//  PeerNetworkCertificateFixtures.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 10/29/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import Security

/// Self-signed P-256 test identities (PKCS#12, passphrase "test"), imported in memory only.
/// They exist solely to exercise Network certificate mode and carry no trust anywhere else.
internal enum PeerNetworkCertificateFixtures {

    internal enum Name : String {
        case alice
        case bob
        case mallory
    }

    internal static func identity(_ name: Name) throws -> SecIdentity {
        guard let data = Data(base64Encoded: pkcs12[name]!.joined()) else {
            throw XCTSkip("Invalid certificate fixture")
        }
        var options : [String:Any] = [kSecImportExportPassphrase as String: "test"]
        #if os(macOS)
        // Without memory-only import, macOS would add the identity to the login Keychain.
        guard #available(macOS 15.0, *) else {
            throw XCTSkip("In-memory PKCS#12 import requires macOS 15")
        }
        options[kSecImportToMemoryOnly as String] = true
        #endif
        var items : CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
            let item = (items as? [[String:Any]])?.first,
            let identity = item[kSecImportItemIdentity as String] else {
            throw XCTSkip("PKCS#12 import failed with status \(status)")
        }
        return identity as! SecIdentity
    }

    internal static func certificateData(_ name: Name) throws -> Data {
        var certificate : SecCertificate?
        let status = SecIdentityCopyCertificate(try identity(name), &certificate)
        guard status == errSecSuccess, let certificate = certificate else {
            throw XCTSkip("Certificate copy failed with status \(status)")
        }
        return SecCertificateCopyData(certificate) as Data
    }

    fileprivate static let pkcs12 : [Name:[String]] = [
        .alice: [
            "MIIDigIBAzCCA0gGCSqGSIb3DQEHAaCCAzkEggM1MIIDMTCCAicGCSqGSIb3DQEHBqCCAhgwggIU",
            "AgEAMIICDQYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQYwDgQI3CkcYI1/Iw0CAggAgIIB4EmQM3rb",
            "IT0fXi5zL/b200n8HaSpfNV0NEoNGYV8YijX/TSdM5vRrbARNJRkxxft/mP2trj3Qtg182J/QFdL",
            "MkA7m0YhmE9AMJxgNwrEIWsQ//jms7IinvEgyg8qtxVi7rHAegBh3aEm9vPMSpbThuJUut40x3Cd",
            "BCD7WE1W4325YYxE/SvTdlSeU7eOGLCHPRFG0graIdJ2IeUF0vpTAauRVIr9Plk4rtd5E3MZXlJz",
            "s21Xq93QMTgwEoeNFvtXu3kyAf40Scw7bZhoNQ0+z4kfV6iP2eNzRjt7Lpv97+q1pQWuOIvNUB+o",
            "6pkDEqnFoWL2JW/h0sUqWthK4/zLR2swN4fISgejREtyHXuLZj/pLyjnWfi79E5iHkaNeEbrSzvs",
            "YjZn++CQWObaIO7HHXBMP5Oz1+aHsOTc9W05PgLCP0zYJmpvnTMvKF+nHE9P55kX8Ou33gFOd/II",
            "UwBvOGB7Uh98RycoLgFAWuV3/uZw9bWrhMOPe5i/yWW+md19zUx+iXQOrm0hSg5hLLGDNUMowXAe",
            "/lM3xfumspSKuUUaMOtNxFUAbfXFgZtDHotOZd7IFdzqdwit/5QNM+VY5kuRmJDkvEjaziLiE/Yf",
            "GOelPW3QuOz/ovOy0eThFSsV2TCCAQIGCSqGSIb3DQEHAaCB9ASB8TCB7jCB6wYLKoZIhvcNAQwK",
            "AQKggbQwgbEwHAYKKoZIhvcNAQwBAzAOBAjqch8WLaZdsAICCAAEgZCBzjv+bEF+tqbYg18+hZab",
            "eDOUfZuLOEsdzhWk/i4i/STJ9puUKtbvCIyFSE7JUzPAziHR3WLHDRxkrBksITeSmpNU4DO+mzlN",
            "oLF7liF1GcaTicZ4hENpVaX48pq7YojG5qRxy9PW2BGkAW8B8LD+SPB/8+MInWTi9gh+KT1FcN3b",
            "wtVjJJ+i3MJNsXumlQExJTAjBgkqhkiG9w0BCRUxFgQU5e0oeMm4AAUXz3yqiWxxKvYKBdgwOTAh",
            "MAkGBSsOAwIaBQAEFAJR7gsVj+svr5xOkSsA/ENZVRTuBBCTTv7eZV2AZlwOGrohJ4k0AgIIAA==",
        ],
        .bob: [
            "MIIDigIBAzCCA0gGCSqGSIb3DQEHAaCCAzkEggM1MIIDMTCCAicGCSqGSIb3DQEHBqCCAhgwggIU",
            "AgEAMIICDQYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQYwDgQI7d9kWfXgdI8CAggAgIIB4BtFDVyO",
            "Nh9+ZL1NxDRjrWx6fNGzc2/9ps5Vk0fIa0o7YLIJaT0scjR27ZMmiJer0X1xnSLspd80NZ7yoUuN",
            "bL68W3L7Pldr2M2Fei88V/yfg7lzUd5YYlJsdZ5xxDcLwBbT8TsylPoEgzWn6H3HdqY0+fzBGX7O",
            "0VSHxzeWjX2It2qtAqDRViY83LQqvzYRcjCVQfKmY8YhqBp9RJGHS1xMOSgk+Tk4TAnRMC/Or1r1",
            "A1/KUTiY9UT7FFKzR9JcxWQL7fhuKpJQ6SccavPKeiwQU8xzUbOzdwDAOUilB15oyaQ8bz6f6OyB",
            "ngWB3y+YSLMvXGjimsxm2S7tPaY5gsE9bVsKfibgZ+/XYBw17COlWSqKBt4goVgWz9HY/T1OaO8H",
            "9Hb1jA3LUjSI9VOjK23GXyuXOZaaHA+T302tjvlsy4KzNoIoS46QZkxvOCCKqS2CcwV7UqLWMgIg",
            "jKPrwXTgwxlsSDczHkzZmN+xWkm355vHHxpy+DNyN0343Y3NF74ysnqh+gxtzqNPAwxy4tOUSiGv",
            "awYDsqLpcv834pKxRjLk1ZsMKuxE0FGyihE8DWIeSJgREczQpleP/EQU8/eKHDOMTEPg/lscTUDn",
            "QmLbKTOFY5CGahDl9dMGllPVJjCCAQIGCSqGSIb3DQEHAaCB9ASB8TCB7jCB6wYLKoZIhvcNAQwK",
            "AQKggbQwgbEwHAYKKoZIhvcNAQwBAzAOBAjBOIDvhO5uXQICCAAEgZDeCeMwxu5k+NQLDA1Za8Bh",
            "Mg2Xegzg9XGF2Qd4QIY6sZDYBjJd2/rlM7wdGOY+idqbrCnfMbEK8tcTyrSAUN2Wf6zE3e8sVGRH",
            "L8SkK4b37eSpYBBDd8/o6yWaTUEmntaGEP+092qKlkiFWFZGExbB6rCcwDfa1+roRXDw97KDsiMB",
            "EVxwFOAHeEXwunnw/M0xJTAjBgkqhkiG9w0BCRUxFgQUnAzklAotOHPtPBGjzgzdtVz72YcwOTAh",
            "MAkGBSsOAwIaBQAEFK0RW+C3myLaK0ftEzMrXp9pYA3OBBDtWbgq0PyNbb4DnArzQsZOAgIIAA==",
        ],
        .mallory: [
            "MIIDkgIBAzCCA1AGCSqGSIb3DQEHAaCCA0EEggM9MIIDOTCCAi8GCSqGSIb3DQEHBqCCAiAwggIc",
            "AgEAMIICFQYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQYwDgQIotgaObkeRrQCAggAgIIB6HfcQvLi",
            "v3Pmz/koXUIJzK42nXY2m0f7E+lyPOiHiumdhVqHmN/He26YCuhKFhxtotdUeg6Yc6iTfqhnJCxB",
            "/+Ha+2EdpICQyrSSkqDMzkK+6jK6Shd9yuF+LjIytUz1Rkx7SxueTVLsIVXHeF2xcf5WT0TUlkI/",
            "wKlZaDM7dT/bhXk+3E3mDKuy1rI1sCw0ezPLFAsgnfb9TFdUT5sFevzevY+J2viU37ZTypVJ+hhu",
            "EbD0v/yPE+6J4ABorHGql2pPWE6TACHukJja1FhdLoc0afcsLDuy+mwcYTyg+EMtsKGHrlq5A8gg",
            "Gzy+U5Ek6p6m2J/lZ2gjEPyirO0ojIJFNcK7CnKLvxaX4emWO/h27TTiFA6ka7PMo7TBhN/OeKY1",
            "vFGlOC/zV1HDJQ7NlTsFh7GMnMA/3kd9Sp5H+314D+7Xq0iqJkGUqCXKfQySc46BPIuXlC+MHi5m",
            "QurzAx2XvOZycTyWdMnMVeNfYR32rfWuhSaMCJtsJd/JUHTn2ej+aq+x/XBTkH+rJ+AopFyISVnG",
            "Y3sWCBrwLtV6k9+mHkuqsaH8dsHKLxX0fwGy7pDO93+CSMbUTqopP/c76w7cUqu7BWjTsBWKk97U",
            "84mf6jem/0yec17m6YnP2kg6JWZN/kADfpwyMIIBAgYJKoZIhvcNAQcBoIH0BIHxMIHuMIHrBgsq",
            "hkiG9w0BDAoBAqCBtDCBsTAcBgoqhkiG9w0BDAEDMA4ECHHS9aNYmCegAgIIAASBkOK9D1wLbc21",
            "WPQwCCOqH51N/MLcUXFNkkksJ+QzJhVIW7J3be/hv3jy83b5eE+QBW8BiCQIpkpgA86HEgdAyHXE",
            "vs1cMXn6GqmK1ugfeFgY3p3cVWlBXjXZk1XWBa7lYHPMw+9SeGmdNiEBXFF5BPXwbVaOIKnZJ3fl",
            "ger8SnhIXYy3RK+gW4PGCJYu3YhVTjElMCMGCSqGSIb3DQEJFTEWBBSNqSaABzOxsrSzj52Pv8Dc",
            "/u5WVDA5MCEwCQYFKw4DAhoFAAQU9ZMnI6ldV78lS8Jsd+yOauMHOqIEEFquLMPIy5IWtrwKUXAd",
            "NdQCAggA",
        ],
    ]
}
