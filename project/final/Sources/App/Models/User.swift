import Vapor
import Fluent

final class User: Model, ModelSessionAuthenticatable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    init() { }

    init(id: UUID? = nil, username: String) {
        self.id = id
        self.username = username
    }
}
