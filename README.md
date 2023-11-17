# Going passwordless with Vapor and Passkeys

### Introduction Structure:

In this tutorial we will explore Passkeys. To be more specific, we'll explore how we can integrate the Swift WebAuthn library into a server-side Swift app. The process of registering and authenticating using Passkeys is pretty simple, but requires some back and forth between client and server. Therefor this tutorial is split into two separate parts:

1. [Passkey Registration]()
2. [Passkey Authentication]()

To avoid starting completely from scratch and turning this 2-part blog article into a whole book, I prepared a small starter template which you can [download here]().

Today I'll show you an example implementation for a standalone Passkey login, however it is also possible to integrate webauthn-swift along an existing, password-based, login.

What are Passkeys? Others already did a good job at explaining this, so why reinvent the wheel? Here is a quote from [passkeys.com](https://passkeys.com):

> Passkeys are the new standard to authenticate on the web.
> Passkeys are a safer and easier replacement for passwords. With passkeys, users can sign in to apps and websites with a biometric sensor (such as a fingerprint or facial recognition), PIN, or pattern, freeing them from having to remember and manage passwords.

To read more about Passkeys and how they work I recommend the following two resources:

- Introduction: https://webauthn.guide/
- Details: https://w3c.github.io/webauthn/

## Act 1 - Setup

#### Setting up the frontend

Passkeys are integrated into our browsers. Through a JavaScript api exposed by the browsers we trigger the Passkey prompts.

*Safari Passkey prompt:*
<img width="1728" alt="passkey_prompt_2" src="https://github.com/brokenhandsio/swift-webauthn-guide/assets/44228394/e3d8bb98-2336-450c-b845-d94623dbf0a5">


*Another example - 1Password prompt:*
<img width="1728" alt="passkey_prompt_1" src="https://github.com/brokenhandsio/swift-webauthn-guide/assets/44228394/9d155c1a-bd95-42a6-ab86-233538065078">


These two prompts are the result of calling `navigator.credentials.create(...)` and `navigator.credentials.get(...)`.

To get a better understanding let's quickly play around with this API. Go to `https://swift.org`, open the developer panel of your browser and switch to the JavaScript console. Create the following variable:

```JavaScript
const publicKeyCredentialCreationOptions = {
    challenge: Uint8Array.from(
        "randomStringFromServer", c => c.charCodeAt(0)),
    rp: {
        name: "Swift",
        id: "swift.org",
    },
    user: {
        id: Uint8Array.from(
            "UZSL85T9AFC", c => c.charCodeAt(0)),
        name: "me@example.com",
        displayName: "FooBar",
    },
    pubKeyCredParams: [{alg: -7, type: "public-key"}],
    authenticatorSelection: {
        authenticatorAttachment: "cross-platform",
    },
    timeout: 60000,
    attestation: "direct"
};
```

Don't worry, you don't have to understand it's content. In fact the Swift WebAuthn library will create this for you automatically. Now calling the Passkeys API with our newly created `publicKeyCredentialCreationOptions` will prompt you to create a new Passkey:

```JavaScript
const credential = await navigator.credentials.create({
    publicKey: publicKeyCredentialCreationOptions
});
```

#### Setting up the Relying Party 

If you haven't already downloaded the starter template, you should do so now. To start add the Swift WebAuthn library to your `Package.swift`:

```Swift
dependencies: [
    // ...
    .package(url: "https://github.com/swift-server/webauthn-swift.git", from: "1.0.0-alpha")
],

// ...

targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "WebAuthn", package: "webauthn-swift")
// ...
]
```

In our backend app we need to keep a `WebAuthnManager`, the core of the Swift WebAuthn library, instance somewhere. If you're using Vapor you could extend `Request` with a `webAuthn` property which allows us to easily access it in the route handlers. Add this somewhere in your code, e.g. in a new file `Request+webAuthn.swift`:

```swift
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
```

Here we configure 3 things:
1. The `relyingPartyID` identifies your app based solely on the domain (not the scheme, port, or path) it can be accessed on. All created Passkeys will be scoped to this identifier. That means a Passkey created at `example.org` can only be used on the same domain. This prevents other websites from talking to random Passkeys. However this also means if you want to change your domain at some point all users need to re-create their Passkeys!
2. The `relyingPartyName` is just a friendly name shown to the user when registering or logging in. 
3. The `relyingPartyOrigin` works similar to the relying party id, but [serves as an additional layer of protection](https://w3c.github.io/webauthn/#sctn-validating-origin). Here we need to specify the whole origin. In our case it's the scheme `https://` + the relying party id + the port `:8080`

Great, that's everything we need to get started.
## Act 2 - Registration

From the UI perspective we only need three components: Two buttons and a text field for entering a username! No password field needed... that's why we're here after all! Let's start with building a quick registration form in HTML. Insert the following form into `Resources/Views/index.leaf` just after `<!-- Form -->`:

```html
<form id="registerForm">
    <input id="username" type="text" />
    <button type="submit">Register</button>
</form>
```

The app should now return you a blank HTML form at http://localhost:8080/.
### Planning ahead

Before we jump into the business logic let's write down what we need:
1. When a user clicks the "Register" button we will notify our server about a new registration attempt.
2. The server will put together a few information and send these back to the client (/browser).
3. The client will take these information and toss them into the `create(parseCreationOptionsFromJSON(...))` JavaScript function which will trigger the Passkey prompt. The returned value of this function is our brand new Passkey! Great! 
4. Before opening our first beer we quickly need to send our new Passkey back to the server, verify it and persist it in a database.

It sounds like a lot of work, but it's actually pretty simple.

### Bringing `<form>` to life

Alright let's start with step one. Add this after the closing `</form>` tag from the previous step:

```HTML
<script type="module">
  // import WebAuthn wrapper
  import { create, parseCreationOptionsFromJSON } from 'https://cdn.jsdelivr.net/npm/@github/webauthn-json@2.1.1/dist/esm/webauthn-json.browser-ponyfill.js';

  // Get a reference to our registration form
  const registerForm = document.getElementById("registerForm");

  // Listen for the form's "submit" event
  registerForm.addEventListener("submit", async function(event) {
    event.preventDefault();

    // Get the username
    const username = document.getElementById("username").value;

    // Send request to server
    const registerResponse = await fetch('/register?username=' + username);

    // Parse response as json and pass into wrapped WebAuthn API
    const registerResponseJSON = await registerResponse.json();
    const passkey = await create(parseCreationOptionsFromJSON(registerResponseJSON));

    // Send passkey to server
    const createPasskeyResponse = await fetch('/passkeys', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(passkey)
    });

    location.href = "/private";
  });
</script>
```

First we add a third-party script developed by GitHub which adds user-friendly wrappers on top of the original WebAuthn APIs `navigator.credentials.create` and `navigator.credentials.get`. This is just for convenience and not mandatory! If you don't want to use it you'll have to deserialise some of the `registrationOptions` properties since the original API expects a few "raw" byte arrays. Using the wrapper we can simply pass in the JSON response from our server - neat! The official WebAuthn API will [support this out of the box at some point](https://w3c.github.io/webauthn/#sctn-parseCreationOptionsFromJSON), but for now we depend on GitHub's "webauthn-json" script.

Our script will listen for the form's `submit` event. On submit it sends a `/signup` request to our backend and passes the JSON response to `create(parseCreationOptionsFromJSON(...))` thus triggering the browsers Passkey prompt.

On the server side of things we still need to add the endpoint we just called in the JavaScript code. In a Vapor app you'd have to register a new route in `routes.swift`:

```swift
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
```

On `/register` this creates a new user and calls the `beginRegistration` function with the newly created user. This will give us a set of options which we send back to the client. Additionally we store the challenge in a cookie because we'll need it later when verifying the new Passkey. If you inspect the returned options you'll notice that these are the options you manually entered in your browser's JavaScript console at the beginning of this blog post!

The WebAuthn API expects the options inside a property named `publicKey`. That's why we return an instance of `CreateCredentialOptions` - a type which doesn't exist yet. So let's create and conform it to `AsyncResponseEncodable` so we can easily return it an a Vapor route handler:

```swift
struct CreateCredentialOptions: Encodable, AsyncResponseEncodable {
    let publicKey: PublicKeyCredentialCreationOptions

    func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.contentType = .json
        return try Response(status: .ok, headers: headers, body: .init(data: JSONEncoder().encode(self)))
    }
}
```

Time to give it a try: Entering a username and clicking "Register" should trigger the prompt asking you to create a new Passkey! However nothing will happen afterwards. Let's fix that!

### Verifying and persisting the Passkey

After the browser created the Passkey we need to send it to our server, verify everything went smoothly and persist it somewhere.

First, let's send the Passkey to our server. Add this below `const registrationCredential` in our JS script:

```JS
const createPasskeyResponse = await fetch('/passkeys', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(passkey)
});
```

On the server we handle the request like this:

```swift
// Example implementation for a Vapor app
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
```

Congratulations, you just built a Passkey registration! Entering a username and hitting "Register" should now redirect you to a private page. The passkey should also appear in your database (in the passkeys table) now.
