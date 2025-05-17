//
//  ASTAnalyer.swift
//  DocGen
//
//  Swift AST 분석기: SourceKittenFramework 기반
//

import Foundation
import SourceKittenFramework
import DocGen

/// Swift 소스 파일의 AST(구조체)를 분석하고 정보 추출을 지원
final class ASTAnalyzer {

    /// 지정 파일에서 AST(Structure) 추출
    /// - Parameter filePath: 분석할 Swift 파일 경로
    /// - Returns: 파싱된 Structure 객체, 실패 시 nil
    func parseAST(for filePath: String) -> Structure? {
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("❌ [ASTAnalyer] 파일 없음: \(filePath)")
            return nil
        }
        guard let file = File(path: filePath) else {
            print("❌ [ASTAnalyer] File 객체 생성 실패: \(filePath)")
            return nil
        }
        do {
            return try Structure(file: file)
        } catch {
            print("❌ [ASTAnalyer] Structure 생성 실패(\(filePath)): \(error)")
            return nil
        }
    }

    /// AST 루트노드(딕셔너리) 재귀 방문 - Visitor 패턴
    /// - Parameters:
    ///   - node: AST 노드([String: SourceKitRepresentable])
    ///   - level: 깊이(들여쓰기)
    ///   - fileContent: 원본 소스 코드
    ///   - filePath: 파일 경로
    func visit(node: [String: SourceKitRepresentable], level: Int = 0, fileContent: String, filePath: String? = nil) {
        let indent = String(repeating: "  ", count: level)
        let kind = node[SwiftDocKey.kind.rawValue] as? String
        let name = node[SwiftDocKey.name.rawValue] as? String
        let offset = node[SwiftDocKey.offset.rawValue] as? Int64

        // 오프셋 → 라인 정보 추출
        var lineInfo = ""
        if let offset = offset {
            let (line, char) = Self.lineAndChar(for: Int(offset), in: fileContent)
            lineInfo = " (Line: \(line), Char: \(char))"
        }
        print("\(indent)Kind: \(kind ?? "N/A"), Name: \(name ?? "-")\(lineInfo)")

        // 하위 구조 재귀
        if let substructures = node[SwiftDocKey.substructure.rawValue] as? [SourceKitRepresentable] {
            for case let subDict as [String: SourceKitRepresentable] in substructures {
                visit(node: subDict, level: level + 1, fileContent: fileContent, filePath: filePath)
            }
        }
    }

    /// 특정 Swift 파일의 AST 전체 방문 및 함수 정보 출력
    func demonstrateASTParsing(filePath: String) {
        guard let fileContent = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("❌ [ASTAnalyer] 파일 내용 읽기 실패: \(filePath)")
            return
        }
        guard let ast = parseAST(for: filePath) else { return }
        print("\n--- AST 구조 (\(filePath)) ---")
        visit(node: ast.dictionary, fileContent: fileContent, filePath: filePath)
        print("--- AST 출력 끝 ---\n")

        let functions = extractFunctions(from: ast.dictionary, fileContent: fileContent, filePath: filePath)
        print("함수/메서드 선언 \(functions.count)개:")
        for fn in functions {
            print("  - \(fn.name) [\(fn.kind)] Line: \(fn.line), Offset: \(fn.offset), Length: \(fn.length)")
            if let n = fn.bodyCodeLineCount, n > 50 {
                print("    ⚠️ 함수 '\(fn.name)' 본문이 매우 김 (\(n) 라인, 주석/공백 제외 순수 코드 기준)")
            } else if let n = fn.bodyLineCount, n > 50 {
                print("    ⚠️ 함수 '\(fn.name)' 본문이 매우 김 (\(n) 라인, 전체 라인 기준)")
            }
        }
    }

    /// AST에서 함수/메서드 선언만 추출
    func extractFunctions(from node: [String: SourceKitRepresentable], fileContent: String, filePath: String? = nil) -> [FunctionInfo] {
        var results: [FunctionInfo] = []
        let CONSTRUCTOR = "source.lang.swift.decl.function.constructor"
        let DESTRUCTOR  = "source.lang.swift.decl.function.destructor"

        func walk(_ n: [String: SourceKitRepresentable]) {
            if let kind = n[SwiftDocKey.kind.rawValue] as? String,
               kind.starts(with: "source.lang.swift.decl.function.") ||
               kind == CONSTRUCTOR || kind == DESTRUCTOR
            {
                let name: String
                if let n = n[SwiftDocKey.name.rawValue] as? String {
                    name = n
                } else if kind == CONSTRUCTOR {
                    name = "init"
                } else if kind == DESTRUCTOR {
                    name = "deinit"
                } else {
                    name = "unknown"
                }
                if let offset = n[SwiftDocKey.offset.rawValue] as? Int64,
                   let length = n[SwiftDocKey.length.rawValue] as? Int64
                {
                    let (line, _) = Self.lineAndChar(for: Int(offset), in: fileContent)
                    let bodyOffset = n[SwiftDocKey.bodyOffset.rawValue] as? Int64
                    let bodyLength = n[SwiftDocKey.bodyLength.rawValue] as? Int64
                    var bodyLineCount: Int?
                    var bodyCodeLineCount: Int?
                    if let bo = bodyOffset, let bl = bodyLength, bl > 0 {
                        let bStart = Int(bo)
                        let bEnd = Int(bo + bl)
                        if bStart >= 0, bEnd <= fileContent.utf8.count {
                            let u8 = Array(fileContent.utf8)
                            if let s = String(bytes: u8[bStart..<min(bEnd, u8.count)], encoding: .utf8) {
                                // 전체 라인 수(기존)
                                bodyLineCount = s.components(separatedBy: .newlines).count
                                // 코드 라인 수(주석, 공백 제외)
                                let codeLines = s.components(separatedBy: .newlines).filter { line in
                                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                                    if trimmed.isEmpty { return false }
                                    if trimmed.hasPrefix("//") { return false }
                                    if trimmed.hasPrefix("#") { return false }
                                    if trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasPrefix("*/") { return false }
                                    return true
                                }
                                bodyCodeLineCount = codeLines.count
                            }
                        }
                    }
                    let fn = FunctionInfo(
                        name: name,
                        kind: kind,
                        filePath: filePath,
                        line: line,
                        offset: offset,
                        length: length,
                        bodyByteOffset: bodyOffset,
                        bodyByteCount: bodyLength,
                        bodyLineCount: bodyLineCount,
                        bodyCodeLineCount: bodyCodeLineCount,
                        astNode: n
                    )
                    results.append(fn)
                }
            }
            if let subs = n[SwiftDocKey.substructure.rawValue] as? [SourceKitRepresentable] {
                for case let dict as [String: SourceKitRepresentable] in subs {
                    walk(dict)
                }
            }
        }
        walk(node)
        return results
    }

    /// 미해결 태그(TODO, FIXME) 추출
    func extractUnresolvedTags(from node: [String: SourceKitRepresentable], fileContent: String, filePath: String?) -> [DocGenCore.Warning] {
        var warnings: [DocGenCore.Warning] = []
        func walk(_ n: [String: SourceKitRepresentable]) {
            if let kind = n[SwiftDocKey.kind.rawValue] as? String, kind.contains(".comment") {
                if let offset = n[SwiftDocKey.offset.rawValue] as? Int64,
                   let length = n[SwiftDocKey.length.rawValue] as? Int64
                {
                    let (line, _) = ASTAnalyzer.lineAndChar(for: Int(offset), in: fileContent)
                    let commentText: String
                    let u8 = Array(fileContent.utf8)
                    if Int(offset) + Int(length) <= u8.count,
                       let s = String(bytes: u8[Int(offset)..<Int(offset+length)], encoding: .utf8) {
                        commentText = s
                    } else { commentText = "" }
                    if commentText.contains("TODO:") || commentText.contains("FIXME:") {
                        let tag = commentText.contains("TODO:") ? "TODO" : "FIXME"
                        warnings.append(
                            DocGenCore.Warning( // DocGenCore.Warning 생성자 호출
                                id: UUID(),
                                filePath: filePath ?? "",
                                line: line,
                                // DocGenCore.Warning init 정의에 따른 올바른 순서로 변경:
                                offset: offset,   // offset, length가 type, severity보다 먼저 와야 함
                                length: length,
                                type: .unresolvedTag,
                                severity: .medium, // 또는 .info 등 적절한 심각도
                                message_ko: "주석에 미해결 태그(\(tag))가 남아 있습니다.",
                                message_en: "Unresolved tag (\(tag)) found in comment.",
                                suggestion_ko: "TODO/FIXME 처리 또는 삭제 권장.",
                                suggestion_en: "Address or remove TODO/FIXME tags."
                            )
                        )
                    }
                }
            }
            if let subs = n[SwiftDocKey.substructure.rawValue] as? [SourceKitRepresentable] {
                for case let dict as [String: SourceKitRepresentable] in subs { walk(dict) }
            }
        }
        walk(node)
        return warnings
    }

    /// 중복 함수명(시그니처) 추출
    func findDuplicateFunctions(_ functions: [FunctionInfo], filePath: String?) -> [DocGenCore.Warning] {
        var warnings: [DocGenCore.Warning] = []
        var seen = [String: [FunctionInfo]]()
        for fn in functions {
            let sig = fn.signature
            seen[sig, default: []].append(fn)
        }
        for (sig, list) in seen where list.count > 1 {
            for fn in list {
                warnings.append(
                    DocGenCore.Warning( // DocGenCore.Warning 생성자 호출
                        id: UUID(),
                        filePath: filePath ?? "",
                        line: fn.line,
                        offset: fn.offset, // FunctionInfo에서 가져온 offset
                        length: fn.length, // FunctionInfo에서 가져온 length
                        type: .duplicateFunctionName, // DocGenCore.WarningType.duplicateFunctionName
                        severity: .medium,            // DocGenCore.Severity.medium
                        message_ko: "중복 함수 선언: \(sig)",
                        message_en: "Duplicate function declaration: \(sig)",
                        suggestion_ko: "중복 함수를 제거/통합하거나 시그니처 차별화 필요.",
                        suggestion_en: "Remove/merge duplicates or differentiate signature."
                    )
                )
            }
        }
        return warnings
    }

    /// 오프셋 기반 라인/문자 반환 (UTF-8 근사)
    static func lineAndChar(for byteOffset: Int, in content: String) -> (line: Int, char: Int) {
        let u8 = Array(content.utf8)
        guard byteOffset <= u8.count else { return (1, 1) }
        let partial = u8.prefix(byteOffset)
        let s = String(decoding: partial, as: UTF8.self)
        let lines = s.components(separatedBy: .newlines)
        return (lines.count, (lines.last?.count ?? 0) + 1)
    }
}

