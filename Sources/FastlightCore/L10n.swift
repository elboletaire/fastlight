import FastlightL10n

// This module's strings, from Resources/<lang>.lproj/Core.strings(dict).
// Keys are the English text; tests check every key used here is in the
// tables. Keep keys as plain literals so they can find them.

/// `key` in the user's language; with arguments, a format for them.
func L(_ key: String, _ args: any CVarArg...) -> String {
    Localizer.current.string(key, table: "Core", args)
}

/// A count's phrase: `other` is the key, `one` the English singular.
func Lp(_ one: String, _ other: String, count: Int, _ args: any CVarArg...) -> String {
    Localizer.current.plural(one: one, other: other, count: count, table: "Core", args)
}

/// Marks a literal as a key, for strings looked up later with `L(name)`.
func L10nKey(_ key: String) -> String { key }
