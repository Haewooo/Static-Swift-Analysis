import SourceKittenFramework
// MARK: - AST 기반 분석기 연동

extension DocGenCore {
    // 활성화할 규칙 목록 (추후 확장 예정)
    static var activeASTRules: [SimpleASTCapableRule] = [
        LongFunctionASTRule(maxBodyLines: 60), // 기존 규칙, 임계값 60으로 설정
        UnresolvedTagASTRule(),
        DuplicateFunctionASTRule(),
        HighComplexityASTRule(maxComplexityAllowed: 15) // 새 규칙, 최대 복잡도 15로 설정
        // 추가적인 AST 기반 규칙은 여기에 선언
    ]

    /// AST 기반 파일 분석 (SimpleASTCapableRule 기반 엔진)
    static func analyzeFileUsingAST(filePath: String, relativePath: String) -> FileAnalysisResult? {
        guard let fileObject = File(path: filePath) else {
            let warning = Warning(id: UUID(), filePath: relativePath, line: nil, type: .securityIssue, severity: .high,
                                  message_ko: "파일 객체를 생성할 수 없습니다 (AST 분석).",
                                  message_en: "Failed to create File object (AST analysis).")
            return FileAnalysisResult(id: UUID(), file: relativePath, lines: 0, codeLines: 0, commentLines: 0, blankLines: 0, funcCount: 0, avgFuncLength: 0, longestFunc: 0, warnings: [warning])
        }
        let astAnalyzer = ASTAnalyzer()
        guard let ast = astAnalyzer.parseAST(for: filePath) else {
            let warning = Warning(id: UUID(), filePath: relativePath, line: nil, type: .styleViolation, severity: .medium,
                                  message_ko: "AST 파싱 실패.", message_en: "Failed to parse AST.")
            return FileAnalysisResult(id: UUID(), file: relativePath, lines: 0, codeLines: 0, commentLines: 0, blankLines: 0, funcCount: 0, avgFuncLength: 0, longestFunc: 0, warnings: [warning])
        }

        // 규칙 기반 경고 집계
        var allWarningsForFile: [Warning] = []

        // 코드/주석/공백/전체 라인 등은 기존 방식 유지
        guard let fileContent = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }
        let (code, comment, blank) = analyzeLineTypes(fileContent)
        let lines = fileContent.components(separatedBy: .newlines).count

        // 함수 통계: AST에서 추출, 평균/최장 자동 산출
        let functions = astAnalyzer.extractFunctions(from: ast.dictionary, fileContent: fileContent, filePath: filePath)
        let funcCount = functions.count
        let funcBodyLens = functions.compactMap { $0.bodyCodeLineCount ?? $0.bodyLineCount }
        let avgFuncLength = funcBodyLens.isEmpty ? 0.0 : Double(funcBodyLens.reduce(0, +)) / Double(funcBodyLens.count)
        let longestFunc = funcBodyLens.max() ?? 0

        // AST 기반 규칙 평가 및 경고 수집
        for rule in activeASTRules {
            let warnings = rule.analyze(ast: ast, file: fileObject)
            allWarningsForFile.append(contentsOf: warnings)
        }

        return FileAnalysisResult(
            id: UUID(),
            file: relativePath,
            lines: lines,
            codeLines: code,
            commentLines: comment,
            blankLines: blank,
            funcCount: funcCount,
            avgFuncLength: avgFuncLength,
            longestFunc: longestFunc,
            warnings: allWarningsForFile
        )
    }
}
//
//  Main.swift
//  DocGen
//

import Foundation

class DocGenCore {
    // 앱 전체 언어 설정 (ko, en)
    static var currentLanguage: String = "ko"
    // 메시지 요약/줄바꿈: 최대 120자 이내로 줄바꿈
    static func wrap(_ text: String, limit: Int = 120) -> String {
        var result = ""
        var currentLine = ""
        for word in text.split(separator: " ") {
            if currentLine.count + word.count + 1 > limit {
                result += currentLine + "\n"
                currentLine = String(word)
            } else {
                if currentLine.isEmpty {
                    currentLine = String(word)
                } else {
                    currentLine += " " + word
                }
            }
        }
        if !currentLine.isEmpty { result += currentLine }
        return result
    }
    // 파일별 통계 구조체 및 경고 모델
    enum WarningType: String, CaseIterable, Identifiable {
        case longFunction
        case highComplexity
        case unusedVariable
        case styleViolation
        case securityIssue
        case duplicateFunctionName
        case longFile
        case unresolvedTag
        case improperAccessControl
        var id: String { self.rawValue }
        var ko: String {
            switch self {
            case .longFunction: return "긴 함수"
            case .highComplexity: return "높은 복잡도"
            case .unusedVariable: return "미사용 변수"
            case .styleViolation: return "코드 스타일 위반"
            case .securityIssue: return "보안 관련 경고"
            case .duplicateFunctionName: return "중복 함수명"
            case .longFile: return "긴 파일 (1200줄 초과)"
            case .unresolvedTag: return "미해결 태그 (TODO, FIXME)"
            case .improperAccessControl: return "부적절한 접근 제어"
            }
        }
        var en: String {
            switch self {
            case .longFunction: return "Long function"
            case .highComplexity: return "High complexity"
            case .unusedVariable: return "Unused variable"
            case .styleViolation: return "Style violation"
            case .securityIssue: return "Security warning"
            case .duplicateFunctionName: return "Duplicate function name"
            case .longFile: return "Long file (over 1200 lines)"
            case .unresolvedTag: return "Unresolved tag (TODO, FIXME)"
            case .improperAccessControl: return "Improper access control"
            }
        }
        var display: String {
            switch DocGenCore.currentLanguage {
            case "en": return en
            case "ko": fallthrough
            default: return "\(ko) (\(en))"
            }
        }
    }

