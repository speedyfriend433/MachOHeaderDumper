# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

-   **TabView Navigation:** Replaced the segmented picker with a more scalable `TabView` for main screen navigation, separating content into "Dump", "Structure", "Symbols", and "Dynamic" categories.
-   **Enhanced UI Rows:** Implemented `InfoRow`, a reusable view component with SF Symbols and improved text hierarchy for a polished appearance in navigation lists.
-   **Static Analysis - Strings:** Added a "Strings" view to display and search all null-terminated C strings found in common sections (`__cstring`, `__objc_methname`, etc.).
-   **Static Analysis - Function Starts:** Added a "Func Starts" view to display the list of function start addresses decoded from the `LC_FUNCTION_STARTS` load command.
-   **Static Analysis - Selector References:** Added a "Sel Refs" view to display all Objective-C selector references found in `__objc_selrefs`, grouped by selector name.
-   **Static Analysis - Categories:** The app now correctly parses and displays Objective-C categories, even if their target class is external to the binary. Includes a dedicated "Categories" view.
-   **Header Generation for Categories:** The Objective-C header generator now produces correct `@interface TargetClass (CategoryName)` definitions and forward-declares external classes.
-   **Search Functionality:** Added searchable modifiers (`.searchable()`) to the Symbols, Strings, and Categories views for easy filtering.
-   **Interactive Symbol Detail View:** Tapping a symbol in the "Symbols" list now pushes a new detail view showing all information for that symbol (`value`, `type`, `section`, etc.).
-   **Enhanced Empty/Unavailable States:** Implemented a more informative `ContentUnavailableView` to provide better user feedback when data for a specific section is not found.

### Changed

-   **Refined Pointer Resolution:** Reworked the VM address to file offset conversion logic to correctly handle Position-Independent Executables (PIE) by normalizing addresses relative to the Mach-O image base address.
-   **Improved Objective-C Parsing:**
    -   Implemented a robust two-pass extraction process to reliably resolve superclasses and merge categories.
    *   Correctly uses the `entsize` from list headers (`objc_list_header_t`) for iterating through methods and properties, improving accuracy.
    *   Added detection for class properties (`+ (property)`) defined on metaclasses.
    *   Added heuristics for `instancetype` in the header generator.
    *   Improved handling for Objective-C types with protocol conformances (e.g., `id<MyProtocol>`).
-   **Refined Load Command Parsing:** Added detailed parsing and display for a wider range of load commands, including `LC_BUILD_VERSION`, `LC_SOURCE_VERSION`, `LC_FUNCTION_STARTS`, and dylib versions.
-   **Refined UI Layout:** Improved overall padding, spacing, and layout consistency using `.insetGrouped` list styles and a dedicated top bar for file info.
-   **Consolidated `onChange` Logic:** Replaced multiple `.onChange` modifiers in the main view with a single, more stable trigger (`processingUpdateId`) to prevent SwiftUI compiler timeouts.

### Fixed

-   **Swift Demangling Reliability:** Replaced the unreliable `dlopen`/`dlsym` approach with a bundled pure-Swift demangler library (`oozoofrog/SwiftDemangle`), ensuring Swift symbols are always demangled correctly regardless of the binary's architecture or code signature.
-   **Pointer Arithmetic Crash:** Fixed a "Negative value is not representable" fatal error by using correct signed arithmetic when resolving relative pointers in Swift metadata.
-   **"Empty" Header Bug:** Fixed an issue where a header file would not be generated if the binary only contained protocols or categories but no classes.
-   **Numerous SwiftUI Compiler Errors:** Resolved a series of "unable to type-check this expression" and "no dynamic member" errors by refactoring complex views into smaller, independent structs and `@ViewBuilder` functions.
-   **Exhaustive Switch Errors:** Corrected all `switch` statements to be exhaustive and match their corresponding `enum` definitions after refactoring.

## [1.2.0] - 2025-07-11

### Added

-   **Initial Release:**
    *   Core application structure with SwiftUI.
    *   TrollStore-focused file import using `UIDocumentPickerViewController`.
    *   Manual Mach-O parser for `arm64` (Thin and Fat binaries).
    *   Basic Objective-C header dumping for classes and protocols.
    *   Basic Swift type name extraction (mangled).
    *   Views for basic Mach-O info, load commands, and symbols.
    *   DyldInfo parser for rebase, bind, and export operations.
