import NIOSSL
import Fluent
import FluentSQLiteDriver
import Leaf
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    app.databases.use(DatabaseConfigurationFactory.sqlite(.file("db.sqlite")), as: .sqlite)

    app.middleware.use(app.sessions.middleware)
    app.middleware.use(User.asyncSessionAuthenticator())

    app.migrations.add(CreateUser())
    app.migrations.add(CreatePasskey())

    try await app.autoMigrate()

    app.views.use(.leaf)

    try routes(app)
}
