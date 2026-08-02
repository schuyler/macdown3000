#!/usr/bin/env swift
//
//  macdown-ax-dump.swift
//  MacDown 3000
//
//  Accessibility diagnostic for Issue #545 (VoiceOver does not announce bold,
//  italic, underline, or strikethrough in the rendered preview).
//
//  This tool attaches to a running MacDown 3000, walks the accessibility tree
//  down to the preview's web area, and prints the text attributes WebKit is
//  exposing for every run of text it finds -- font name, underline,
//  strikethrough, and anything else present.
//
//  The point is to answer one question without needing VoiceOver: is WebKit
//  handing the accessibility layer correct attributes that VoiceOver simply
//  declines to speak, or are the attributes missing before VoiceOver ever
//  sees them? Those two answers imply completely different fixes.
//
//  USAGE
//
//      1. Launch MacDown 3000 and open Tools/accessibility-sample.md.
//      2. Make sure the preview pane is visible.
//      3. Run:  ./Tools/macdown-ax-dump.swift
//
//     The first run will ask for Accessibility permission. Grant it to
//     Terminal (System Settings -> Privacy & Security -> Accessibility),
//     then run the tool again.
//
//  OPTIONS
//
//      --pid <n>     Attach to a specific process instead of searching.
//      --verbose     Also dump every accessibility attribute on each element,
//                    plus the parameterized attributes it supports.
//      --raw         Print the full element tree, not just text-bearing nodes.
//
//  Optionally compile it for a faster start-up:
//
//      swiftc -O Tools/macdown-ax-dump.swift -o /tmp/macdown-ax-dump
//

import AppKit
import ApplicationServices
import Foundation

// MARK: - Options

struct Options
{
    var pid: pid_t?
    var verbose = false
    var raw = false
}

func parseOptions() -> Options
{
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())

    while let argument = arguments.first
    {
        arguments.removeFirst()
        switch argument
        {
        case "--verbose", "-v":
            options.verbose = true
        case "--raw":
            options.raw = true
        case "--pid":
            guard let raw = arguments.first, let value = pid_t(raw) else
            {
                fail("--pid requires a numeric process id")
            }
            arguments.removeFirst()
            options.pid = value
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            fail("unrecognized argument: \(argument)")
        }
    }
    return options
}

let usage = """
usage: macdown-ax-dump [--pid <n>] [--verbose] [--raw]

Dumps the accessibility text attributes WebKit exposes for MacDown 3000's
rendered preview. See the comment block at the top of this file for details.
"""

