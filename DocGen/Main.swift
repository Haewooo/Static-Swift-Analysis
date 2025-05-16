//
//  Main.swift
//  DocGen
//

import Foundation

class DocGenCore {
    
    // 파일별 통계 구조체 및 경고 모델
    enum WarningType: String, CaseIterable, Identifiable {
        case longFunction = "긴 함수"
        case highComplexity = "높은 복잡도"
        case magicNumber = "매직 넘버 사용"
        case unusedVariable = "미사용 변수"
        case styleViolation = "코드 스타일 위반"
        case securityIssue = "보안 관련 경고"
        case duplicateFunctionName = "중복 함수명"
        case longFile = "긴 파일 (600줄 초과)"
        case unresolvedTag = "미해결 태그 (TODO, FIXME)"
        case improperAccessControl = "부적절한 접근 제어"
        var id: String { self.rawValue }
    }

    enum Severity: Int, Comparable {
        case info = 0
        case low = 1
        case medium = 2
        case high = 3
        case critical = 4
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
        var displayName: String {
            switch self {
            case .info: return "정보"
            case .low: return "낮음"
            case .medium: return "중간"
            case .high: return "높음"
            case .critical: return "심각"
            }
        }
    }

    struct Warning: Identifiable, Equatable {
        let id: UUID
        let filePath: String
        let line: Int?
        let type: WarningType
        let severity: Severity
        let message: String
        let suggestion: String?
        static func == (lhs: Warning, rhs: Warning) -> Bool {
            lhs.id == rhs.id
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
        var totalQualityScore = 100.0
        var smellCount = 0

        for filePath in swiftFiles {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            let relativePath = filePath.replacingOccurrences(of: rootPath + "/", with: "")
            let (code, comment, blank) = analyzeLineTypes(content)
            let (funcCount, avgFuncLen, maxFuncLen, fileWarnings) = analyzeAdvanced(content: content, filePath: relativePath)
            let lines = content.components(separatedBy: .newlines).count

            // 품질점수 감점
            var fileQualityScore = 100.0
            fileQualityScore -= Double(fileWarnings.count * 2)
            if lines > 600 { fileQualityScore -= 5 }
            if avgFuncLen > 40 { fileQualityScore -= 5 }
            if fileQualityScore < 0 { fileQualityScore = 0 }

            smellCount += fileWarnings.count
            totalQualityScore += fileQualityScore

            fileAnalyses.append(FileAnalysisResult(
                id: UUID(),
                file: relativePath,
                lines: lines,
                codeLines: code,
                commentLines: comment,
                blankLines: blank,
                funcCount: funcCount,
                avgFuncLength: avgFuncLen,
                longestFunc: maxFuncLen,
                warnings: fileWarnings
            ))
            totalLineCount += lines
            totalCode += code; totalComment += comment; totalBlank += blank
            totalFunc += funcCount
            warnings.append(contentsOf: fileWarnings)
            generateDocs(for: filePath, relativePath: relativePath, outputPath: outputPath)
        }

        let commentRate = totalCode == 0 ? 0 : Double(totalComment) / Double(totalCode) * 100
        let qualityMsg = "품질점수: \(String(format:"%.1f",totalQualityScore/Double(max(swiftFiles.count,1))))/100"
        let commentMsg = commentRate < 7 ? "주석률 낮음(\(String(format: "%.1f", commentRate))%)" : "주석 적정(\(String(format: "%.1f", commentRate))%)"

        generateSummaryIndex(
            from: fileAnalyses.map { ($0.file, [], [], []) },
            outputPath: outputPath,
            fileAnalyses: fileAnalyses,
            totalLineCount: totalLineCount,
            totalFunc: totalFunc,
            commentMsg: commentMsg,
            qualityMsg: qualityMsg
        )

        let warningText = warnings.isEmpty ? "특이 경고 없음." : warnings.map { w in
            let linePart = w.line != nil ? " (line \(w.line!))" : ""
            return "(\(w.filePath))\(linePart): [\(w.type.rawValue)] \(w.message)"
        }.joined(separator: "\n")
        let resultMsg = """
        완료: \(swiftFiles.count)개 파일 분석됨.
        전체 줄수: \(totalLineCount) / 코드: \(totalCode) / 주석: \(totalComment) / 공백: \(totalBlank)
        함수: \(totalFunc), 평균 함수길이: \((totalFunc>0) ? String(format: "%.1f",Double(totalCode)/Double(totalFunc)) : "0")
        주석률: \(String(format: "%.1f", commentRate))%
        \(qualityMsg) / \(commentMsg)
        코드스멜/복잡도/보안/컨벤션/미사용 변수/매직넘버/스타일 위반 등 감지 건수: \(smellCount)
        경고:
        \(warningText)
        """

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

    // advanced analysis using Warning objects and modularized helpers
    static func analyzeAdvanced(content: String, filePath: String) -> (
        funcCount: Int, avgFuncLen: Double, maxFuncLen: Int, warnings: [Warning]
    ) {
        var allWarnings: [Warning] = []
        let lines = content.components(separatedBy: .newlines)
        // 1. 함수 관련 지표 및 경고 분석
        let funcAnalysisResult = analyzeFunctionMetrics(lines: lines, filePath: filePath)
        allWarnings.append(contentsOf: funcAnalysisResult.warnings)
        // 2. 매직 넘버 탐지
        allWarnings.append(contentsOf: findMagicNumbers(lines: lines, filePath: filePath))
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
                        warnings.append(Warning(id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .highComplexity, severity: .high, message: "함수 '\(fName)'의 Cyclomatic Complexity가 \(currentCyclomatic)으로 높습니다 (12 이하 권장).", suggestion: "함수를 더 작은 단위로 분리하거나 로직을 단순화하세요."))
                    }
                    for v in localVars where !usedVars.contains(v) {
                        warnings.append(Warning(id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .unusedVariable, severity: .low, message: "함수 '\(fName)' 내 지역 변수/상수 '\(v)'가 사용되지 않았습니다.", suggestion: "불필요하면 제거하세요."))
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
                            warnings.append(Warning(id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .highComplexity, severity: .high, message: "함수 '\(fName)'의 Cyclomatic Complexity가 \(currentCyclomatic)으로 높습니다 (12 이하 권장).", suggestion: "함수를 더 작은 단위로 분리하거나 로직을 단순화하세요."))
                        }
                        for v in localVars where !usedVars.contains(v) {
                            warnings.append(Warning(id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .unusedVariable, severity: .low, message: "함수 '\(fName)' 내 지역 변수/상수 '\(v)'가 사용되지 않았습니다.", suggestion: "불필요하면 제거하세요."))
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
                warnings.append(Warning(id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .highComplexity, severity: .high, message: "함수 '\(fName)'의 Cyclomatic Complexity가 \(currentCyclomatic)으로 높습니다 (12 이하 권장).", suggestion: "함수를 더 작은 단위로 분리하거나 로직을 단순화하세요."))
            }
            for v in localVars where !usedVars.contains(v) {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: currentFuncStartLine, type: .unusedVariable, severity: .low, message: "함수 '\(fName)' 내 지역 변수/상수 '\(v)'가 사용되지 않았습니다.", suggestion: "불필요하면 제거하세요."))
            }
            allLocalVariablesInFunctions[fName] = (localVars, usedVars)
        }
        for (idx, lenInfo) in funcLens.enumerated() where lenInfo > 50 {
            warnings.append(Warning(id: UUID(), filePath: filePath, line: nil, type: .longFunction, severity: .medium, message: "함수 (순서: \(idx+1))의 길이가 \(lenInfo)줄로 너무 깁니다 (50줄 이하 권장).", suggestion: "함수를 더 작은 단위로 분리하는 것을 고려하세요."))
        }
        for (name, count) in funcNameCounts where count > 1 {
            warnings.append(Warning(id: UUID(), filePath: filePath, line: funcNameToLine[name], type: .duplicateFunctionName, severity: .medium, message: "함수명 '\(name)'이(가) 파일 내에서 \(count)번 중복 정의되었습니다.", suggestion: "함수명을 다르게 하거나, 오버로딩이 올바르게 되었는지 확인하세요."))
        }
        let maxLen = funcLens.max() ?? 0
        let avgLen = funcLens.isEmpty ? 0.0 : Double(funcLens.reduce(0, +)) / Double(funcLens.count)
        return (funcCount, avgLen, maxLen, warnings, allLocalVariablesInFunctions)
    }

    // 2. 매직 넘버 탐지
    private static func findMagicNumbers(lines: [String], filePath: String) -> [Warning] {
        var warnings: [Warning] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.contains("//") else { continue }
            let numberPattern = #"\b\d+\b"#
            if let regex = try? NSRegularExpression(pattern: numberPattern), let _ = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .magicNumber, severity: .medium, message: "매직 넘버가 코드에 직접 포함되어 있습니다: '\(trimmed)'", suggestion: "상수로 추출하여 의미를 명확히 하세요."))
            }
        }
        return warnings
    }

    // 3. 미사용 파일 레벨 변수 탐지
    private static func findUnusedFileLevelVariables(lines: [String], filePath: String, functionLocalVariables: [String: ([String], Set<String>)]) -> [Warning] {
        var warnings: [Warning] = []
        var fileLevelVars: [String: Int] = [:]
        var usedFileVars: Set<String> = []
        var inTypeDecl: Bool = false
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: #"^(class|struct|enum)\s"#, options: .regularExpression) != nil {
                inTypeDecl = true
            }
            if let range = trimmed.range(of: #"^(var|let)\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression), !inTypeDecl {
                let name = String(trimmed[range].split(separator: " ")[1])
                fileLevelVars[name] = idx+1
            }
            for v in fileLevelVars.keys {
                if trimmed.range(of: "\\b\(v)\\b", options: .regularExpression) != nil {
                    usedFileVars.insert(v)
                }
            }
        }
        for (v, lineNum) in fileLevelVars where !usedFileVars.contains(v) {
            warnings.append(Warning(id: UUID(), filePath: filePath, line: lineNum, type: .unusedVariable, severity: .low, message: "파일 레벨 변수/상수 '\(v)'가 사용되지 않았습니다.", suggestion: "불필요하다면 삭제하세요."))
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
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .styleViolation, severity: .low, message: "불필요한 공백이 포함됨: '\(trimmed)'", suggestion: nil))
            }
            // 중복 공백
            if trimmed.contains("var  ") {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .styleViolation, severity: .low, message: "중복 공백이 포함됨: '\(trimmed)'", suggestion: nil))
            }
            // 클래스명/상속 누락
            if trimmed.contains("class ") && !trimmed.contains(":") {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .styleViolation, severity: .low, message: "클래스 선언에 상속/프로토콜 누락 가능성: '\(trimmed)'", suggestion: "상속 또는 프로토콜 채택 여부 확인"))
            }
            // 타입 네이밍 규칙(UpperCamel)
            if let m = trimmed.range(of: #"^(class|struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) {
                let name = String(trimmed[m].split(separator: " ")[1])
                if name.prefix(1).lowercased() == name.prefix(1) {
                    warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .styleViolation, severity: .low, message: "타입명 네이밍 규칙 위반: \(name)", suggestion: "UpperCamelCase 사용 권장"))
                }
            }
            // 함수명 네이밍 규칙
            if let funcRange = trimmed.range(of: #"func\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) {
                let fname = String(trimmed[funcRange].split(separator: " ")[1].split(separator:"(")[0])
                if fname.contains("_") {
                    warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .styleViolation, severity: .low, message: "함수명 네이밍 규칙 위반: \(fname)", suggestion: "camelCase 사용 권장"))
                }
            }
        }
        // 긴 파일 경고
        if lines.count > 600 {
            warnings.append(Warning(id: UUID(), filePath: filePath, line: nil, type: .longFile, severity: .medium, message: "파일이 너무 깁니다 (\(lines.count)줄, 600줄 초과)", suggestion: "파일을 분할하는 것을 고려하세요."))
        }
        return warnings
    }

    // 5. 보안 관련 문제 탐지
    private static func findSecurityIssues(lines: [String], filePath: String) -> [Warning] {
        var warnings: [Warning] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("password") || trimmed.contains("key") || trimmed.contains("secret") {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .securityIssue, severity: .high, message: "보안 관련 키워드 노출 감지: '\(trimmed)'", suggestion: "민감정보 노출 주의"))
            }
            if trimmed.contains("public ") && trimmed.contains("var ") && !trimmed.contains("{ get") {
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .improperAccessControl, severity: .medium, message: "public var의 과도 노출 가능성: '\(trimmed)'", suggestion: "접근제어자를 검토하세요."))
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
                warnings.append(Warning(id: UUID(), filePath: filePath, line: idx+1, type: .unresolvedTag, severity: .info, message: "미해결 태그 발견: '\(trimmed)'", suggestion: "작업이 끝났으면 태그를 제거하세요."))
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

        var doc = "# \(fileName) — \(relativePath)\n\n"
        doc += "---\n\n"
        doc += "## Declarations (\(declarations.count))\n\n"
        if declarations.isEmpty {
            doc += "_No declarations found._\n\n"
        } else {
            doc += "swift\n"
            declarations.forEach { doc += "\($0)\n" }
            doc += "\n\n"
        }
        doc += "---\n\n"
        doc += "## Public Methods (\(methods.count))\n\n"
        if methods.isEmpty {
            doc += "_No public methods found._\n\n"
        } else {
            doc += "swift\n"
            methods.forEach { doc += "func \($0)\n" }
            doc += "\n\n"
        }
        doc += "---\n\n"
        doc += "## Top-Level Flow Candidates (\(topLevelFlow.count))\n\n"
        if topLevelFlow.isEmpty {
            doc += "_No top-level orchestrators found._\n\n"
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
        var index = "# SSC Documentation Index\n\n"
        index += "## 전체 통계\n"
        index += "- 전체 파일: \(fileAnalyses.count)\n- 전체 줄수: \(totalLineCount)\n- 전체 함수: \(totalFunc)\n"
        index += "- 품질 진단: \(qualityMsg), \(commentMsg)\n\n"
        index += "## 파일별 상세\n"
        for f in fileAnalyses {
            index += "### \(f.file)\n- 줄수: \(f.lines), 코드: \(f.codeLines), 주석: \(f.commentLines), 공백: \(f.blankLines)\n"
            index += "- 함수: \(f.funcCount), 평균 함수길이: \(String(format: "%.1f", f.avgFuncLength)), 가장 긴 함수: \(f.longestFunc)\n"
            if !f.warnings.isEmpty {
                let detailedWarningsText = f.warnings.map { warning -> String in
                    let lineInfo = warning.line.map { " (L\($0))" } ?? "" // 라인 정보가 있으면 " (L라인번호)" 형태로, 없으면 빈 문자열
                    return "[\(warning.severity.displayName)/\(warning.type.rawValue)] \(warning.message)\(lineInfo)"
                }.joined(separator: " | ") 
                index += "- 상세 경고: \(detailedWarningsText)\n"
            }
            index += "\n"
        }
        let indexPath = (outputPath as NSString).appendingPathComponent("SUMMARY_INDEX.md")
        do { try index.write(toFile: indexPath, atomically: true, encoding: .utf8) } catch {}
    }
}
