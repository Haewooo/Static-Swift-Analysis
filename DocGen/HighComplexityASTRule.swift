//
//  HighComplexityASTRule.swift
//  DocGen

import Foundation
import SourceKittenFramework
import DocGen

/// 함수의 Cyclomatic Complexity(순환 복잡도)가 너무 높은 경우 감지하는 AST 기반 규칙
struct HighComplexityASTRule: SimpleASTCapableRule {
    let identifier = "high_cyclomatic_complexity_ast"
    let description = "AST를 기반으로 함수의 순환 복잡도(Cyclomatic Complexity)가 너무 높은 경우를 감지합니다."
    private let maxComplexityAllowed: Int

    /// 생성자에서 허용 최대 복잡도를 지정 (기본값 10)
    init(maxComplexityAllowed: Int = 10) {
        self.maxComplexityAllowed = maxComplexityAllowed
    }

    /// AST 구조체와 파일 정보를 받아 함수별 Cyclomatic Complexity를 계산 후 경고 반환
    func analyze(ast: Structure, file: File) -> [DocGenCore.Warning] {
        var warnings: [DocGenCore.Warning] = []
        let astAnalyzer = ASTAnalyzer()
        let functions = astAnalyzer.extractFunctions(
            from: ast.dictionary,
            fileContent: file.contents,
            filePath: file.path
        )

        for fn in functions {
            guard let bodyOffset = fn.bodyByteOffset,
                  let bodyLength = fn.bodyByteCount,
                  bodyLength > 0 else {
                continue // 본문 없는 함수는 건너뜀
            }
            let complexity = calculateCyclomaticComplexity(
                forNode: ast.dictionary,
                withinBodyOffset: bodyOffset,
                bodyLength: bodyLength
            )
            if complexity > self.maxComplexityAllowed {
                warnings.append(
                    DocGenCore.Warning(
                        id: UUID(),
                        filePath: file.path ?? "UnknownFile",
                        line: fn.line,
                        offset: fn.offset,
                        length: fn.length,
                        type: .highComplexity,
                        severity: .medium,
                        message_ko: "함수 '\(fn.name)'의 순환 복잡도가 \(complexity)로 최대치(\(self.maxComplexityAllowed))를 초과합니다.",
                        message_en: "Function '\(fn.name)' has a cyclomatic complexity of \(complexity), exceeding max of \(self.maxComplexityAllowed).",
                        suggestion_ko: "함수를 분리하거나 로직을 단순화해 복잡도를 낮추세요.",
                        suggestion_en: "Consider refactoring or simplifying the function to reduce complexity."
                    )
                )
            }
        }
        return warnings
    }

    /// 함수 본문 AST에서 순환 복잡도를 계산
    private func calculateCyclomaticComplexity(forNode astNode: [String: SourceKitRepresentable], withinBodyOffset: Int64, bodyLength: Int64) -> Int {
        var complexity = 1 // 기본값 1

        func traverse(node: [String: SourceKitRepresentable]) {
            guard let nodeOffset = node[SwiftDocKey.offset.rawValue] as? Int64,
                  let nodeLength = node[SwiftDocKey.length.rawValue] as? Int64 else {
                if let substructures = node[SwiftDocKey.substructure.rawValue] as? [SourceKitRepresentable] {
                    for case let subDict as [String: SourceKitRepresentable] in substructures {
                        traverse(node: subDict)
                    }
                }
                return
            }
            let nodeEndOffset = nodeOffset + nodeLength
            let bodyEndOffset = withinBodyOffset + bodyLength
            // 본문 범위 밖이면 무시
            if nodeEndOffset <= withinBodyOffset || nodeOffset >= bodyEndOffset {
                return
            }
            // 본문 내 제어 흐름 노드 종류별 복잡도 증가
            if nodeOffset >= withinBodyOffset && nodeEndOffset <= bodyEndOffset {
                if let kind = node[SwiftDocKey.kind.rawValue] as? String {
                    switch kind {
                    case "source.lang.swift.stmt.if",
                         "source.lang.swift.stmt.forEach",
                         "source.lang.swift.stmt.while",
                         "source.lang.swift.stmt.repeatWhile",
                         "source.lang.swift.stmt.catch",
                         "source.lang.swift.stmt.guard",
                         "source.lang.swift.stmt.case":
                        complexity += 1
                    default: break
                    }
                }
            }
            if let substructures = node[SwiftDocKey.substructure.rawValue] as? [SourceKitRepresentable] {
                for case let subDict as [String: SourceKitRepresentable] in substructures {
                    traverse(node: subDict)
                }
            }
        }
        traverse(node: astNode)
        return complexity
    }
}
