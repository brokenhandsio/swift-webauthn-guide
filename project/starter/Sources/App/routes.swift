import Fluent
import Vapor

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
}