    enum Severity: Int, Comparable {
        case info = 0
        case low = 1
        case medium = 2
        case high = 3
        case critical = 4
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
        var displayName: String {
            switch DocGenCore.currentLanguage {
            case "en":
                switch self {
                case .info: return "Info"
                case .low: return "Low"
                case .medium: return "Medium"
                case .high: return "High"
                case .critical: return "Critical"
                }
            case "ko": fallthrough
            default:
                switch self {
                case .info: return "정보 (Info)"
                case .low: return "낮음 (Low)"
                case .medium: return "중간 (Medium)"
                case .high: return "높음 (High)"
                case .critical: return "심각 (Critical)"
                }
            }
        }
    }

    public struct Warning: Identifiable, Equatable {
        public let id: UUID
        public let filePath: String
        public let line: Int?
        public let offset: Int64?
        public let length: Int64?
        public let type: WarningType
        public let severity: Severity
        public let message_ko: String
        public let message_en: String
        public let suggestion_ko: String?
        public let suggestion_en: String?

        public var message: String {
            switch DocGenCore.currentLanguage {
            case "en": return message_en
            case "ko": fallthrough
            default: return "\(message_ko) (\(message_en))"
            }
        }

        public var suggestion: String? {
            switch DocGenCore.currentLanguage {
            case "en": return suggestion_en
            case "ko": fallthrough
            default:
                if let ko = suggestion_ko, let en = suggestion_en {
                    return "\(ko) (\(en))"
                } else if let ko = suggestion_ko {
                    return ko
                } else if let en = suggestion_en {
                    return en
                } else {
                    return nil
                }
            }
        }

        public static func == (lhs: Warning, rhs: Warning) -> Bool {
            lhs.id == rhs.id
        }

        public init(id: UUID = UUID(), filePath: String, line: Int?,
                    offset: Int64? = nil, length: Int64? = nil, // offset, length 파라미터
                    type: WarningType, severity: Severity,
                    message_ko: String, message_en: String,
                    suggestion_ko: String? = nil, suggestion_en: String? = nil) {
            self.id = id
            self.filePath = filePath
            self.line = line
            self.offset = offset // 할당
            self.length = length // 할당
            self.type = type
            self.severity = severity
            self.message_ko = message_ko
            self.message_en = message_en
            self.suggestion_ko = suggestion_ko
            self.suggestion_en = suggestion_en
        }
    }

    struct FileAnalysisResult: Identifiable, Equatable {
        let id: UUID
        let file: String
        let lines: Int
        let codeLines: Int
        let commentLines: Int
        let blankLines: Int
        let funcCount: Int
        let avgFuncLength: Double
        let longestFunc: Int
        let warnings: [Warning]
        static func == (lhs: FileAnalysisResult, rhs: FileAnalysisResult) -> Bool {
            lhs.id == rhs.id
        }
    }

    struct AnalysisDashboard {
        let analyses: [FileAnalysisResult]
        let totalLines: Int
        let totalFuncs: Int
        let totalComments: Int
        let totalBlanks: Int
        let commentRate: Double
        let qualityMsg: String
        let warnings: [Warning]
        let summaryText: String // 로그나 상태에 쓸 메시지
    }

