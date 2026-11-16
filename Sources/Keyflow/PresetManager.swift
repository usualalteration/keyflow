import Foundation

struct FavoriteConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var config: Configuration
}

/// Genre presets live in `GenreProfile`; this manager stores the user's favorite configurations
/// (including the random seed, so an arrangement can be reproduced).
final class PresetManager: ObservableObject {
    @Published private(set) var favorites: [FavoriteConfig] = []
    private let key = "keyflow.favorites.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: "keyflow.favorites.v1"),
           let f = try? JSONDecoder().decode([FavoriteConfig].self, from: data) {
            favorites = f
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(name: String, config: Configuration) {
        let n = name.trimmingCharacters(in: .whitespaces)
        favorites.append(FavoriteConfig(name: n.isEmpty ? "\(config.genre.rawValue) · seed \(config.seed)" : n,
                                        config: config))
        save()
    }

    func remove(_ fav: FavoriteConfig) {
        favorites.removeAll { $0.id == fav.id }
        save()
    }
}
