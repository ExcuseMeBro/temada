import Foundation
import Combine

// Deliberately not Codable/UserDefaults/Keychain-backed. Launch-only memory.
@MainActor final class APICredentials: ObservableObject {
    @Published var apiKey = ""
    var valid: Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && key.utf8.count <= 1024 && key.utf8.allSatisfy { (33...126).contains($0) }
    }
    func bootstrap(consent: Bool) throws -> Data {
        guard consent else { throw CredentialError.consent }
        guard valid else { throw CredentialError.invalid }
        var data = try JSONSerialization.data(withJSONObject: ["apiKey": apiKey.trimmingCharacters(in: .whitespacesAndNewlines)])
        data.append(10)
        guard data.count <= 4096 else { throw CredentialError.invalid }
        return data
    }
    enum CredentialError: Error { case consent, invalid }
}