    // 통합 정적 분석/품질 평가/코드스멜/보안/컨벤션 등
    static func generate(rootPath: String, outputPath: String) -> AnalysisDashboard {
        let swiftFiles = findSwiftFiles(at: rootPath)
        var fileAnalyses: [FileAnalysisResult] = []
        var totalLineCount = 0
        var totalCode = 0, totalComment = 0, totalBlank = 0
        var totalFunc = 0
        var warnings: [Warning] = []
        var smellCount = 0
        for filePath in swiftFiles {
            let relativePath = filePath.replacingOccurrences(of: rootPath + "/", with: "")
            if let fileAnalysis = analyzeFileUsingAST(filePath: filePath, relativePath: relativePath) {
                fileAnalyses.append(fileAnalysis)
                totalLineCount += fileAnalysis.lines
                totalCode += fileAnalysis.codeLines
                totalComment += fileAnalysis.commentLines
                totalBlank += fileAnalysis.blankLines
                totalFunc += fileAnalysis.funcCount
                warnings.append(contentsOf: fileAnalysis.warnings)
                smellCount += fileAnalysis.warnings.count
            }
            generateDocs(for: filePath, relativePath: relativePath, outputPath: outputPath)
        }
        let commentRate = totalCode == 0 ? 0 : Double(totalComment) / Double(totalCode) * 100
        // avgFileQualityScore 계산: fileAnalyses.map { fileQualityScore($0) }의 평균만 사용
        let avgScore = fileAnalyses.isEmpty ? 0.0 : fileAnalyses.map { fileQualityScore($0) }.reduce(0, +) / Double(fileAnalyses.count)
        let qualityMsg: String = {
            let score = String(format: "%.1f", min(100.0, avgScore))
            switch DocGenCore.currentLanguage {
            case "en": return "Quality score: \(score)/100"
            case "ko": fallthrough
            default: return "품질점수: \(score)/100 (Quality score: \(score)/100)"
            }
        }()
        let commentMsg: String = {
            let rateStr = String(format: "%.1f", commentRate)
            if commentRate < 7 {
                switch DocGenCore.currentLanguage {
                case "en": return "Low comment rate (\(rateStr)%)"
                case "ko": fallthrough
                default: return "주석률 낮음(\(rateStr)%) (Low comment rate (\(rateStr)%))"
                }
            } else {
                switch DocGenCore.currentLanguage {
                case "en": return "Adequate comment rate (\(rateStr)%)"
                case "ko": fallthrough
                default: return "주석 적정(\(rateStr)%) (Adequate comment rate (\(rateStr)%))"
                }
            }
        }()
        generateSummaryIndex(
            from: fileAnalyses.map { ($0.file, [], [], []) },
            outputPath: outputPath,
            fileAnalyses: fileAnalyses,
            totalLineCount: totalLineCount,
            totalFunc: totalFunc,
            commentMsg: commentMsg,
            qualityMsg: qualityMsg
        )
        let warningText: String
        if warnings.isEmpty {
            switch DocGenCore.currentLanguage {
            case "en": warningText = "No notable warnings."
            case "ko": fallthrough
            default: warningText = "특이 경고 없음. (No notable warnings.)"
            }
        } else {
            warningText = warnings.map { w in
                let linePart = w.line != nil ? " (line \(w.line ?? 0))" : ""
                return "(\(w.filePath))\(linePart): [\(w.type.display)] \(wrap(w.message))"
            }.joined(separator: "\n")
        }
        let resultMsg: String = {
            // 현지화 함수
            func label(_ ko: String, _ en: String) -> String {
                return DocGenCore.currentLanguage == "en" ? en : "\(ko) (\(en))"
            }
            let filesText: String
            switch DocGenCore.currentLanguage {
            case "en":
                filesText = label("완료: \(swiftFiles.count)개 파일 분석됨.", "Completed: \(swiftFiles.count) files analyzed.") + "\n"
            case "ko": fallthrough
            default:
                filesText = label("완료: \(swiftFiles.count)개 파일 분석됨.", "Completed: \(swiftFiles.count) files analyzed.") + "\n"
            }
            let avgFuncLengthStr = totalFunc > 0 ? String(format: "%.1f", Double(totalCode) / Double(totalFunc)) : "0"
            let commentRateStr = String(format: "%.1f", commentRate)
            let statText: String
            switch DocGenCore.currentLanguage {
            case "en":
                statText = label(
                    "전체 줄수: \(totalLineCount) / 코드: \(totalCode) / 주석: \(totalComment) / 공백: \(totalBlank)\n함수: \(totalFunc), 평균 함수길이: \(avgFuncLengthStr)\n주석률: \(commentRateStr)% (Comment rate: \(commentRateStr)%)\n",
                    "Total lines: \(totalLineCount) / Code: \(totalCode) / Comments: \(totalComment) / Blank: \(totalBlank)\nFunctions: \(totalFunc), Avg. function length: \(avgFuncLengthStr)\nComment rate: \(commentRateStr)%\n"
                )
            case "ko": fallthrough
            default:
                statText = label(
                    "전체 줄수: \(totalLineCount) / 코드: \(totalCode) / 주석: \(totalComment) / 공백: \(totalBlank)\n함수: \(totalFunc), 평균 함수길이: \(avgFuncLengthStr)\n주석률: \(commentRateStr)% (Comment rate: \(commentRateStr)%)\n",
                    "Total lines: \(totalLineCount) / Code: \(totalCode) / Comments: \(totalComment) / Blank: \(totalBlank)\nFunctions: \(totalFunc), Avg. function length: \(avgFuncLengthStr)\nComment rate: \(commentRateStr)%\n"
                )
            }
            let smellText: String
            switch DocGenCore.currentLanguage {
            case "en":
                smellText = label(
                    "감지 건수: \(smellCount) (Detected: \(smellCount))\n",
                    "Detected code violation: \(smellCount)\n"
                )
            case "ko": fallthrough
            default:
                smellText = label(
                    "감지 건수: \(smellCount) (Detected: \(smellCount))\n",
                    "Detected code violation: \(smellCount)\n"
                )
            }
            let warningsLabel: String = label("경고:", "Warnings:")
            let msg = filesText + statText + "\(qualityMsg) / \(commentMsg)\n" + smellText + "\(warningsLabel)\n\(warningText)"
            return wrap(msg)
        }()
        return AnalysisDashboard(
            analyses: fileAnalyses,
            totalLines: totalLineCount,
            totalFuncs: totalFunc,
            totalComments: totalComment,
            totalBlanks: totalBlank,
            commentRate: commentRate,
            qualityMsg: qualityMsg,
            warnings: warnings,
            summaryText: resultMsg
        )
    }