/// 함수/메서드 선언 정보 구조체
struct FunctionInfo {
    let name: String
    let kind: String
    let filePath: String?
    let line: Int
    let offset: Int64
    let length: Int64
    let bodyByteOffset: Int64?
    let bodyByteCount: Int64?
    let bodyLineCount: Int?
    let bodyCodeLineCount: Int? // 실제 코드 라인(주석/빈 줄 제외)
    let astNode: [String: SourceKitRepresentable]? // AST 노드 원본 저장(파라미터 추출용)

    var signature: String {
        let param = parameterTypes?.joined(separator: ",") ?? ""
        return "\(name)(\(param))"
    }
    var parameterTypes: [String]? {
        guard let node = astNode else { return nil }
        // swiftDocKey.elements 에서 파라미터 타입 추출 시도
        if let elements = node[SwiftDocKey.elements.rawValue] as? [SourceKitRepresentable] {
            var types: [String] = []
            for case let elem as [String: SourceKitRepresentable] in elements {
                if let kind = elem[SwiftDocKey.kind.rawValue] as? String,
                   kind == "source.lang.swift.decl.var.parameter" {
                    if let typeName = elem[SwiftDocKey.typeName.rawValue] as? String {
                        types.append(typeName)
                    } else if let name = elem[SwiftDocKey.name.rawValue] as? String {
                        types.append(name)
                    } else {
                        types.append("Any")
                    }
                }
            }
            return types
        }
        return nil
    }
}


