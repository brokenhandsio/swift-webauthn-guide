import Fluent
import Vapor
import WebAuthn

func routes(_ app: Application) throws {
    app.get { req async throws in
        try await req.view.render("index")
    }

    app.get("private") { req in
        let user = try req.auth.require(User.self)
        return req.view.render("private", ["user": user])
    }

    app.get("logout") { req in
        req.auth.logout(User.self)
        return req.redirect(to: "/")
    }

    app.get("register") { req in
        // Create and login user
        let username = try req.query.get(String.self, at: "username")
        let user = User(username: username)
        try await user.create(on: req.db)
        req.auth.login(user)

        // Generate registration options
        let options = req.webAuthn.beginRegistration(user:
            .init(
                id: try [UInt8](user.requireID().uuidString.utf8),
                name: user.username,
                displayName: user.username
            )
        )

        // Also pass along challenge because we need it later
        req.session.data["registrationChallenge"] = Data(options.challenge).base64EncodedString()

        return CreateCredentialOptions(publicKey: options)
    }

    app.post("passkeys", use: { req in
        // Obtain the user we're registering a credential for
        let user = try req.auth.require(User.self)

        // Obtain the challenge we stored for this session
        guard let challengeEncoded = req.session.data["registrationChallenge"],
            let challenge = Data(base64Encoded: challengeEncoded) else {
            throw Abort(.badRequest, reason: "Missing registration session ID")
        }

        // Delete the challenge to prevent attackers from reusing it
        req.session.data["registrationChallenge"] = nil

        // Verify the credential the client sent us
        let credential = try await req.webAuthn.finishRegistration(
            challenge: [UInt8](challenge),
            credentialCreationData: req.content.decode(RegistrationCredential.self),
            confirmCredentialIDNotRegisteredYet: { _ in true}
        )

        try await Passkey(from: credential, userID: user.requireID()).save(on: req.db)

        return HTTPStatus.ok
    })
}

struct CreateCredentialOptions: Encodable, AsyncResponseEncodable {
    let publicKey: PublicKeyCredentialCreationOptions

    func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.contentType = .json
        return try Response(status: .ok, headers: headers, body: .init(data: JSONEncoder().encode(self)))
    }
}
