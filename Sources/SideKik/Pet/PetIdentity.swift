import SwiftUI

/// Definitions and themes for selectable pet companion personas
public struct PetIdentity: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let title: String
    public let description: String
    public let primaryColorHex: String
    public let secondaryColorHex: String
    public let accentColorHex: String

    public init(
        id: String,
        name: String,
        title: String,
        description: String,
        primaryColorHex: String,
        secondaryColorHex: String,
        accentColorHex: String
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.description = description
        self.primaryColorHex = primaryColorHex
        self.secondaryColorHex = secondaryColorHex
        self.accentColorHex = accentColorHex
    }

    public static let sparky = PetIdentity(
        id: "sparky",
        name: "Sparky",
        title: "Cyber Fox",
        description: "Energetic digital kitsune with alert ears and warm amber aura.",
        primaryColorHex: "#FF7A00",
        secondaryColorHex: "#FFA94D",
        accentColorHex: "#FFF3BF"
    )

    public static let ghosty = PetIdentity(
        id: "ghosty",
        name: "Ghosty",
        title: "Ambient Spirit",
        description: "Gentle pastel spirit with soft translucent float and blushing expressions.",
        primaryColorHex: "#B197FC",
        secondaryColorHex: "#D0BFFF",
        accentColorHex: "#E5DBFF"
    )

    public static let pixelCat = PetIdentity(
        id: "pixelcat",
        name: "Pixel Cat",
        title: "Retro Neko",
        description: "16-bit retro arcade buddy with twitching ears and wagging tail.",
        primaryColorHex: "#4DABF7",
        secondaryColorHex: "#74C0FC",
        accentColorHex: "#D0EBFF"
    )

    public static let robo = PetIdentity(
        id: "robo",
        name: "Robo-Clicky",
        title: "AI Orb",
        description: "Classic cybernetic floating sphere with expressive neon visor.",
        primaryColorHex: "#20C997",
        secondaryColorHex: "#38D9A9",
        accentColorHex: "#63E6BE"
    )

    public static let allPets: [PetIdentity] = [.sparky, .ghosty, .pixelCat, .robo]

    public static func find(byId id: String) -> PetIdentity {
        allPets.first(where: { $0.id == id }) ?? .sparky
    }
}
