import UIKit

/// LDraw color palette — maps LDraw color codes to UIColor.
/// Based on the official LDConfig.ldr from LDraw.org.
/// Reference: https://www.ldraw.org/article/547.html
enum LDrawColorMap {

    /// Special LDraw color codes
    static let inheritColorCode: Int = 16   // Use parent color
    static let edgeColorCode: Int = 24      // Edge color (complement)

    /// Map an LDraw color code to a UIColor.
    /// Falls back to gray if code is unknown.
    static func uiColor(for code: Int) -> UIColor {
        if let hex = palette[code] {
            return uiColor(hex: hex)
        }
        return UIColor.systemGray
    }

    /// Map our internal LegoColor to the closest LDraw color code.
    /// Used when a piece's stored color should be applied to an LDraw model.
    static func ldrawCode(for legoColor: LegoColor) -> Int {
        switch legoColor {
        case .red: return 4              // Red
        case .blue: return 1             // Blue
        case .yellow: return 14          // Yellow
        case .green: return 2            // Green
        case .black: return 0            // Black
        case .white: return 15           // White
        case .gray: return 71            // Light Bluish Gray (modern LEGO gray)
        case .darkGray: return 72        // Dark Bluish Gray
        case .orange: return 25          // Orange
        case .brown: return 70           // Reddish Brown
        case .tan: return 19             // Tan
        case .darkBlue: return 272       // Dark Blue
        case .darkGreen: return 288      // Dark Green
        case .darkRed: return 320        // Dark Red
        case .lightBlue: return 9        // Light Blue
        case .lime: return 27            // Lime
        case .pink: return 5             // Light Pink
        case .purple: return 22          // Purple
        case .transparent: return 47     // Trans-Clear
        case .transparentBlue: return 33 // Trans-Dark Blue
        case .transparentRed: return 36  // Trans-Red
        }
    }

    // MARK: - Internal Palette (hex strings)