    /// 파일 품질 점수 계산 함수 (경고, 파일 길이, 평균 함수 길이 기반)
    private static func fileQualityScore(_ analysis: FileAnalysisResult) -> Double {
        var score = 100.0
        score -= Double(analysis.warnings.count * 2)
        if analysis.lines > 1200 { score -= 5 }
        if analysis.avgFuncLength > 40 { score -= 5 }
        if score < 0 { score = 0 }
        return score
    }

    // advanced analysis using Warning objects and modularized helpers
    static func analyzeAdvanced(content: String, filePath: String) -> (
        funcCount: Int, avgFuncLen: Double, maxFuncLen: Int, warnings: [Warning]
    ) {
        var allWarnings: [Warning] = []
        let lines = content.components(separatedBy: .newlines)
        // 1. 함수 관련 지표 및 경고 분석
        let funcAnalysisResult = analyzeFunctionMetrics(lines: lines, filePath: filePath)
        allWarnings.append(contentsOf: funcAnalysisResult.warnings)
        // 3. 미사용 파일 레벨 변수 탐지
        allWarnings.append(contentsOf: findUnusedFileLevelVariables(lines: lines, filePath: filePath, functionLocalVariables: funcAnalysisResult.localVariablesInFunctions))
        // 4. 코드 스타일 위반 탐지
        allWarnings.append(contentsOf: checkStyleViolations(lines: lines, filePath: filePath))
        // 5. 보안 관련 문제 탐지
        allWarnings.append(contentsOf: findSecurityIssues(lines: lines, filePath: filePath))
        // 6. 미해결 태그 (TODO, FIXME) 탐지
        allWarnings.append(contentsOf: findUnresolvedTags(lines: lines, filePath: filePath))
        return (
            funcCount: funcAnalysisResult.count,
            avgFuncLen: funcAnalysisResult.avgLen,
            maxFuncLen: funcAnalysisResult.maxLen,
            warnings: allWarnings
        )
    }

