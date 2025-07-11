//
//  FormattingUtils.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import Foundation

func vmProtToString(_ prot: vm_prot_t) -> String {
    var parts: [String] = []
    if (prot & VM_PROT_READ) != 0 { parts.append("R") } else { parts.append("-") }
    if (prot & VM_PROT_WRITE) != 0 { parts.append("W") } else { parts.append("-") }
    if (prot & VM_PROT_EXECUTE) != 0 { parts.append("X") } else { parts.append("-") }
    return parts.joined()
}
