# MachOHeaderDumper for iOS 

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**A native iOS application to dump Objective-C headers, Swift type information, symbols, and structural details from Mach-O binaries directly on-device.** Inspired by `class-dump`, but built entirely in Swift for iOS.

---

## Overview

MachOHeaderDumper provides developers, security researchers, and tweak developers with a powerful on-device tool to inspect iOS applications, frameworks, and dynamic libraries.

**Core Capabilities:**

*   **Objective-C Header Dumping:** Extracts `@interface`, `@protocol`, `@property`, and `@method` declarations similar to `class-dump`.
*   **Swift Type Extraction:** Identifies Swift classes, structs, enums, and protocols present in the binary metadata. Attempts symbol demangling using `dlsym`.
*   **Mach-O Structure Analysis:** Displays detailed header information, load commands (including segments, sections, dylib dependencies, UUID, code signature location, etc.), symbol tables (local, external, undefined), and dynamic linking information (rebase, bind, export opcodes).
*   **On-Device Operation:** All parsing and analysis happens directly on your iOS device.
*   **File Import:** Import `.dylib`, `.framework`, or `.app` bundle, executable files via the native Files app integration.
~~*   **TrollStore Optimized:** Assumes TrollStore installation for necessary file system access outside the standard app sandbox.~~ <- no longer requires trollstore to install!