// MARK: - AST 규칙 추상화 및 확장성 지원

/// 모든 AST 기반 분석 규칙이 따를 프로토콜
protocol SimpleASTCapableRule {
    var identifier: String { get }
    var description: String { get }
    func analyze(ast: Structure, file: File) -> [DocGenCore.Warning]
}

/// 긴 함수 규칙(순수 코드라인 기준)
struct LongFunctionASTRule: SimpleASTCapableRule {
    let identifier = "long_function_ast"
    let description = "AST 기반, 주석/공백 제외 순수 코드 기준 함수 길이 초과 경고"
    let maxBodyLines: Int

    init(maxBodyLines: Int = 50) {
        self.maxBodyLines = maxBodyLines
    }

    func analyze(ast: Structure, file: File) -> [DocGenCore.Warning] {
        let analyzer = ASTAnalyzer()
        let functions = analyzer.extractFunctions(from: ast.dictionary, fileContent: file.contents, filePath: file.path)
        var warnings: [DocGenCore.Warning] = []
        for fn in functions {
            let codeLines = fn.bodyCodeLineCount ?? fn.bodyLineCount ?? 0
            if codeLines > self.maxBodyLines {
                warnings.append(
                    DocGenCore.Warning(
                        id: UUID(),
                        filePath: file.path ?? "",
                        line: fn.line,
                        offset: fn.offset,
                        length: fn.length,
                        type: .longFunction, // DocGenCore.WarningType.longFunction
                        severity: .medium,   // DocGenCore.Severity.medium
                        message_ko: "함수 '\(fn.name)'의 본문 길이가 \(codeLines)줄(순수 코드 기준, 최대: \(self.maxBodyLines)줄)을 초과합니다.",
                        message_en: "Function '\(fn.name)' body is too long (\(codeLines) lines, code only, max: \(self.maxBodyLines)).",
                        suggestion_ko: "함수를 더 작은 단위로 분리하세요.",
                        suggestion_en: "Consider splitting the function into smaller units."
                    )
                )
            }
        }
        return warnings
    }
}

/// 미해결 태그 규칙(AST 기반, TODO/FIXME)
struct UnresolvedTagASTRule: SimpleASTCapableRule {
    let identifier = "unresolved_tag_ast"
    let description = "AST 기반, 주석 내 TODO: 또는 FIXME: 태그 감지"
    func analyze(ast: Structure, file: File) -> [DocGenCore.Warning] {
        let analyzer = ASTAnalyzer()
        // Already returns [DocGenCore.Warning] with offset and length set
        return analyzer.extractUnresolvedTags(from: ast.dictionary, fileContent: file.contents, filePath: file.path)
    }
}

struct DuplicateFunctionASTRule: SimpleASTCapableRule {
    let identifier = "duplicate_function_ast"
    let description = "AST 기반, 함수명+파라미터 시그니처 중복 감지"

    func analyze(ast: Structure, file: File) -> [DocGenCore.Warning] {
        let analyzer = ASTAnalyzer()
        let functions = analyzer.extractFunctions(from: ast.dictionary, fileContent: file.contents, filePath: file.path)
        // Use the analyzer's findDuplicateFunctions to get all warnings with offset/length
        return analyzer.findDuplicateFunctions(functions, filePath: file.path)
    }
}
