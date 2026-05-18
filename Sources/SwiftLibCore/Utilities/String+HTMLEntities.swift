import Foundation

extension String {
    private static let namedHTMLEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ndash": "\u{2013}", "mdash": "\u{2014}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "bull": "\u{2022}", "hellip": "\u{2026}", "trade": "\u{2122}",
        "copy": "\u{00A9}", "reg": "\u{00AE}", "deg": "\u{00B0}",
        "times": "\u{00D7}", "divide": "\u{00F7}", "minus": "\u{2212}",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "zwj": "\u{200D}", "zwnj": "\u{200C}",
        "Alpha": "\u{0391}", "Beta": "\u{0392}", "Gamma": "\u{0393}",
        "Delta": "\u{0394}", "Epsilon": "\u{0395}", "Zeta": "\u{0396}",
        "Eta": "\u{0397}", "Theta": "\u{0398}", "Iota": "\u{0399}",
        "Kappa": "\u{039A}", "Lambda": "\u{039B}", "Mu": "\u{039C}",
        "Nu": "\u{039D}", "Xi": "\u{039E}", "Omicron": "\u{039F}",
        "Pi": "\u{03A0}", "Rho": "\u{03A1}", "Sigma": "\u{03A3}",
        "Tau": "\u{03A4}", "Upsilon": "\u{03A5}", "Phi": "\u{03A6}",
        "Chi": "\u{03A7}", "Psi": "\u{03A8}", "Omega": "\u{03A9}",
        "alpha": "\u{03B1}", "beta": "\u{03B2}", "gamma": "\u{03B3}",
        "delta": "\u{03B4}", "epsilon": "\u{03B5}", "zeta": "\u{03B6}",
        "eta": "\u{03B7}", "theta": "\u{03B8}", "iota": "\u{03B9}",
        "kappa": "\u{03BA}", "lambda": "\u{03BB}", "mu": "\u{03BC}",
        "nu": "\u{03BD}", "xi": "\u{03BE}", "omicron": "\u{03BF}",
        "pi": "\u{03C0}", "rho": "\u{03C1}", "sigmaf": "\u{03C2}",
        "sigma": "\u{03C3}", "tau": "\u{03C4}", "upsilon": "\u{03C5}",
        "phi": "\u{03C6}", "chi": "\u{03C7}", "psi": "\u{03C8}",
        "omega": "\u{03C9}", "thetasym": "\u{03D1}", "upsih": "\u{03D2}",
        "piv": "\u{03D6}", "nabla": "\u{2207}", "part": "\u{2202}",
        "le": "\u{2264}", "ge": "\u{2265}", "ne": "\u{2260}",
        "equiv": "\u{2261}", "cong": "\u{2245}", "sim": "\u{223C}",
        "asymp": "\u{2248}", "prop": "\u{221D}", "infin": "\u{221E}",
        "sum": "\u{2211}", "prod": "\u{220F}", "int": "\u{222B}",
        "radic": "\u{221A}", "perp": "\u{22A5}", "ang": "\u{2220}",
        "and": "\u{2227}", "or": "\u{2228}", "cap": "\u{2229}",
        "cup": "\u{222A}", "sub": "\u{2282}", "sup": "\u{2283}",
        "nsub": "\u{2284}", "sube": "\u{2286}", "supe": "\u{2287}",
        "empty": "\u{2205}", "exist": "\u{2203}", "forall": "\u{2200}",
        "isin": "\u{2208}", "notin": "\u{2209}", "ni": "\u{220B}",
        "larr": "\u{2190}", "uarr": "\u{2191}", "rarr": "\u{2192}",
        "darr": "\u{2193}", "harr": "\u{2194}", "crarr": "\u{21B5}",
        "lArr": "\u{21D0}", "uArr": "\u{21D1}", "rArr": "\u{21D2}",
        "dArr": "\u{21D3}", "hArr": "\u{21D4}",
        "plusmn": "\u{00B1}", "sup1": "\u{00B9}", "sup2": "\u{00B2}",
        "sup3": "\u{00B3}", "frac14": "\u{00BC}", "frac12": "\u{00BD}",
        "frac34": "\u{00BE}", "micro": "\u{00B5}", "middot": "\u{00B7}",
        "para": "\u{00B6}", "sect": "\u{00A7}",
        "laquo": "\u{00AB}", "raquo": "\u{00BB}",
        "dagger": "\u{2020}", "Dagger": "\u{2021}",
        "permil": "\u{2030}", "euro": "\u{20AC}", "pound": "\u{00A3}",
        "yen": "\u{00A5}", "cent": "\u{00A2}", "curren": "\u{00A4}",
        "iexcl": "\u{00A1}", "iquest": "\u{00BF}", "brvbar": "\u{00A6}",
        "ordf": "\u{00AA}", "ordm": "\u{00BA}", "not": "\u{00AC}",
        "shy": "\u{00AD}", "macr": "\u{00AF}", "acute": "\u{00B4}",
        "cedil": "\u{00B8}", "uml": "\u{00A8}",
    ]

    public func decodingHTMLEntities() -> String {
        guard let regex = try? NSRegularExpression(pattern: "&(#x([0-9a-fA-F]+)|#(\\d+)|([a-zA-Z]+));") else {
            return self
        }
        var result = self
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }
            var replacement: String?

            if let hexRange = Range(match.range(at: 2), in: result) {
                let hexStr = String(result[hexRange])
                if let codePoint = UInt32(hexStr, radix: 16), let scalar = Unicode.Scalar(codePoint) {
                    replacement = String(scalar)
                }
            } else if let decRange = Range(match.range(at: 3), in: result) {
                let decStr = String(result[decRange])
                if let codePoint = UInt32(decStr), let scalar = Unicode.Scalar(codePoint) {
                    replacement = String(scalar)
                }
            } else if let nameRange = Range(match.range(at: 4), in: result) {
                let name = String(result[nameRange]).lowercased()
                replacement = Self.namedHTMLEntities[name]
            }

            if let replacement = replacement {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        return result
    }
}
