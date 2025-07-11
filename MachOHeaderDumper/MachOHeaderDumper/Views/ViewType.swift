import Foundation

enum ViewType: String, CaseIterable, Identifiable {
    case objcDump = "ObjC Dump"
    case swiftDump = "Swift Dump"
    case info = "Info"
    case categories = "Categories"
    case loadCmds = "Load Cmds"
    case strings = "Strings"
    case funcStarts = "Func Starts"
    case symbols = "Symbols"
    case dyldInfo = "DyldInfo"
    case exports = "Exports"
    case selectorRefs = "Sel Refs"
    var id: String { self.rawValue }
}
