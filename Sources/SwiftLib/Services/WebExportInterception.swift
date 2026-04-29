import CoreFoundation
import Foundation
import SwiftLibCore

struct WebExportSnapshot: Decodable, Sendable {
    struct Candidate: Decodable, Hashable, Sendable {
        let url: String
        let label: String?
        let hint: String?
    }

    let candidates: [Candidate]
    let loginRequired: Bool
}

struct InterceptedWebExport: Hashable, Sendable {
    enum Format: String, Sendable {
        case ris
        case bibTeX
        case cnki
    }

    let format: Format
    let payload: String
    let sourceURL: String
    let mimeType: String?
    let fileName: String?
}

enum WebExportInterception {
    static let snapshotScript = #"""
    (() => {
      const candidates = [];
      const seen = new Set();
      const exportTextPattern = /(ris|bibtex|refworks|endnote|noteexpress|citation|export|引用|导出|参考文献)/i;

      const normalizeText = (value) => (value || '').replace(/\s+/g, ' ').trim();
      const pushCandidate = (href, label, hint) => {
        if (!href) return;
        try {
          const absolute = new URL(href, location.href).toString();
          const key = absolute.toLowerCase();
          if (seen.has(key)) return;
          const labelText = normalizeText(label);
          const hintText = normalizeText(hint);
          const combined = [absolute, labelText, hintText].join(' ');
          if (!exportTextPattern.test(combined)) return;
          seen.add(key);
          candidates.push({
            url: absolute,
            label: labelText || null,
            hint: hintText || null
          });
        } catch {}
      };

      for (const anchor of document.querySelectorAll('a[href]')) {
        pushCandidate(
          anchor.getAttribute('href'),
          anchor.innerText || anchor.textContent,
          anchor.getAttribute('title') || anchor.getAttribute('aria-label')
        );
      }

      for (const node of document.querySelectorAll('[data-export-url], [data-download-url], [data-href], button, [role="button"]')) {
        pushCandidate(
          node.getAttribute('data-export-url') || node.getAttribute('data-download-url') || node.getAttribute('data-href'),
          node.innerText || node.textContent,
          node.getAttribute('title') || node.getAttribute('aria-label')
        );
      }

      const bodyText = normalizeText(document.body?.innerText).slice(0, 4000);
      const loginSignals = [
        '登录', '登入', '统一认证', '机构登录', '校园网',
        'sign in', 'login', 'institutional login', 'shibboleth', 'captcha'
      ];
      const loginRequired =
        !!document.querySelector('input[type="password"], form[action*="login" i], a[href*="login" i], a[href*="shibboleth" i]') ||
        loginSignals.some((token) => bodyText.toLowerCase().includes(token.toLowerCase()));

      return JSON.stringify({ candidates, loginRequired });
    })();
    """#

    static func detectFormat(
        url: URL?,
        mimeType: String? = nil,
        fileName: String? = nil,
        label: String? = nil,
        hint: String? = nil
    ) -> InterceptedWebExport.Format? {
        let lowerMime = mimeType?.lowercased() ?? ""
        let lowerURL = url?.absoluteString.lowercased() ?? ""
        let lowerFileName = fileName?.lowercased() ?? ""
        let lowerLabel = label?.lowercased() ?? ""
        let lowerHint = hint?.lowercased() ?? ""
        let combined = [lowerURL, lowerFileName, lowerMime, lowerLabel, lowerHint].joined(separator: " ")

        if combined.contains("research-info-systems")
            || lowerURL.hasSuffix(".ris")
            || lowerFileName.hasSuffix(".ris")
            || combined.contains("refworks")
            || combined.contains("endnote")
            || combined.contains("noteexpress")
            || combined.contains("refman") {
            return .ris
        }

        if combined.contains("bibtex")
            || combined.contains("application/x-bibtex")
            || lowerURL.hasSuffix(".bib")
            || lowerFileName.hasSuffix(".bib") {
            return .bibTeX
        }

        if combined.contains("cnki")
            || combined.contains("download.aspx")
            || combined.contains("downloadcitation")
            || combined.contains("引用导出")
            || combined.contains("导出") {
            return .cnki
        }

        return nil
    }

    static func decodeText(data: Data, response: URLResponse?) -> String? {
        if let text = String(data: data, encoding: .utf8)?.swiftlib_nilIfBlank {
            return text
        }
        if let text = String(data: data, encoding: .unicode)?.swiftlib_nilIfBlank {
            return text
        }
        if let text = String(data: data, encoding: .utf16)?.swiftlib_nilIfBlank {
            return text
        }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: gb18030)?.swiftlib_nilIfBlank {
            return text
        }

        if let lowerEncoding = response?.textEncodingName?.lowercased(),
           lowerEncoding.contains("gb"),
           let text = String(data: data, encoding: gb18030)?.swiftlib_nilIfBlank {
            return text
        }

        return nil
    }

    static func parseReference(from export: InterceptedWebExport) -> Reference? {
        switch export.format {
        case .ris:
            return RISImporter.parse(export.payload).first
                ?? CNKIExportParser.parse(export.payload).first
        case .bibTeX:
            return BibTeXImporter.parse(export.payload).first
        case .cnki:
            return CNKIExportParser.parse(export.payload).first
                ?? RISImporter.parse(export.payload).first
                ?? BibTeXImporter.parse(export.payload).first
        }
    }
}