func fail(_ message: String) -> Never
{
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Accessibility helpers

/// Copy a plain attribute, returning nil for any error rather than
/// distinguishing between them -- absent and unreadable are equivalent here.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef?
{
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
    else { return nil }
    return value
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String?
{
    return attribute(element, name) as? String
}

func children(of element: AXUIElement) -> [AXUIElement]
{
    return attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
}

func role(of element: AXUIElement) -> String
{
    return stringAttribute(element, kAXRoleAttribute as String) ?? "(no role)"
}

func attributeNames(of element: AXUIElement) -> [String]
{
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

func parameterizedAttributeNames(of element: AXUIElement) -> [String]
{
    var names: CFArray?
    guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success
    else { return [] }
    return names as? [String] ?? []
}

/// Ask an element for the attributed string covering its whole value. This is
/// the same parameterized attribute VoiceOver uses to decide what to announce,
/// so whatever shows up here is the ceiling on what a screen reader can say.
func attributedString(of element: AXUIElement, length: Int) -> NSAttributedString?
{
    var range = CFRange(location: 0, length: length)
    guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

    var value: CFTypeRef?
    let error = AXUIElementCopyParameterizedAttributeValue(
        element,
        "AXAttributedStringForRange" as CFString,
        rangeValue,
        &value)
    guard error == .success else { return nil }
    return value as? NSAttributedString
}

// MARK: - Locating the preview

func findApplication(pid: pid_t?) -> (AXUIElement, String)
{
    if let pid = pid
    {
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        return (AXUIElementCreateApplication(pid), name)
    }

    let candidates = NSWorkspace.shared.runningApplications.filter { application in
        guard let identifier = application.bundleIdentifier else { return false }
        return identifier.lowercased().contains("macdown")
    }

    guard let application = candidates.first, let name = application.localizedName else
    {
        fail("""
            MacDown 3000 does not appear to be running.

            Launch it, open a document with formatted text, make sure the
            preview pane is visible, then run this tool again. If it is
            running under a bundle identifier without "macdown" in it, pass
            --pid explicitly.
            """)
    }
    return (AXUIElementCreateApplication(application.processIdentifier), name)
}

/// Depth-first search for the web area WebKit publishes for the preview.
/// Returns every match -- a document with no preview open, or several open
/// windows, are both worth reporting rather than silently picking one.
func findWebAreas(under element: AXUIElement, depth: Int = 0) -> [AXUIElement]
{
    guard depth < 64 else { return [] }

    if role(of: element) == "AXWebArea" { return [element] }
    return children(of: element).flatMap { findWebAreas(under: $0, depth: depth + 1) }
}

// MARK: - Reporting

/// Attributes worth calling out by name. Everything else still gets printed,
/// but these are the ones that decide whether Issue #545 is a WebKit problem
/// or a VoiceOver policy problem.
let interestingAttributes = [
    "AXFont",
    "AXUnderline",
    "AXUnderlineColor",
    "AXStrikethrough",
    "AXStrikethroughColor",
    "AXSuperscript",
    "AXHeadingLevel",
    "AXLink",
]

func describe(fontValue: Any) -> String
{
    guard let font = fontValue as? [String: Any] else { return "\(fontValue)" }

    let name = font["AXFontName"] as? String ?? "?"
    let family = font["AXFontFamily"] as? String ?? "?"
    let size = font["AXFontSize"] as? NSNumber

    var description = "name=\(name) family=\(family)"
    if let size = size { description += " size=\(size)" }

    // VoiceOver infers "bold" and "italic" from the resolved face, so a name
    // that carries neither is the single most likely explanation for silence.
    let lowercased = name.lowercased()
    var traits: [String] = []
    if lowercased.contains("bold") { traits.append("BOLD") }
    if lowercased.contains("italic") || lowercased.contains("oblique") { traits.append("ITALIC") }
    if !traits.isEmpty { description += "  <- \(traits.joined(separator: "+"))" }

    return description
}

func describe(attribute name: String, value: Any) -> String
{
    if name == "AXFont" { return describe(fontValue: value) }
    return "\(value)"
}

func report(textElement element: AXUIElement, options: Options, indent: String)
{
    let value = stringAttribute(element, kAXValueAttribute as String)
        ?? stringAttribute(element, kAXDescriptionAttribute as String)
        ?? ""
    guard !value.isEmpty else { return }

    let elementRole = role(of: element)
    let subrole = stringAttribute(element, kAXSubroleAttribute as String)
    let roleDescription = stringAttribute(element, "AXRoleDescription")

    print("\(indent)\(elementRole)", terminator: "")
    if let subrole = subrole { print(" [\(subrole)]", terminator: "") }
    if let roleDescription = roleDescription { print(" \"\(roleDescription)\"", terminator: "") }
    print()
    print("\(indent)  text: \(value.debugDescription)")

    if options.verbose
    {
        let names = attributeNames(of: element).sorted()
        print("\(indent)  attributes: \(names.joined(separator: ", "))")
        let parameterized = parameterizedAttributeNames(of: element).sorted()
        print("\(indent)  parameterized: \(parameterized.joined(separator: ", "))")
    }

    guard let attributed = attributedString(of: element, length: value.utf16.count) else
    {
        print("\(indent)  ** AXAttributedStringForRange unavailable on this element **")
        print()
        return
    }

    let full = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttributes(in: full, options: []) { attributes, range, _ in
        let substring = (attributed.string as NSString).substring(with: range)

        // Runs carrying no attributes at all are the interesting negative
        // result, so print them rather than skipping.
        let keys = attributes.keys.map { $0.rawValue }.sorted()
        let highlights = keys.filter { interestingAttributes.contains($0) }

        print("\(indent)  run \(substring.debugDescription)")
        if highlights.isEmpty
        {
            print("\(indent)    (no formatting attributes)")
        }
        for key in keys
        {
            guard let value = attributes[NSAttributedString.Key(rawValue: key)] else { continue }
            let marker = interestingAttributes.contains(key) ? "*" : " "
            print("\(indent)   \(marker) \(key): \(describe(attribute: key, value: value))")
        }
    }
    print()
}

func walk(_ element: AXUIElement, options: Options, depth: Int = 0)
{
    guard depth < 64 else { return }

    let indent = String(repeating: "  ", count: depth)
    let elementRole = role(of: element)
    let childElements = children(of: element)

    // Text-bearing leaves are the payload. Everything else is scaffolding and
    // only gets printed under --raw.
    let bearsText = childElements.isEmpty
        || elementRole == "AXStaticText"
        || elementRole == "AXHeading"

    if bearsText
    {
        report(textElement: element, options: options, indent: indent)
    }
    else if options.raw
    {
        print("\(indent)\(elementRole)")
    }

    for child in childElements
    {
        walk(child, options: options, depth: depth + 1)
    }
}

// MARK: - Entry point

let options = parseOptions()

// Spelled as a literal rather than kAXTrustedCheckOptionPrompt: that constant
// is imported as Unmanaged<CFString> on some SDKs and a plain CFString on
// others, and the literal compiles against both.
guard AXIsProcessTrustedWithOptions(
    ["AXTrustedCheckOptionPrompt": true] as CFDictionary) else
{
    fail("""
        This tool needs Accessibility permission to read another app's
        accessibility tree.

        A system prompt should have appeared. Grant access to Terminal (or
        whichever terminal you are using) in System Settings -> Privacy &
        Security -> Accessibility, then run this tool again.
        """)
}

let (application, applicationName) = findApplication(pid: options.pid)
print("Attached to \(applicationName)")

let webAreas = findWebAreas(under: application)
guard !webAreas.isEmpty else
{
    fail("""
        No AXWebArea found in \(applicationName).

        The preview pane is where the rendered HTML lives, so this usually
        means it is hidden. Open a document, make sure the preview is
        visible, and try again.
        """)
}

print("Found \(webAreas.count) web area(s)\n")
print(String(repeating: "=", count: 72))

for (index, webArea) in webAreas.enumerated()
{
    print("WEB AREA \(index + 1)")
    print(String(repeating: "=", count: 72))
    walk(webArea, options: options)
}

print(String(repeating: "=", count: 72))
print("""

What to look for:

  * A run of bold text should carry an AXFont whose name contains "Bold".
  * Italic text should carry a font name with "Italic" or "Oblique".
  * Underlined text should carry AXUnderline with a non-zero value.
  * Struck text should carry AXStrikethrough with a non-zero value.

If those attributes are present, WebKit is doing its job and VoiceOver is
choosing not to speak them -- migrating to WKWebView would expose the same
attributes and change nothing. If they are absent, the attributes are being
lost before VoiceOver ever sees them, and there is a real bug to chase.
""")
