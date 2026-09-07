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

    public static let sparky = PetIdentity(
        id: "sparky",
        name: "Fenne",
        title: "Cyber Fox",
        description: "Lively orange fox with oversized ears, curious trot, and warm amber aura.",
        openPetsId: "fenne-fox",
        primaryColorHex: "#FF7A00",
        secondaryColorHex: "#FFA94D",
        accentColorHex: "#FFF3BF"
    )

    public static let pixelCat = PetIdentity(
        id: "pixelcat",
        name: "Yuzu",
        title: "Golden Kitten",
        description: "Tiny golden tabby kitten with bright round eyes, soft paws, and playful bounce.",
        openPetsId: "yuzu-golden-kitten",
        primaryColorHex: "#F59F00",
        secondaryColorHex: "#FFD43B",
        accentColorHex: "#FFF9DB"
    )

    public static let ghosty = PetIdentity(
        id: "ghosty",
        name: "Barnaby",
        title: "OpenPets Bear",
        description: "The iconic OpenPets companion bear with gentle gestures and friendly guidance.",
        openPetsId: "default-pet",
        primaryColorHex: "#4C6EF5",
        secondaryColorHex: "#748FFC",
        accentColorHex: "#EDF2FF"
    )

    public static let robo = PetIdentity(
        id: "robo",
        name: "Banana",
        title: "Skater Buddy",
        description: "Cheerful curved yellow banana on a skateboard wearing a red cap and sneakers.",
        openPetsId: "banana-skater",
        primaryColorHex: "#FCC419",
        secondaryColorHex: "#FFE066",
        accentColorHex: "#FFF9DB"
    )

    public static let allPets: [PetIdentity] = [.sparky, .pixelCat, .ghosty, .robo]

    public static func find(byId id: String) -> PetIdentity {
        allPets.first(where: { $0.id == id || $0.openPetsId == id }) ?? .sparky
    }
}
