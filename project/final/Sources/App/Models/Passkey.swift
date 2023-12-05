import Fluent
import Vapor
import WebAuthn

final class Passkey: Model, Content {
    static let schema = "passkeys"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "public_key")
    var publicKey: String

    @Field(key: "current_sign_count")
    var currentSignCount: UInt32

    @Parent(key: "user_id")
    var user: User

    init() {}

    init(id: String, publicKey: String, currentSignCount: UInt32, userID: UUID) {
        self.id = id
        self.publicKey = publicKey
        self.currentSignCount = currentSignCount
        self.$user.id = userID
    }

    convenience init(from credential: Credential, userID: UUID) {
        self.init(
            id: credential.id,
            publicKey: credential.publicKey.base64URLEncodedString().asString(),
            currentSignCount: credential.signCount,
            userID: userID
        )
    }
}

extension Passkey {
    struct Create: Content {
        let id: String
        let publicKey: String
        let currentSignCount: UInt32
        let userID: UUID
    }
}