![Screenshot 1](https://github.com/user-attachments/assets/cef49eba-dcec-408c-9bc5-eb18fd6513c7) 

## Features

*   **📱 Native iOS Interface:** Clean and responsive UI built with SwiftUI.
*   **🧠 Robust Mach-O Parser:**
    *   Handles 64-bit `arm64`/`arm64e` Mach-O files (Thin and Fat).
    *   Parses essential load commands (`LC_SEGMENT_64`, `LC_LOAD_DYLIB`, `LC_UUID`, `LC_SYMTAB`, `LC_DYSYMTAB`, `LC_DYLD_INFO_ONLY`, `LC_ENCRYPTION_INFO_64`, `LC_BUILD_VERSION`, etc.).
    *   Displays segment and section details (addresses, offsets, sizes, flags).
*   **🔬 Objective-C Analysis:**
    *   Reconstructs interfaces from `__objc_classlist`, `__objc_const`, `__objc_catlist`, `__objc_protolist`.
    *   Resolves method selectors and type encodings.
    *   Parses property attributes (`nonatomic`, `strong`, `weak`, `readonly`, etc.).
    *   Handles categories and merges them into base class definitions.
    *   Identifies class (`+`) and instance (`-`) methods and properties.
    *   Detects `instancetype` based on common patterns.
*   **🔬 Swift Analysis (Basic):**
    *   Parses `__swift5_types` section to find type context descriptors.
    *   Extracts mangled names for Classes, Structs, and Enums.
    *   **Attempts demangling** using `_swift_demangle` via `dlsym` (requires the function to be available in loaded images or the target binary).
*   **🔗 Dynamic Linker Info:**
    *   Parses and displays rebase operations (pointer fixups).
    *   Parses and displays bind, weak bind, and lazy bind operations (symbol linking).
    *   Parses and displays the export trie information.
*   **📄 Symbol Table Viewer:** Lists symbols with their type, scope (external/local), section, and address/value.
*   **📤 Export Options:**
    *   Copy generated Objective-C headers to the clipboard.
    *   (Future) Share headers as `.h` files.
    *   (Future) Export parsed structural info (JSON?).
*   **📂 File Handling:**
    *   Import binaries using `UIDocumentPickerViewController`.
    *   Automatically resolves executables within `.app` and `.framework` bundles.

## Technical Details

*   **Language:** Primarily Swift, leveraging low-level access via `mmap`, `UnsafeRawBufferPointer`, and direct struct memory binding.
*   **Concurrency:** Uses `async/await` and `Task.detached` for background parsing to keep the UI responsive. Actor isolation (`MainActor`) is used for UI updates.
*   **Parsing:** Implements manual parsing of Mach-O structures, Objective-C metadata (`class_ro_t`, `method_t`, etc.), Swift type descriptors, and dyld opcodes (ULEB128/SLEB128 decoding, state machines). Avoids external parsing libraries for core Mach-O structure.
*   **Demangling:** Relies on runtime availability of `_swift_demangle` via `dlopen`/`dlsym`. Does *not* bundle a static demangler library.
~~*   **TrollStore:** Requires TrollStore installation to grant the app the necessary permissions to:~~
    ~~*   Read files outside its sandbox (e.g., system frameworks, other app bundles).~~
    ~~*   Potentially use `dlopen` on arbitrary binaries (used for demangling).~~ <- now replaced by Swift-Demangle

## Installation (Requires TrollStore)

1.  Download the latest `.tipa` file from the [Releases](https://github.com/speedyfriend433/MachOHeaderDumper/releases/tag/Releases) page.
2.  Open the downloaded `.tipa` file with TrollStore.
3.  Tap "Install".
4.  The MachOHeaderDumper app will appear on your Home Screen.

## Usage

1.  Launch the MachOHeaderDumper app.
2.  Tap the "Import File..." button.
3.  Use the Files browser to navigate to and select the desired `.dylib`, `.framework`, or `.app` file/bundle.
4.  The app will parse the binary in the background. Status updates will be shown.
5.  Once parsing and analysis are complete, use the segmented picker at the top to switch between different views:
    *   **ObjC Header:** View the generated Objective-C headers (if any). Use the "Show IVars" toggle if desired.
    *   **Swift Types:** View basic information about detected Swift types (mangled/demangled name, kind).
    *   **Info:** View Mach-O header details and UUID.
    *   **Load Cmds:** View the list of load commands and their parameters.
    *   **Symbols:** Browse the symbol table.
    *   **DyldInfo:** View rebase and bind operations.
    *   **Exports:** View exported symbols.
6.  Text selection is enabled in most detail views.

## Limitations & Future Work

*   **Swift Analysis:** Swift metadata parsing is basic. It doesn't yet extract methods, properties, protocol conformances, or detailed enum cases/struct layouts. Generating full Swift interface files is a future goal.
*   **Demangling Reliability:** Swift demangling depends on finding `_swift_demangle` at runtime, which may not always succeed. Bundling a static demangler is a potential improvement.
*   **Objective-C Accuracy:** Assumes relatively modern Objective-C runtime structures. Parsing highly obfuscated or unusual binaries might yield incomplete results. Doesn't handle runtime-only features like associated objects.
*   **Encrypted Binaries:** Cannot currently parse encrypted App Store binaries. On-device decryption is a complex future possibility.
*   **Error Handling:** While basic error handling is present, parsing malformed binaries could still lead to unexpected behavior or crashes.
*   **UI/UX:** Further refinements like cross-referencing, search/filtering, graphical visualizers, and improved export options are planned.
*   **Runtime Analysis:** Adding modes for inspecting live processes or loaded libraries is a potential advanced feature.

## Building from Source

1.  Clone the repository: `git clone https://github.com/speedyfriend433/MachOHeaderDumper.git`
2.  Open `MachOHeaderDumper.xcodeproj` in Xcode.
3.  Select your device or simulator. (Note: `dlopen`/`dlsym` behavior might differ on simulator vs. device).
4.  Build the project (Cmd+B).
5.  To install on a device via TrollStore, you'll need to export an unsigned IPA:
    *   Product -> Archive.
    *   In the Organizer window, select the archive.
    *   Click "Distribute App".
    *   Choose "Ad Hoc" or "Development".
    *   Under "App Thinning", select "None".
    *   **Crucially**, uncheck "Include manifest for over-the-air installation" and **ensure code signing is set to "Sign to Run Locally" or manually configured for no signing**. (The exact steps depend on Xcode version and project setup. The goal is an unsigned IPA).
    *   Export the IPA file.
    *   Transfer the IPA to your device and install with any IPA Installer.

## Contributing

Contributions are welcome! Please feel free to submit pull requests, report issues, or suggest features. Focus areas include:

*   Improving Swift metadata parsing accuracy and depth.
*   Implementing a bundled Swift demangler.
*   Adding support for more Mach-O architectures or features.
*   Refining the UI/UX.
*   Implementing advanced analysis features (Xrefs, disassembler integration).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

*Disclaimer: This tool is intended for educational and research purposes. Respect software licenses and terms of service when analyzing binaries.*
