import Fluent

struct CreatePasskey: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("passkeys")
            .id()
            .field("public_key", .string, .required)
            .field("current_sign_count", .uint32, .required)
            .field("user_id", .uuid, .required, .references("users", "id"))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("passkeys").delete()
    }
}