    // 1. 함수 관련 지표 및 경고 분석 (함수 개수, 길이, 복잡도, 중복 함수명 등)
    private static func analyzeFunctionMetrics(lines: [String], filePath: String) -> (
        count: Int, avgLen: Double, maxLen: Int, warnings: [Warning], localVariablesInFunctions: [String: ([String], Set<String>)]
    ) {
        var warnings: [Warning] = []
        var funcCount = 0
        var funcLens: [Int] = []
        var currentFuncLen = 0
        var currentCyclomatic = 1
        var insideFunc = false
        var currentFuncStartLine = 0
        var currentFuncName: String? = nil
        var funcNameCounts: [String: Int] = [:]
        var funcNameToLine: [String: Int] = [:]
        var localVars: [String] = []
        var usedVars: Set<String> = []
        var allLocalVariablesInFunctions: [String: ([String], Set<String>)] = [:]
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = idx + 1
            if let funcRange = trimmed.range(of: #"func\s+([A-Za-z_][A-Za-z0-9_<>\[\]\.:\s\(\),?]*)\("#, options: .regularExpression) {
                if insideFunc, let fName = currentFuncName {
                    funcLens.append(currentFuncLen)
                    if currentCyclomatic > 12 {
                        warnings.append(Warning(
                            id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .highComplexity, severity: .high,
                            message_ko: "함수 '\(fName)'의 Cyclomatic Complexity가 \(currentCyclomatic)으로 높습니다 (12 이하 권장).",
                            message_en: "Function '\(fName)' has high cyclomatic complexity (\(currentCyclomatic)) (recommended ≤12).",
                            suggestion_ko: "함수를 더 작은 단위로 분리하거나 로직을 단순화하세요.",
                            suggestion_en: "Split into smaller functions or simplify logic."
                        ))
                    }
                    for v in localVars where !usedVars.contains(v) {
                        warnings.append(Warning(
                            id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .unusedVariable, severity: .low,
                            message_ko: "함수 '\(fName)' 내 지역 변수/상수 '\(v)'가 사용되지 않았습니다.",
                            message_en: "Unused local variable/constant '\(v)' in function '\(fName)'.",
                            suggestion_ko: "불필요하면 제거하세요.",
                            suggestion_en: "Remove if unnecessary."
                        ))
                    }
                    allLocalVariablesInFunctions[fName] = (localVars, usedVars)
                }
                insideFunc = true
                funcCount += 1
                currentFuncLen = 1
                currentCyclomatic = 1
                currentFuncStartLine = lineNumber
                localVars = []
                usedVars = []
                let funcSignature = String(trimmed[funcRange.lowerBound ..< trimmed.range(of: "(")!.lowerBound])
                let fname = funcSignature.replacingOccurrences(of: "func ", with: "").trimmingCharacters(in: .whitespaces)
                currentFuncName = fname
                if !fname.isEmpty {
                    funcNameCounts[fname, default: 0] += 1
                    if funcNameCounts[fname] == 1 {
                        funcNameToLine[fname] = lineNumber
                    }
                }
            } else if insideFunc {
                currentFuncLen += 1
                if trimmed.hasPrefix("}") {
                    if let fName = currentFuncName {
                        funcLens.append(currentFuncLen)
                        if currentCyclomatic > 12 {
                        warnings.append(Warning(
                            id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .highComplexity, severity: .high,
                            message_ko: "함수 '\(fName)'의 Cyclomatic Complexity가 \(currentCyclomatic)으로 높습니다 (12 이하 권장).",
                            message_en: "Function '\(fName)' has high cyclomatic complexity (\(currentCyclomatic)) (recommended ≤12).",
                            suggestion_ko: "함수를 더 작은 단위로 분리하거나 로직을 단순화하세요.",
                            suggestion_en: "Split into smaller functions or simplify logic."
                        ))
                        }
                        for v in localVars where !usedVars.contains(v) {
                            warnings.append(Warning(
                                id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .unusedVariable, severity: .low,
                                message_ko: "함수 '\(fName)' 내 지역 변수/상수 '\(v)'가 사용되지 않았습니다.",
                                message_en: "Unused local variable/constant '\(v)' in function '\(fName)'.",
                                suggestion_ko: "불필요하면 제거하세요.",
                                suggestion_en: "Remove if unnecessary."
                            ))
                        }
                        allLocalVariablesInFunctions[fName] = (localVars, usedVars)
                    }
                    insideFunc = false
                    currentFuncName = nil
                    localVars = []
                    usedVars = []
                } else {
                    if trimmed.contains("if ") || trimmed.contains("guard ") || trimmed.contains("while ") || trimmed.contains("for ") || trimmed.contains("case ") || trimmed.contains("catch ") || trimmed.contains("else if ") {
                        currentCyclomatic += 1
                    }
                    if let range = trimmed.range(of: #"(let|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) {
                        let parts = trimmed[range].split(separator: " ")
                        if parts.count > 1 {
                            let name = String(parts[1])
                            if !name.isEmpty && name != "_" { localVars.append(name) }
                        }
                    }
                    for v in localVars {
                        if trimmed.range(of: "\\b\(v)\\b", options: .regularExpression) != nil { usedVars.insert(v) }
                    }
                }
            }
        }
        if insideFunc, let fName = currentFuncName {
            funcLens.append(currentFuncLen)
            if currentCyclomatic > 12 {
                warnings.append(Warning(
                    id: UUID(),
                    filePath: filePath,
                    line: currentFuncStartLine,
                    type: .highComplexity,
                    severity: .high,
                    message_ko: "함수 '\(fName)'의 Cyclomatic Complexity가 \(currentCyclomatic)으로 높습니다 (12 이하 권장).",
                    message_en: "Function '\(fName)' has high cyclomatic complexity (\(currentCyclomatic)) (recommended ≤12).",
                    suggestion_ko: "함수를 더 작은 단위로 분리하거나 로직을 단순화하세요.",
                    suggestion_en: "Split into smaller functions or simplify logic."
                ))
            }
            for v in localVars where !usedVars.contains(v) {
                warnings.append(Warning(
                    id: UUID(),
                    filePath: filePath,
                    line: currentFuncStartLine,
                    type: .unusedVariable,
                    severity: .low,
                    message_ko: "함수 '\(fName)' 내 지역 변수/상수 '\(v)'가 사용되지 않았습니다.",
                    message_en: "Unused local variable/constant '\(v)' in function '\(fName)'.",
                    suggestion_ko: "불필요하면 제거하세요.",
                    suggestion_en: "Remove if unnecessary."
                ))
            }
            allLocalVariablesInFunctions[fName] = (localVars, usedVars)
        }
        for (idx, lenInfo) in funcLens.enumerated() where lenInfo > 50 {
            warnings.append(Warning(
                id: UUID(),
                filePath: filePath,
                line: nil,
                type: .longFunction,
                severity: .medium,
                message_ko: "함수 (순서: \(idx+1))의 길이가 \(lenInfo)줄로 너무 깁니다 (50줄 이하 권장).",
                message_en: "Function (index: \(idx+1)) is too long (\(lenInfo) lines, recommended ≤50).",
                suggestion_ko: "함수를 더 작은 단위로 분리하는 것을 고려하세요.",
                suggestion_en: "Consider splitting into smaller functions."
            ))
        }
        for (name, count) in funcNameCounts where count > 1 {
            warnings.append(Warning(
                id: UUID(),
                filePath: filePath,
                line: funcNameToLine[name],
                type: .duplicateFunctionName,
                severity: .medium,
                message_ko: "함수명 '\(name)'이(가) 파일 내에서 \(count)번 중복 정의되었습니다.",
                message_en: "Function name '\(name)' is duplicated \(count) times in the file.",
                suggestion_ko: "함수명을 다르게 하거나, 오버로딩이 올바르게 되었는지 확인하세요.",
                suggestion_en: "Rename the function or verify correct overloading."
            ))
        }
        let maxLen = funcLens.max() ?? 0
        let avgLen = funcLens.isEmpty ? 0.0 : Double(funcLens.reduce(0, +)) / Double(funcLens.count)
        return (funcCount, avgLen, maxLen, warnings, allLocalVariablesInFunctions)
    }

    // 3. 미사용 파일 레벨 변수 탐지
    // Detects true file-level variables (not inside any type/extension/protocol) and warns if unused.
    // - Only considers variables declared at the file scope (not inside class/struct/enum/extension/protocol/actor).
    // - Ignores variables declared inside type bodies or extensions.
    // - Usage check avoids counting the declaration line itself as usage.
    // - Uses precise word boundaries for variable detection.
    private static func findUnusedFileLevelVariables(lines: [String], filePath: String, functionLocalVariables: [String: ([String], Set<String>)]) -> [Warning] {
        var warnings: [Warning] = []
        var fileLevelVars: [String: Int] = [:] // name -> line number
        var scopeStack: [String] = [] // Track the current nesting (e.g. class, struct, enum, extension, protocol, actor)
        var braceBalanceStack: [Int] = [] // Track { count for each scope
        let typeDeclRegex = try! NSRegularExpression(pattern: #"^\s*(class|struct|enum|extension|protocol|actor)\b"#)
        let varDeclRegex = try! NSRegularExpression(pattern: #"^\s*(var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\b"#)
        // Step 1: Identify file-level variable/constant declarations
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Detect scope entry: class/struct/enum/extension/protocol/actor
            if let match = typeDeclRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                // Entering a type/extension scope
                if let typeRange = Range(match.range(at: 1), in: trimmed) {
                    let typeKeyword = String(trimmed[typeRange])
                    scopeStack.append(typeKeyword)
                    // Count braces on this line and push to stack for this scope
                    let openBraces = trimmed.filter { $0 == "{" }.count
                    braceBalanceStack.append(openBraces)
                }
            }
            // Track braces to detect leaving type scopes
            var openCount = line.filter { $0 == "{" }.count
            var closeCount = line.filter { $0 == "}" }.count
            if !braceBalanceStack.isEmpty {
                braceBalanceStack[braceBalanceStack.count-1] += openCount - closeCount
                // If brace count for this scope drops to zero or below, pop scope
                while let last = braceBalanceStack.last, last <= 0, !scopeStack.isEmpty {
                    braceBalanceStack.removeLast()
                    scopeStack.removeLast()
                }
            }
            // Only collect variables when not inside any type/extension/protocol/actor
            if scopeStack.isEmpty {
                if let match = varDeclRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                    // Get variable name
                    if let nameRange = Range(match.range(at: 2), in: trimmed) {
                        let name = String(trimmed[nameRange])
                        if !name.isEmpty && name != "_" {
                            fileLevelVars[name] = idx+1
                        }
                    }
                }
            }
        }
        // Step 2: For each file-level variable, check for usage elsewhere in the file (excluding its own declaration line)
        for (varName, declLine) in fileLevelVars {
            var isUsed = false
            let varPattern = #"(?<![A-Za-z0-9_])\#(varName)\b"#
            let varRegex = try! NSRegularExpression(pattern: varPattern)
            for (idx, line) in lines.enumerated() {
                if idx + 1 == declLine { continue } // skip declaration line itself
                // Avoid false positives: skip comments
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                // Only count as usage if variable name appears as whole word
                if varRegex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil {
                    isUsed = true
                    break
                }
            }
            if !isUsed {
                warnings.append(Warning(
                    id: UUID(),
                    filePath: filePath,
                    line: declLine,
                    type: .unusedVariable,
                    severity: .low,
                    message_ko: "파일 레벨 변수/상수 '\(varName)'가 사용되지 않았습니다.",
                    message_en: "Unused file-level variable/constant '\(varName)'.",
                    suggestion_ko: "불필요하다면 삭제하세요.",
                    suggestion_en: "Delete if unnecessary."
                ))
            }
        }
        return warnings
    }

    // 4. 코드 스타일 위반 탐지
    private static func checkStyleViolations(lines: [String], filePath: String) -> [Warning] {
        var warnings: [Warning] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 불필요한 공백
            if trimmed.hasSuffix("  ") {
                warnings.append(Warning(
                    id: UUID(),
                    filePath: filePath,
                    line: idx+1,
                    type: .styleViolation,
                    severity: .low,
                    message_ko: "불필요한 공백이 포함됨: '\(trimmed)'",
                    message_en: "Unnecessary whitespace: '\(trimmed)'",
                    suggestion_ko: "여분의 공백을 제거하세요.",
                    suggestion_en: "Remove unnecessary whitespace."
                ))
            }
            // 중복 공백
            if trimmed.contains("var  ") {
                warnings.append(Warning(
                    id: UUID(),
                    filePath: filePath,
                    line: idx+1,
                    type: .styleViolation,
                    severity: .low,
                    message_ko: "중복 공백이 포함됨: '\(trimmed)'",
                    message_en: "Duplicated whitespace: '\(trimmed)'",
                    suggestion_ko: "중복된 공백을 하나로 줄이세요.",
                    suggestion_en: "Reduce duplicated whitespace to a single space."
                ))
            }
            // 클래스명/상속 누락
            if trimmed.contains("class ") && !trimmed.contains(":") {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .styleViolation, severity: .low,
                    message_ko: "클래스 선언에 상속/프로토콜 누락 가능성: '\(trimmed)'",
                    message_en: "Possible missing inheritance/protocol in class declaration: '\(trimmed)'",
                    suggestion_ko: "상속 또는 프로토콜 채택 여부 확인",
                    suggestion_en: "Check inheritance or protocol adoption"
                ))
            }
            // 타입 네이밍 규칙(UpperCamel)
            if let m = trimmed.range(of: #"^(class|struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) {
                let name = String(trimmed[m].split(separator: " ")[1])
                if name.prefix(1).lowercased() == name.prefix(1) {
                    warnings.append(Warning(
                        id: UUID(),
                        filePath: filePath,
                        line: idx+1,
                        type: .styleViolation,
                        severity: .low,
                        message_ko: "타입명 네이밍 규칙 위반: \(name)",
                        message_en: "Type name does not follow UpperCamelCase: \(name)",
                        suggestion_ko: "UpperCamelCase 사용 권장",
                        suggestion_en: "Use UpperCamelCase"
                    ))
                }
            }
            // 함수명 네이밍 규칙
            if let funcRange = trimmed.range(of: #"func\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) {
                let fname = String(trimmed[funcRange].split(separator: " ")[1].split(separator:"(")[0])
                if fname.contains("_") {
                    warnings.append(Warning(
                        id: UUID(),
                        filePath: filePath,
                        line: idx+1,
                        type: .styleViolation,
                        severity: .low,
                        message_ko: "함수명 네이밍 규칙 위반: \(fname)",
                        message_en: "Function name does not follow camelCase: \(fname)",
                        suggestion_ko: "camelCase 사용 권장",
                        suggestion_en: "Use camelCase"
                    ))
                }
            }
        }
        // 긴 파일 경고 (1200줄 초과)
        if lines.count > 1200 {
            warnings.append(Warning(
                id: UUID(), filePath: filePath, line: nil, type: .longFile, severity: .medium,
                message_ko: "파일이 너무 깁니다 (\(lines.count)줄, 1200줄 초과)",
                message_en: "File is too long (\(lines.count) lines, over 1200 lines)",
                suggestion_ko: "파일을 분할하는 것을 고려하세요.",
                suggestion_en: "Consider splitting the file."
            ))
        }
        return warnings
    }

    // 5. 보안 관련 문제 탐지
    private static func findSecurityIssues(lines: [String], filePath: String) -> [Warning] {
        var warnings: [Warning] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("password") || trimmed.contains("key") || trimmed.contains("secret") {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .securityIssue, severity: .high,
                    message_ko: "보안 관련 키워드 노출 감지: '\(trimmed)'",
                    message_en: "Security sensitive keyword detected: '\(trimmed)'",
                    suggestion_ko: "민감정보 노출 주의",
                    suggestion_en: "Beware of sensitive information exposure"
                ))
            }
            if trimmed.contains("public ") && trimmed.contains("var ") && !trimmed.contains("{ get") {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .improperAccessControl, severity: .medium,
                    message_ko: "public var의 과도 노출 가능성: '\(trimmed)'",
                    message_en: "Potential overexposure of public var: '\(trimmed)'",
                    suggestion_ko: "접근제어자를 검토하세요.",
                    suggestion_en: "Review access control modifiers"
                ))
            }
        }
        return warnings
    }

    // 6. 미해결 태그 (TODO, FIXME) 탐지
    private static func findUnresolvedTags(lines: [String], filePath: String) -> [Warning] {
        var warnings: [Warning] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("FIXME") || trimmed.contains("TODO") {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .unresolvedTag, severity: .info,
                    message_ko: "미해결 태그 발견: '\(trimmed)'",
                    message_en: "Unresolved tag found: '\(trimmed)'",
                    suggestion_ko: "작업이 끝났으면 태그를 제거하세요.",
                    suggestion_en: "Remove the tag after completion"
                ))
            }
        }
        return warnings
    }

    // 주석/공백/코드 줄 분석
    static func analyzeLineTypes(_ content: String) -> (code: Int, comment: Int, blank: Int) {
        let lines = content.components(separatedBy: .newlines)
        var code = 0, comment = 0, blank = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { blank += 1 }
            else if trimmed.hasPrefix("//") { comment += 1 }
            else { code += 1 }
        }
        return (code, comment, blank)
    }

    // 함수/평균길이/경고 진단
    static func analyzeFunctions(_ content: String) -> (count: Int, avgLen: Double, maxLen: Int, warnings: [String]) {
        let lines = content.components(separatedBy: .newlines)
        var funcLines: [Int] = []
        var inFunc = false
        var currentLen = 0
        for line in lines {
            if line.contains("func ") {
                if inFunc { funcLines.append(currentLen) }
                inFunc = true; currentLen = 1
            } else if inFunc {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("}") {
                    funcLines.append(currentLen)
                    inFunc = false; currentLen = 0
                } else {
                    currentLen += 1
                }
            }
        }
        if inFunc { funcLines.append(currentLen) }
        let warnings: [String] = funcLines.filter { $0 > 50 }.map { "함수 \(funcLines.firstIndex(of: $0) ?? 0 + 1): \( $0 )줄 (50줄↑)" }
        let avg = funcLines.isEmpty ? 0 : Double(funcLines.reduce(0, +)) / Double(funcLines.count)
        return (funcLines.count, avg, funcLines.max() ?? 0, warnings)
    }


    static func findSwiftFiles(at path: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return [] }
        var swiftFiles: [String] = []
        for case let file as String in enumerator {
            if file.hasSuffix(".swift") {
                let fullPath = (path as NSString).appendingPathComponent(file)
                swiftFiles.append(fullPath)
            }
        }
        return swiftFiles
    }

    static func parseDeclarations(from content: String) -> [String] {
        let pattern = #"(?m)^\s*((public)\s+)?(class|struct|enum|protocol)\s+(\w+)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        return matches.map {
            let accessRange = $0.range(at: 2)
            let keywordRange = $0.range(at: 3)
            let nameRange = $0.range(at: 4)
            let access = accessRange.location != NSNotFound ? "public " : ""
            let keyword = String(content[Range(keywordRange, in: content)!])
            let name = String(content[Range(nameRange, in: content)!])
            return "\(access)\(keyword) \(name)"
        }
    }

    static func parsePublicMethods(from content: String) -> ([String], [String]) {
        let pattern = #"(?m)^\s*public\s+func\s+([^\(]+\(.*\))"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let allMethods = matches.map {
            let nsRange = $0.range(at: 1)
            return String(content[Range(nsRange, in: content)!])
        }

        let flowKeywords = ["setup", "start", "handle", "render", "update", "load", "init"]
        let topLevelFlowMethods = allMethods.filter { method in
            flowKeywords.contains { keyword in method.contains(keyword) }
        }

        return (allMethods, topLevelFlowMethods)
    }

    static func generateDocs(for filePath: String, relativePath: String, outputPath: String) {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return
        }
        let declarations = parseDeclarations(from: content)
        let (methods, topLevelFlow) = parsePublicMethods(from: content)
        let fileName = (relativePath as NSString).lastPathComponent
        let lang = DocGenCore.currentLanguage
        func label(_ ko: String, _ en: String) -> String {
            switch lang {
            case "en": return en
            case "ko": fallthrough
            default: return "\(ko) (\(en))"
            }
        }
        var doc = "# \(fileName) — \(relativePath)\n\n"
        doc += "---\n\n"
        doc += "## \(label("선언부", "Declarations")) (\(declarations.count))\n\n"
        if declarations.isEmpty {
            doc += "_\(label("선언 없음", "No declarations found"))_\n\n"
        } else {
            doc += "swift\n"
            declarations.forEach { doc += "\($0)\n" }
            doc += "\n\n"
        }
        doc += "---\n\n"
        doc += "## \(label("공개 메서드", "Public Methods")) (\(methods.count))\n\n"
        if methods.isEmpty {
            doc += "_\(label("공개 메서드 없음", "No public methods found"))_\n\n"
        } else {
            doc += "swift\n"
            methods.forEach { doc += "func \($0)\n" }
            doc += "\n\n"
        }
        doc += "---\n\n"
        doc += "## \(label("최상위 흐름 후보", "Top-Level Flow Candidates")) (\(topLevelFlow.count))\n\n"
        if topLevelFlow.isEmpty {
            doc += "_\(label("최상위 orchestrator 없음", "No top-level orchestrators found"))_\n\n"
        } else {
            doc += "swift\n"
            topLevelFlow.forEach { doc += "func \($0)\n" }
            doc += "\n\n"
        }
        let outputFilePath = (outputPath as NSString).appendingPathComponent((relativePath as NSString).deletingPathExtension + ".md")
        let outputDir = (outputFilePath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return
        }
        do {
            try doc.write(toFile: outputFilePath, atomically: true, encoding: .utf8)
        } catch {
            return
        }
    }

    static func generateSummaryIndex(
        from docs: [(String, [String], [String], [String])],
        outputPath: String,
        fileAnalyses: [FileAnalysisResult],
        totalLineCount: Int,
        totalFunc: Int,
        commentMsg: String,
        qualityMsg: String
    ) {
        let lang = DocGenCore.currentLanguage
        func label(_ ko: String, _ en: String) -> String {
            switch lang {
            case "en": return en
            case "ko": fallthrough
            default: return "\(ko) (\(en))"
            }
        }
        var index = "# SSC Documentation Index\n\n"
        index += "## \(label("전체 통계", "Summary"))\n"
        index += "- \(label("전체 파일", "Total files")): \(fileAnalyses.count)\n"
        index += "- \(label("전체 줄수", "Total lines")): \(totalLineCount)\n"
        index += "- \(label("전체 함수", "Total functions")): \(totalFunc)\n"
        index += "- \(label("품질 진단", "Quality diagnosis")): \(qualityMsg), \(commentMsg)\n\n"
        index += "## \(label("파일별 상세", "Per-file details"))\n"
        for f in fileAnalyses {
            index += "### \(f.file)\n"
            index += "- \(label("줄수", "Lines")): \(f.lines), \(label("코드", "Code")): \(f.codeLines), \(label("주석", "Comments")): \(f.commentLines), \(label("공백", "Blank")): \(f.blankLines)\n"
            index += "- \(label("함수", "Functions")): \(f.funcCount), \(label("평균 함수길이", "Avg. function length")): \(String(format: "%.1f", f.avgFuncLength)), \(label("가장 긴 함수", "Longest function")): \(f.longestFunc)\n"
            if !f.warnings.isEmpty {
                let detailedWarningsText = f.warnings.map { warning -> String in
                    let lineInfo = warning.line != nil ? " (L\(warning.line ?? 0))" : ""
                    return "[\(warning.severity.displayName)/\(warning.type.display)] \(DocGenCore.wrap(warning.message))\(lineInfo)"
                }.joined(separator: " | ")
                index += "- \(label("상세 경고", "Detailed Warnings")): \(detailedWarningsText)\n"
            }
            index += "\n"
        }
        let indexPath = (outputPath as NSString).appendingPathComponent("SUMMARY_INDEX.md")
        do { try index.write(toFile: indexPath, atomically: true, encoding: .utf8) } catch {}
    }
}

