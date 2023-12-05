import Vapor
import WebAuthn

extension Request {
    var webAuthn: WebAuthnManager {
        WebAuthnManager(
            config: WebAuthnManager.Config(
                relyingPartyID: "localhost",
                relyingPartyName: "Vapor Passkey Tutorial",
                relyingPartyOrigin: "http://localhost:8080"
            )
        )
    }
}
