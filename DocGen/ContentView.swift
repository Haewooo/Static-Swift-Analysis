//
//  ContentView.swift
//  DocGen
//


import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    // 언어 목록 및 선택 상태
    @AppStorage("AppLanguage") private var appLanguage: String = "ko"
    @State private var rootPath: String = ""
    @State private var outputPath: String = ""
    @State private var status: String = DocGenCore.currentLanguage == "en" ? "Ready to start analysis." : "시작할 준비가 되었습니다."
    @State private var isProcessing: Bool = false
    @State private var logMessages: [String] = []
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var recentRootPaths: [String] = []
    @State private var recentOutputPaths: [String] = []
    @State private var showDetailedResult: Bool = true

    @State private var analyses: [DocGenCore.FileAnalysisResult] = []
    @State private var totalLines: Int = 0
    @State private var totalFuncs: Int = 0
    @State private var totalComments: Int = 0
    @State private var totalBlanks: Int = 0
    @State private var commentRate: Double = 0
    @State private var qualityMsg: String = ""
    @State private var overallProjectWarnings: [DocGenCore.Warning] = []

    @State private var fileSearch: String = ""
    @State private var sortKey: String = "품질점수"
    @State private var sortDesc: Bool = true
    @State private var selectedFileID: DocGenCore.FileAnalysisResult.ID? = nil
    
    // 한/영 텍스트 전환 헬퍼
    private func label(_ ko: String, _ en: String) -> String {
        let lang = DocGenCore.currentLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lang.hasPrefix("en") {
            return en
        } else {
            return ko
        }
    }

    var selectedFile: DocGenCore.FileAnalysisResult? {
        guard let selectedID = selectedFileID else { return nil }
        return analyses.first { $0.id == selectedID }
    }

    var filteredAnalyses: [DocGenCore.FileAnalysisResult] {
        var arr = analyses
        if !fileSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arr = arr.filter {
                $0.file.lowercased().contains(fileSearch.lowercased()) ||
                $0.warnings.contains(where: { warning in
                    warning.message.lowercased().contains(fileSearch.lowercased()) ||
                    warning.type.rawValue.lowercased().contains(fileSearch.lowercased())
                })
            }
        }
        switch sortKey {
        case "파일명":
            arr = arr.sorted { sortDesc ? $0.file > $1.file : $0.file < $1.file }
        case "품질점수":
            arr = arr.sorted { sortDesc ? fileQualityScore($0) > fileQualityScore($1) : fileQualityScore($0) < fileQualityScore($1) }
        case "경고수":
            arr = arr.sorted { sortDesc ? $0.warnings.count > $1.warnings.count : $0.warnings.count < $1.warnings.count }
        default:
            break
        }
        return arr
    }

    var overallQualityGrade: (label: String, color: Color) {
        let score = avgFileQualityScore
        if score >= 95 { return ("A+", .green) }
        if score >= 90 { return ("A", .green) }
        if score >= 80 { return ("B", .teal) }
        if score >= 70 { return ("C", .yellow) }
        if score >= 60 { return ("D", .orange) }
        return ("F", .red)
    }

    var avgFileQualityScore: Double {
        guard !analyses.isEmpty else { return 0 }
        let total = analyses.map { fileQualityScore($0) }.reduce(0, +)
        return total / Double(analyses.count)
    }

    /// 파일 품질점수 산정 공식(상한/하한, 감점 항목 구조화)
    func fileQualityScore(_ f: DocGenCore.FileAnalysisResult) -> Double {
        // 점수 상한/하한(사용자 커스텀 가능)
        let maxScore: Double = 100.0
        let minScore: Double = 0.0

        // 감점 기준(사용자 커스텀 가능)
        let penaltyCritical: Double = 5.0
        let penaltyHigh: Double = 3.0
        let penaltyMedium: Double = 2.0
        let penaltyLow: Double = 1.0
        let penaltyInfo: Double = 0.0
        let penaltyLongFunc: Double = 5.0 // 긴 함수 경고 감점
        let penaltyManyLines: Double = 5.0 // 파일 라인 수 초과 감점
        let penaltyLongAvgFunc: Double = 5.0 // 평균 함수 길이 초과 감점
        let longFuncThreshold: Int = 40 // 긴 함수 기준
        let manyLinesThreshold: Int = 600 // 파일 라인 수 기준

        var score = maxScore

        // 1. 경고별 감점 (중복 감점 방지: 긴 함수 경고는 별도 처리)
        var longFunctionWarned = false
        for warning in f.warnings {
            // 긴 함수 경고는 별도 집계
            if warning.type == .longFunction {
                longFunctionWarned = true
                continue
            }
            switch warning.severity {
            case .critical: score -= penaltyCritical
            case .high: score -= penaltyHigh
            case .medium: score -= penaltyMedium
            case .low: score -= penaltyLow
            case .info: score -= penaltyInfo
            }
        }

        // 2. 긴 함수 경고 감점 (여러 개여도 1회만 감점)
        if longFunctionWarned {
            score -= penaltyLongFunc
        }

        // 3. 파일 라인 수, 평균 함수 길이 감점
        // 긴 함수 경고가 있으면 중복 감점 방지(긴 함수 경고가 없을 때만 적용)
        if !longFunctionWarned {
            if f.lines > manyLinesThreshold {
                score -= penaltyManyLines
            }
            if f.avgFuncLength > Double(longFuncThreshold) {
                score -= penaltyLongAvgFunc
            }
        }

        // 점수 상한/하한을 min/max로 보장
        return min(maxScore, max(minScore, score))
    }

    func warningColor(_ severity: DocGenCore.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .info: return .gray
        }
    }
    func severityIcon(_ severity: DocGenCore.Severity) -> String {
        switch severity {
        case .critical: return "exclamationmark.octagon.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "info.circle.fill"
        case .info: return "questionmark.circle.fill"
        }
    }

    private var codePct: Double {
        let total = totalLines
        return Double(totalLines - totalComments - totalBlanks) / Double(max(total, 1)) * 100
    }
    private var commentPct: Double {
        let total = totalLines
        return Double(totalComments) / Double(max(total, 1)) * 100
    }
    private var blankPct: Double {
        let total = totalLines
        return Double(totalBlanks) / Double(max(total, 1)) * 100
    }

    private var pathInputGroup: some View {
        GroupBox(label: Label(label("분석 범위 및 출력", "Analysis Range & Output"), systemImage: "folder")) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(label("루트 경로:", "Root Path:")).frame(width: 82, alignment: .leading)
                    TextField(label("예: /Users/yourname/Project", "e.g. /Users/yourname/Project"), text: $rootPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .contextMenu {
                            ForEach(recentRootPaths, id: \.self) { path in
                                Button(path) { rootPath = path }
                            }
                        }
                    Button(label("찾기", "Browse")) { selectPath(isDirectory: true) { selected in rootPath = selected } }
                    Button(action: { copyToClipboard(rootPath) }) {
                        Image(systemName: "doc.on.doc").help(label("경로 복사", "Copy Path"))
                    }
                }
                HStack(spacing: 8) {
                    Text(label("출력 경로:", "Output Path:")).frame(width: 82, alignment: .leading)
                    TextField(label("예: /Users/yourname/Docs", "e.g. /Users/yourname/Docs"), text: $outputPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .contextMenu {
                            ForEach(recentOutputPaths, id: \.self) { path in
                                Button(path) { outputPath = path }
                            }
                        }
                    Button(label("찾기", "Browse")) { selectPath(isDirectory: true) { selected in outputPath = selected } }
                    Button(action: { copyToClipboard(outputPath) }) {
                        Image(systemName: "doc.on.doc").help(label("경로 복사", "Copy Path"))
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var overallQualityHeader: some View {
        HStack(alignment: .center) {
            Label(label("전체 품질", "Overall Quality"), systemImage: "chart.bar.xaxis")
                .font(.headline)
            Text(overallQualityGrade.label)
                .bold()
                .foregroundColor(overallQualityGrade.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(overallQualityGrade.color.opacity(0.14))
                .clipShape(Capsule())
            Spacer()
            Text(label("평균 파일 품질점수: \(String(format: "%.1f", avgFileQualityScore))/100", "Avg File Quality Score: \(String(format: "%.1f", avgFileQualityScore))/100"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var statisticsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label("전체 통계", "Statistics")).font(.headline)
            Label(label("총 파일 수: \(analyses.count)", "Total Files: \(analyses.count)"), systemImage: "doc.on.doc.fill")
            Label(label("총 라인 수: \(totalLines)", "Total Lines: \(totalLines)"), systemImage: "text.alignleft")
            Label(label("총 함수 수: \(totalFuncs)", "Total Functions: \(totalFuncs)"), systemImage: "function")
            Label(label("총 주석 수: \(totalComments)", "Total Comments: \(totalComments)"), systemImage: "text.bubble")
            Label(label("총 공백 라인 수: \(totalBlanks)", "Total Blank Lines: \(totalBlanks)"), systemImage: "rectangle.and.pencil.and.ellipsis")
            Label(label(String(format: "주석률: %.1f%%", commentRate), String(format: "Comment Rate: %.1f%%", commentRate)), systemImage: "percent")
            if !qualityMsg.isEmpty {
                Label(qualityMsg, systemImage: "checkmark.seal")
                    .foregroundColor(.blue)
                    .font(.subheadline)
            }
        }
        .frame(minWidth: 200, alignment: .topLeading)
    }

    private var overallDistributionChart: some View {
        Chart {
            BarMark(
                x: .value(label("비율", "Ratio"), codePct),
                y: .value(label("구성", "Category"), label("전체 코드", "Code"))
            )
                .foregroundStyle(Color.blue.opacity(0.85))
                .annotation(position: .overlay) {
                    Text(label(String(format: "%.0f%% 코드", codePct), String(format: "%.0f%% Code", codePct)))
                        .font(.caption2)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 0.5)
                }
            BarMark(
                x: .value(label("비율", "Ratio"), commentPct),
                y: .value(label("구성", "Category"), label("전체 코드", "Code"))
            )
                .foregroundStyle(Color.teal)
                .annotation(position: .overlay) {
                    Text(label(String(format: "%.0f%% 주석", commentPct), String(format: "%.0f%% Comment", commentPct)))
                        .font(.caption2)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 0.5)
                }
            BarMark(
                x: .value(label("비율", "Ratio"), blankPct),
                y: .value(label("구성", "Category"), label("전체 코드", "Code"))
            )
                .foregroundStyle(Color.orange.opacity(0.7))
                .annotation(position: .overlay) {
                    Text(label(String(format: "%.0f%% 공백", blankPct), String(format: "%.0f%% Blank", blankPct)))
                        .font(.caption2)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 0.5)
                }
        }
        .frame(height: 70)
        .chartXScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(preset: .extended, values: .stride(by: 20)) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }

    private var fileQualityChart: some View {
        Chart {
            ForEach(filteredAnalyses) { file in
                let score = fileQualityScore(file)
                SectorMark(
                    angle: .value(label("품질점수", "Quality Score"), score),
                    innerRadius: .ratio(0.6),
                    angularInset: 1
                )
                .foregroundStyle(
                    score < 60 ? .red :
                    score < 70 ? .orange :
                    score < 80 ? .yellow :
                    score < 90 ? .teal : .green
                )
                .cornerRadius(3)
                .annotation(position: .overlay) {
                    Text(String(format: "%.0f", score))
                        .font(.caption2)
                        .bold()
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 200, height: 200)
        .chartLegend(.hidden)
        .overlay {
            if analyses.isEmpty && !isProcessing {
                Text(label("분석 데이터 없음", "No analysis data")).foregroundColor(.secondary)
            }
        }
    }

    private var chartsVStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(label("코드 분포", "Code Distribution")).font(.headline)
            overallDistributionChart
            Text(label("파일별 품질 (점수)", "File Quality (Score)")).font(.headline)
                .padding(.top)
            if !analyses.isEmpty {
                fileQualityChart
            } else {
                ContentUnavailableView(label("분석 데이터 없음", "No analysis data"), systemImage: "chart.pie")
                    .frame(height: 200)
            }
        }
        .frame(maxWidth: 330)
    }

    private var warningsSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label("주요 경고 (\(overallProjectWarnings.count)개)", "Top Warnings (\(overallProjectWarnings.count))")).font(.headline)
            if overallProjectWarnings.isEmpty && !isProcessing {
                Label(label("발견된 주요 경고 없음", "No major warnings found"), systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isProcessing {
                ProgressView().scaleEffect(0.8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(overallProjectWarnings.sorted(by: { $0.severity > $1.severity }).prefix(7)) { warning in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(warning.message)
                                        .font(.system(size: 13))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text("\(warning.filePath)\(warning.line.map { ":\($0)" } ?? "") (\(warning.type.rawValue))")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            } icon: {
                                Image(systemName: severityIcon(warning.severity))
                                    .foregroundColor(warningColor(warning.severity))
                            }
                            .help("\(warning.severity.displayName): \(warning.message)\n경로: \(warning.filePath)\(warning.line.map { " (Line \($0))" } ?? "")\n유형: \(warning.type.rawValue)\n제안: \(warning.suggestion ?? "N/A")")
                            .padding(.vertical, 3)
                            .padding(.horizontal, 5)
                            .background(warningColor(warning.severity).opacity(0.1))
                            .cornerRadius(6)
                        }
                        if overallProjectWarnings.count > 7 {
                            Text(label("외 \(overallProjectWarnings.count - 7)건 더 있음 (파일 상세 또는 전체 로그 확인)",
                                       "\(overallProjectWarnings.count - 7) more. See file detail or full log"))
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .frame(minWidth: 250, alignment: .topLeading)
    }

    private var dashboardHStack: some View {
        HStack(alignment: .top, spacing: 20) {
            statisticsSummary
            Divider()
            chartsVStack
            Divider()
            warningsSummary
        }
        .padding(.vertical)
    }

    private var searchSortControls: some View {
        HStack(spacing: 16) {
            TextField(label("파일명/경고 메시지/유형 검색...", "Search filename/warning/type..."), text: $fileSearch)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 320)
            Picker("정렬", selection: $sortKey) {
                Text(label("품질점수", "Quality Score")).tag("품질점수")
                Text(label("경고수", "Warning Count")).tag("경고수")
                Text(label("파일명", "Filename")).tag("파일명")
            }
            .labelsHidden().frame(width: 120)
            Button(action: { sortDesc.toggle() }) {
                Image(systemName: sortDesc ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            Spacer()
            if selectedFileID != nil {
                Button(action: { selectedFileID = nil }) {
                    Label(label("파일 상세 닫기", "Close File Detail"), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.top, 2)
    }

    private var fileTableView: some View {
        Table(filteredAnalyses, selection: $selectedFileID) {
            // "파일명" 컬럼
            TableColumn(label("파일명", "Filename")) { fileAnalysis in
                Text(fileAnalysis.file)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 150, ideal: 250)

            // "품질점수" 컬럼
            TableColumn(label("품질점수", "Quality Score")) { fileAnalysis in
                let score = fileQualityScore(fileAnalysis)
                Text(String(format: "%.1f", score))
                    .foregroundColor(score < 60 ? .red : score < 70 ? .orange : score < 80 ? .yellow : .primary)
                    .fontWeight(score < 70 ? .bold : .regular)
            }
            .width(80)

            // "경고수" 컬럼
            TableColumn(label("경고수", "Warning Count")) { fileAnalysis in
                Text("\(fileAnalysis.warnings.count)")
                    .foregroundColor(fileAnalysis.warnings.filter { $0.severity >= .medium }.count > 0 ? .orange : (fileAnalysis.warnings.count > 0 ? .blue : .secondary))
            }
            .width(60)

            // "라인 수" 컬럼 (value 키 경로 대신 content 클로저 사용)
            TableColumn(label("라인 수", "Line Count")) { fileAnalysis in
                Text("\(fileAnalysis.lines)")
            }
            .width(60)

            // "함수 수" 컬럼 (value 키 경로 대신 content 클로저 사용)
            TableColumn(label("함수 수", "Function Count")) { fileAnalysis in
                Text("\(fileAnalysis.funcCount)")
            }
            .width(60)

            // "평균 함수 길이" 컬럼 (content 클로저 사용)
            TableColumn(label("평균 함수 길이", "Avg Func Length")) { fileAnalysis in
                Text(String(format: "%.1f", fileAnalysis.avgFuncLength))
            }
            .width(100)

            // "가장 긴 함수" 컬럼 (content 클로저 사용)
            TableColumn(label("가장 긴 함수", "Longest Function")) { fileAnalysis in
                Text("\(fileAnalysis.longestFunc)")
            }
            .width(80)

            // "주석률" 컬럼 (content 클로저 사용)
            TableColumn(label("주석률", "Comment Rate")) { fileAnalysis in
                let rate = fileAnalysis.codeLines > 0 ? Double(fileAnalysis.commentLines) / Double(fileAnalysis.codeLines) * 100 : 0
                Text(String(format: "%.1f%%", rate))
            }
            .width(70)
        }
        .frame(minHeight: 220, maxHeight: .infinity)
        // row 클릭 시 selectedFileID만 갱신, showDetailedResult는 사용자가 토글로만 조작
        .overlay {
            if analyses.isEmpty && !isProcessing {
                ContentUnavailableView(label("분석할 파일을 선택하세요.", "Select a file to analyze."), systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    @ViewBuilder
    private func fileDetailGroup(detail: DocGenCore.FileAnalysisResult) -> some View {
        GroupBox(label: Label(label("파일 상세", "File Detail"), systemImage: "doc.plaintext")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(label("총 라인: \(detail.lines), 코드: \(detail.codeLines), 주석: \(detail.commentLines), 공백: \(detail.blankLines)", "Total Lines: \(detail.lines), Code: \(detail.codeLines), Comments: \(detail.commentLines), Blank: \(detail.blankLines)"))
                    Spacer()
                    Text(label("품질 점수: \(String(format: "%.1f", fileQualityScore(detail)))", "Quality Score: \(String(format: "%.1f", fileQualityScore(detail)))"))
                        .bold()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 5)

                if detail.warnings.isEmpty {
                    Label(label("이 파일에는 특이 경고가 없습니다.", "No significant warnings in this file."), systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(label("경고 (\(detail.warnings.count)개):", "Warnings (\(detail.warnings.count)):")).font(.headline).padding(.bottom, 2)
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            // 심각도 높은 순으로 정렬
                            ForEach(detail.warnings.sorted(by: { $0.severity > $1.severity })) { warning in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: severityIcon(warning.severity))
                                        .foregroundColor(warningColor(warning.severity))
                                        .font(.title3)
                                        .frame(width: 25)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("[\(warning.severity.displayName) / \(warning.type.rawValue)] \(warning.message)")
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let line = warning.line {
                                            Text(label("라인: \(line)", "Line: \(line)"))
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        if let suggestion = warning.suggestion, !suggestion.isEmpty {
                                            Text(label("제안: \(suggestion)", "Suggestion: \(suggestion)"))
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(warningColor(warning.severity).opacity(0.08))
                                .cornerRadius(8)
                                .help(label("파일: \(warning.filePath)\n라인: \(warning.line ?? 0)\n유형: \(warning.type.rawValue)\n심각도: \(warning.severity.displayName)",
                                            "File: \(warning.filePath)\nLine: \(warning.line ?? 0)\nType: \(warning.type.rawValue)\nSeverity: \(warning.severity.displayName)"))
                            }
                        }
                    }
                    .frame(minHeight: 150, maxHeight: 300)
                }
            }
            .padding(.vertical, 5)
        }
        .padding(.bottom, 6)
    }

    private var logGroup: some View {
        GroupBox(label: Label(label("실행 로그", "Execution Log"), systemImage: "terminal")) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(logMessages, id: \.self) { msg in
                        Text(msg)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(msg.contains("❌") ? .red : .primary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .frame(minHeight: 80, maxHeight: 120)
        }
    }

    private var statusText: some View {
        Text(status)
            .font(.footnote)
            .foregroundColor(.gray)
            .padding(.top, 6)
    }

    private var actionControls: some View {
        HStack {
            Spacer()
            VStack {
                Spacer(minLength: 20)
                VStack(spacing: 12) {
                    Button(action: runDocGen) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .padding(.trailing, 5)
                                Text(label("분석 중...", "Analyzing..."))
                                    .fontWeight(.semibold)
                            } else {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.title3)
                                Text(label("분석 시작", "Analyze"))
                                    .fontWeight(.semibold)
                                    .font(.headline)
                            }
                        }
                        .frame(width: 180)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background {
                            if !(rootPath.isEmpty || isProcessing) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: .blue.opacity(0.9), location: 0.0),
                                                .init(color: .indigo, location: 0.4),
                                                .init(color: .purple.opacity(0.85), location: 0.7),
                                                .init(color: .pink.opacity(0.9), location: 1.0)
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.3))
                            }
                        }
                        .foregroundColor((rootPath.isEmpty || isProcessing) ? Color.gray.opacity(0.7) : Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(rootPath.isEmpty || isProcessing)
                    .animation(.easeInOut, value: isProcessing)

                    Toggle(isOn: $showDetailedResult) {
                        Text(label("상세 결과 보기", "Show detailed result"))
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .frame(maxWidth: 240)
                }
                .padding(.top, 24) // 버튼을 더 아래로 내림
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }
    

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer()
                        Picker(selection: $appLanguage, label: EmptyView()) {
                            Text("한국어").tag("ko")
                            Text("English").tag("en")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 160)
                        .onChange(of: appLanguage) { newLang in
                            DocGenCore.currentLanguage = newLang
                            status = newLang == "en" ? "Ready to start analysis." : "시작할 준비가 되었습니다."
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .background(Color.clear) // No background

                    HStack(spacing: 0) {
                        Text("Swift")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .blue.opacity(0.9), location: 0.0),
                                        .init(color: .indigo, location: 0.4),
                                        .init(color: .purple.opacity(0.85), location: 0.7),
                                        .init(color: .pink.opacity(0.9), location: 1.0)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text(label(" 정적 분석기", " Static Analyzer"))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1.2)
                    .padding(.bottom, 6)

                    Divider()
                        .padding(.bottom, 2)

                    pathInputGroup
                    overallQualityHeader
                    dashboardHStack
                    Divider()
                    searchSortControls
                    fileTableView
                    if let detail = selectedFile, showDetailedResult {
                        fileDetailGroup(detail: detail)
                    }
                    logGroup
                    Spacer()
                    statusText
                }
                .padding(32)
            }

            VStack(spacing: 0) {
                Divider()
                actionControls
                    .padding()
            }
        }
        .frame(minWidth: 900, idealWidth: 1150, maxWidth: .infinity,
               minHeight: 620, idealHeight: 800, maxHeight: .infinity)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("오류 발생"), message: Text(alertMessage), dismissButton: .default(Text("확인")))
        }
        .onAppear {
            DocGenCore.currentLanguage = appLanguage
            status = appLanguage == "en" ? "Ready to start analysis." : "시작할 준비가 되었습니다."
            #if os(macOS)
            if let window = NSApplication.shared.windows.first {
                window.isMovableByWindowBackground = true
            }
            #endif
        }
    }

    private func severityDescription(_ severity: Int) -> String {
        switch severity {
        case 4: return "심각(Critical) 위험도"
        case 3: return "높음(High) 위험도"
        case 2: return "중간(Medium) 위험도"
        case 1: return "낮음(Low) 위험도"
        default: return "정보(Info)"
        }
    }

    private func selectPath(isDirectory: Bool, set: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !isDirectory
        panel.canChooseDirectories = isDirectory
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            set(url.path)
        }
    }

    private func runDocGen() {
        guard !rootPath.isEmpty else { return }
        isProcessing = true
        status = label("분석 중…", "Analyzing...")
        logMessages.append(label("▶️ 분석 시작: \(Date())\n  Root: \(rootPath)\n  Output: \(outputPath)", "▶️ Analysis started: \(Date())\n  Root: \(rootPath)\n  Output: \(outputPath)"))
        if !recentRootPaths.contains(rootPath) { recentRootPaths.insert(rootPath, at: 0) }
        if !recentOutputPaths.contains(outputPath) { recentOutputPaths.insert(outputPath, at: 0) }
        if recentRootPaths.count > 3 { recentRootPaths = Array(recentRootPaths.prefix(3)) }
        if recentOutputPaths.count > 3 { recentOutputPaths = Array(recentOutputPaths.prefix(3)) }

        DispatchQueue.global().async {
            let dashboard: DocGenCore.AnalysisDashboard = DocGenCore.generate(rootPath: rootPath, outputPath: outputPath.isEmpty ? "" : outputPath)
            DispatchQueue.main.async {
                isProcessing = false
                analyses = dashboard.analyses
                totalLines = dashboard.totalLines
                totalFuncs = dashboard.totalFuncs
                totalComments = dashboard.totalComments
                totalBlanks = dashboard.totalBlanks
                commentRate = dashboard.commentRate
                qualityMsg = dashboard.qualityMsg
                overallProjectWarnings = dashboard.warnings
                logMessages.append(dashboard.summaryText)
                status = dashboard.summaryText
                // 분석 후 상세 자동 표시 옵션에 따라 파일 상세 자동 선택/해제
                if showDetailedResult, !dashboard.analyses.isEmpty {
                    // 경고가 가장 많은 파일의 id를 선택
                    if let mostWarningsFile = dashboard.analyses.max(by: { $0.warnings.count < $1.warnings.count }) {
                        selectedFileID = mostWarningsFile.id
                    } else {
                        selectedFileID = nil
                    }
                } else {
                    selectedFileID = nil
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
