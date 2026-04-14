import Foundation
import MusicTheory

public enum InversionPolicy: Hashable, Codable, Sendable {
    case rootPosition
    case keepClose
    case nearest
    case fixed(Int)
}

public enum TensionPolicy: Hashable, Codable, Sendable {
    case none
    case diatonicSeventh
    case diatonicExtensions(maxDegree: Int)
    case custom([Interval])
}

public struct ChordRecipe: Hashable, Codable, Sendable {
    public let root: NoteName?
    public let scaleDegree: Int?
    public let chordType: ChordType
    public let inversionPolicy: InversionPolicy
    public let tensionPolicy: TensionPolicy

    public init(
        root: NoteName? = nil,
        scaleDegree: Int? = nil,
        chordType: ChordType,
        inversionPolicy: InversionPolicy = .nearest,
        tensionPolicy: TensionPolicy = .none
    ) {
        self.root = root
        self.scaleDegree = scaleDegree
        self.chordType = chordType
        self.inversionPolicy = inversionPolicy
        self.tensionPolicy = tensionPolicy
    }
}

