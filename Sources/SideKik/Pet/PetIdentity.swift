import SwiftUI

/// Definitions and themes for selectable pet companion personas powered by OpenPets
public struct PetIdentity: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let title: String
    public let description: String
    public let openPetsId: String
    public let primaryColorHex: String
    public let secondaryColorHex: String
    public let accentColorHex: String

    public init(
        id: String,
        name: String,
        title: String,
        description: String,
        openPetsId: String,
        primaryColorHex: String,
        secondaryColorHex: String,
        accentColorHex: String
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.description = description
        self.openPetsId = openPetsId
        self.primaryColorHex = primaryColorHex
        self.secondaryColorHex = secondaryColorHex
        self.accentColorHex = accentColorHex
    }

    public static let azure = PetIdentity(
        id: "azure",
        name: "Azure",
        title: "Tiny Blue Dragon",
        description: "A tiny blue dragon with small wings and a friendly snout.",
        openPetsId: "azure-openpets",
        primaryColorHex: "#2563EB",
        secondaryColorHex: "#60A5FA",
        accentColorHex: "#DBEAFE"
    )

    public static let patchi = PetIdentity(
        id: "patchi",
        name: "Patchi",
        title: "Leafy Red Panda",
        description: "A tiny red panda with leafy head accents and a ringed tail.",
        openPetsId: "patchi-openpets",
        primaryColorHex: "#EA580C",
        secondaryColorHex: "#FB923C",
        accentColorHex: "#FFEDD5"
    )

    public static let prickle = PetIdentity(
        id: "prickle",
        name: "Prickle",
        title: "Potted Cactus",
        description: "A tiny potted cactus with a pink flower.",
        openPetsId: "prickle-openpets",
        primaryColorHex: "#16A34A",
        secondaryColorHex: "#4ADE80",
        accentColorHex: "#DCFCE7"
    )

    public static let penguin = PetIdentity(
        id: "penguin",
        name: "Penguin",
        title: "Cozy Penguin",
        description: "A cozy pixel penguin bundled in a blue scarf.",
        openPetsId: "penguin-openpets",
        primaryColorHex: "#0284C7",
        secondaryColorHex: "#38BDF8",
        accentColorHex: "#E0F2FE"
    )

    public static let woolbell = PetIdentity(
        id: "woolbell",
        name: "Woolbell",
        title: "Fluffy Ram Lamb",
        description: "A fluffy ram lamb with curled horns and a small bell collar.",
        openPetsId: "woolbell-openpets",
        primaryColorHex: "#F59E0B",
        secondaryColorHex: "#FCD34D",
        accentColorHex: "#FEF3C7"
    )

    public static let sporecap = PetIdentity(
        id: "sporecap",
        name: "Sporecap",
        title: "Cozy Mushroom",
        description: "A cozy mushroom pet with a red spotted cap and leafy arms.",
        openPetsId: "sporecap-openpets",
        primaryColorHex: "#DC2626",
        secondaryColorHex: "#F87171",
        accentColorHex: "#FEE2E2"
    )

    public static let allPets: [PetIdentity] = [
        .azure,
        .patchi,
        .penguin,
        .prickle,
        .woolbell,
        .sporecap
    ]

    public static func find(byId id: String) -> PetIdentity {
        let clean = id.lowercased()
        if clean == "sparky" || clean == "fenne" { return .azure }
        if clean == "pixelcat" || clean == "yuzu" { return .patchi }
        if clean == "ghosty" || clean == "barnaby" { return .penguin }
        if clean == "robo" || clean == "banana" { return .prickle }
        return allPets.first(where: { $0.id == clean || $0.openPetsId == clean }) ?? .azure
    }
}

extension Color {
    public init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (37, 99, 235)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1.0)
    }
}