    /// Hex values from the official LDConfig.ldr
    private static let palette: [Int: String] = [
        0: "#05131D",   // Black
        1: "#0055BF",   // Blue
        2: "#257A3E",   // Green
        3: "#00838F",   // Dark Turquoise
        4: "#C91A09",   // Red
        5: "#FC97AC",   // Pink
        6: "#7E512B",   // Brown (Old Brown)
        7: "#9BA19D",   // Light Gray
        8: "#6D6E5C",   // Dark Gray
        9: "#B4D2E3",   // Light Blue
        10: "#4B9F4A",  // Bright Green
        11: "#55A5AF",  // Light Turquoise
        12: "#F2705E",  // Salmon
        13: "#FC97AC",  // Pink
        14: "#F2CD37",  // Yellow
        15: "#FFFFFF",  // White
        17: "#C2DAB8",  // Light Green
        18: "#FBE696",  // Light Yellow
        19: "#E4CD9E",  // Tan
        20: "#C9CAE2",  // Light Violet
        22: "#81007B",  // Purple
        23: "#2032B0",  // Dark Blue Violet
        25: "#FE8A18",  // Orange
        26: "#923978",  // Magenta
        27: "#BBE90B",  // Lime
        28: "#958A73",  // Dark Tan
        29: "#E4ADC8",  // Bright Pink
        30: "#A06EB9",  // Medium Lavender
        31: "#CDA4DE",  // Lavender
        68: "#F3CF9B",  // Very Light Orange
        69: "#CD6298",  // Bright Reddish Lilac
        70: "#582A12",  // Reddish Brown
        71: "#A0A5A9",  // Light Bluish Gray
        72: "#6C6E68",  // Dark Bluish Gray
        73: "#7B9AC4",  // Medium Blue
        74: "#9DB95A",  // Medium Green
        77: "#FECCCF",  // Light Pink
        78: "#F6D7B3",  // Light Nougat
        84: "#AA7D55",  // Medium Nougat
        85: "#3F3691",  // Medium Lilac
        86: "#7C503A",  // Light Brown
        89: "#1B2A34",  // Blue-Violet
        92: "#BB805A",  // Nougat
        100: "#F9B7A5", // Light Salmon
        110: "#26469A", // Violet
        112: "#4861AC", // Medium Violet
        115: "#B7D425", // Medium Yellowish Green
        118: "#9CD6CC", // Aqua
        120: "#DEEA92", // Light Yellowish Green
        125: "#F9A777", // Light Orange
        128: "#AD6140", // Dark Nougat
        151: "#A8AB9D", // Very Light Bluish Gray
        191: "#F8BB3D", // Bright Light Orange
        212: "#9FC3E9", // Bright Light Blue
        216: "#B31004", // Rust
        218: "#8E5597", // Reddish Lilac
        219: "#564E9D", // Lilac
        226: "#FFEC6C", // Bright Light Yellow
        232: "#77C9D8", // Sky Blue
        272: "#0A3463", // Dark Blue
        288: "#184632", // Dark Green
        295: "#A5A9B4", // Flat Silver
        297: "#AA7F2E", // Pearl Gold
        308: "#352100", // Dark Brown
        313: "#ABD9FF", // Maersk Blue
        320: "#720E0F", // Dark Red
        321: "#469BC3", // Dark Azure
        322: "#68C3E2", // Medium Azure
        323: "#D3F2EA", // Light Aqua
        326: "#E2F99A", // Yellowish Green
        330: "#77774E", // Olive Green
        335: "#88605E", // Sand Red
        351: "#F785B1", // Medium Dark Pink
        353: "#FF6D77", // Coral
        366: "#D67923", // Earth Orange
        373: "#75657D", // Sand Purple
        378: "#A0BCAC", // Sand Green
        379: "#6074A1", // Sand Blue
        450: "#B67B50", // Fabuland Brown
        462: "#FFA70B", // Medium Orange
        484: "#A95500", // Dark Orange
        503: "#BCB4A5", // Very Light Gray
        // Transparent colors
        32: "#000000",  // Trans-Black IR Lens
        33: "#0020A0",  // Trans-Dark Blue
        34: "#84B68D",  // Trans-Green
        35: "#D9E4A7",  // Trans-Bright Green
        36: "#C91A09",  // Trans-Red
        37: "#DF6695",  // Trans-Dark Pink
        38: "#FF800D",  // Trans-Neon Orange
        40: "#635F52",  // Trans-Black
        41: "#559AB7",  // Trans-Medium Blue
        42: "#C0FF00",  // Trans-Neon Green
        43: "#AEE9EF",  // Trans-Light Blue
        44: "#96709F",  // Trans-Bright Reddish Lilac
        45: "#FC97AC",  // Trans-Pink
        46: "#F5CD2F",  // Trans-Yellow
        47: "#FCFCFC",  // Trans-Clear
        52: "#A5A5CB",  // Trans-Purple
        54: "#DAB000",  // Trans-Neon Yellow
        57: "#F08F1C",  // Trans-Neon Orange
        // Chrome / pearl
        60: "#645A4C",  // Chrome Antique Brass
        61: "#6C96BF",  // Chrome Blue
        62: "#3CB371",  // Chrome Green
        63: "#AA4D8E",  // Chrome Pink
        64: "#1B2A34",  // Chrome Black
        134: "#764D3B", // Copper
        135: "#A0A0A0", // Pearl Light Gray
        137: "#5677BA", // Pearl Sand Blue
        142: "#DEAC66", // Pearl Light Gold
        148: "#484D48", // Pearl Dark Gray
        150: "#989B99", // Pearl Very Light Gray
        178: "#B4883E", // Flat Dark Gold
        179: "#898788", // Flat Silver
        183: "#F2F3F2", // Pearl White
        184: "#D60026", // Metallic Bright Red
        186: "#008E3C", // Metallic Dark Green
        189: "#AA7F2E", // Reddish Gold
        // Edge colors (complement)
        24: "#7F7F7F"
    ]

    private static func uiColor(hex: String) -> UIColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else {
            return UIColor.systemGray
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
