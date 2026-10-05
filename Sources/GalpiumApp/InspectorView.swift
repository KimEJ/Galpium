import AppKit
import GalpiumCore
import SwiftUI

struct InspectorView: View {
  @ObservedObject var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(title).font(.headline)
        Spacer()
        Button {
          model.inspector = ""
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain).help(localized("패널 닫기"))
      }.padding(18)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          switch model.inspector {
          case "connection": connection
          case "references": references
          case "history": historyPanel
          case "conflict": conflictPanel
          case "lint": lintPanel
          default: EmptyView()
          }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
  private var title: String {
    [
      "connection": localized("AI 연결"), "references": localized("출처와 백링크"),
      "history": localized("변경 이력"),
      "conflict": localized("최신본과 비교"),
      "lint": localized("위키 구조 점검"),
    ][model.inspector] ?? ""
  }
  private var connection: some View {
    VStack(alignment: .leading, spacing: 16) {
      ConnectionStatusDetails(status: model.connections)
      Divider()
      Text(localized("Codex와 같은 위키를 사용하세요")).font(.title3).fontWeight(.semibold)
      Text(
        localized(
          "Codex 플러그인으로 연결하거나 아래 설정을 수동으로 추가하세요. 앱을 닫아도 MCP는 같은 로컬 저장소를 사용할 수 있습니다.")
      )
      .lineSpacing(4)
      Text(model.mcpCommand).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        .padding(12).background(Theme.layer).clipShape(RoundedRectangle(cornerRadius: 8))
      Button(localized("연결 설정 복사"), systemImage: "doc.on.doc") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.mcpCommand, forType: .string)
        model.notice = localized("Codex 연결 설정을 복사했습니다.")
      }
      Button(
        localized("MCP 연결 확인"), systemImage: "checkmark.circle", action: model.testMCPConnection
      )
      .disabled(model.isBusy)
      Text(localized("AI가 작성한 변경은 개정과 이력으로 기록됩니다. 다른 곳에서 바뀐 문서를 덮어쓰면 충돌을 알려줍니다.")).font(.callout)
        .foregroundStyle(.secondary)
      Divider()
      Text(localized("저장 위치")).font(.headline)
      Text(model.store?.root.path ?? localized("저장소를 열지 못했습니다.")).font(.caption).textSelection(
        .enabled)
      Button(localized("저장 폴더 열기"), systemImage: "folder") {
        if let root = model.store?.root { NSWorkspace.shared.open(root) }
      }
    }
  }
  private var references: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(localized("연결된 자료")).font(.headline)
      if let page = model.currentPage {
        let ids = (try? model.store?.materialIDs(in: page)) ?? []
        ForEach(ids.sorted(), id: \.self) { id in
          if let item = try? model.store?.material(id) {
            Button(item.title) { model.openMaterial(id) }.buttonStyle(.plain).foregroundStyle(
              Theme.accent)
          }
        }
      }
      Divider()
      Text(localized("이 문서를 가리키는 문서")).font(.headline)
      let incoming = (try? model.store?.backlinks(to: model.selected ?? "")) ?? []
      if incoming.isEmpty { Text(localized("아직 연결된 문서가 없습니다.")).foregroundStyle(.secondary) }
      ForEach(incoming) { page in
        Button(page.title) { model.open(page) }.buttonStyle(.plain).foregroundStyle(Theme.accent)
      }
      Divider()
      Text(localized("문서 링크")).font(.headline)
      Text("[[\(model.selected ?? "")]]").font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
    }
  }
  private var historyPanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(model.revisions, id: \.revision) { page in
        Button {
          model.historyRevision = page.revision
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text("r\(page.revision) · \(operationTitle(page.operation))").fontWeight(.medium)
            Text(page.changeNote.isEmpty ? shortDate(page.updatedAt) : page.changeNote).font(
              .caption
            ).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(
            model.historyRevision == page.revision ? Theme.accent.opacity(0.1) : Theme.layer
          ).clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
      }
      if model.revisions.count < model.historyTotal {
        Button(localized("이전 이력 더 보기"), action: model.moreHistory)
      }
      if let page = model.revisions.first(where: { $0.revision == model.historyRevision }),
        let current = model.currentPage
      {
        Divider()
        Text(page.title).font(.headline)
        Text(localized("r%ld → 현재 r%ld", page.revision, current.revision)).font(.caption)
          .foregroundStyle(
            .secondary)
        if !page.sameContent(as: current) {
          Text(localized("제목 · 태그 · 출처 · 고정 · 보관 상태도 선택한 버전으로 복원됩니다.")).font(.caption)
            .foregroundStyle(
              .secondary)
        }
        diffView(TextTools.diff(page.body, current.body))
        Button(localized("r%ld으로 복원…", page.revision)) { model.restore(page.revision) }.disabled(
          page.revision == current.revision && current.status == "active")
        DisclosureGroup(localized("이 버전의 본문")) {
          Text(page.body).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .padding(.top, 8)
        }
      }
    }
  }
  private var conflictPanel: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let latest = model.conflict {
        Label(
          localized("외부 변경 · 최신 r%ld", latest.revision), systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.orange)
        Text(localized("아래는 최신 문서에서 내 초안으로 바뀌는 내용입니다. 초안은 기기에 보관되어 있습니다.")).font(.callout)
        Text(localized("최신 제목: %@", latest.title)).font(.callout)
        Text(localized("내 초안 제목: %@", model.draft.title)).font(.callout)
        diffView(TextTools.diff(latest.body, model.draft.body))
        Button(localized("비교한 초안으로 새 개정 저장"), action: model.reconcileConflict).buttonStyle(
          .borderedProminent)
        Text(localized("이 버튼은 최신 문서 위에 내 초안을 새 개정으로 기록합니다. 기존 버전은 이력에 남습니다.")).font(.caption)
          .foregroundStyle(
            .secondary)
      }
    }
  }
  private func diffView(_ diff: LineDiff) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(
        localized(
          "+%ld / −%ld%@", diff.added, diff.removed, diff.coarse ? localized(" · 큰 변경 묶음") : "")
      ).font(
        .caption
      )
      .foregroundStyle(.secondary)
      if diff.rows.isEmpty {
        Text(localized("본문에 차이가 없습니다.")).font(.callout).foregroundStyle(.secondary)
      }
      ForEach(diff.rows) { row in
        HStack(alignment: .top, spacing: 6) {
          Text(row.type == "add" ? "+" : row.type == "remove" ? "−" : " ").frame(width: 12)
          Text(row.text.isEmpty ? " " : row.text).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 11, design: .monospaced)).foregroundStyle(
          row.type == "add" ? Theme.accent : row.type == "remove" ? Color.red : Color.secondary
        ).padding(4).background(row.type == "context" ? .clear : Theme.layer).textSelection(
          .enabled)
      }
    }
  }
  private var lintPanel: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(localized("링크와 출처의 구조를 확인합니다. 내용의 사실 여부는 원본을 읽고 검토하세요.")).font(.callout).foregroundStyle(
        .secondary)
      let findings = (try? model.store?.lint()) ?? []
      if findings.isEmpty {
        Label(localized("구조 점검 항목이 없습니다."), systemImage: "checkmark.circle").foregroundStyle(
          Theme.accent)
      }
      ForEach(Array(findings.enumerated()), id: \.offset) { _, row in
        VStack(alignment: .leading, spacing: 5) {
          Text(
            [
              "broken_link": localized("연결되지 않은 문서"), "orphan_page": localized("들어오는 링크 없음"),
              "uncompiled_source": localized("아직 정리하지 않은 원본"), "large_page": localized("긴 문서"),
              "missing_attachment": localized("첨부파일 없음"),
            ][row["code"] ?? ""] ?? localized("점검 항목")
          ).font(.headline)
          Text((row["slug"] ?? "") + (row["target"].map { " → " + $0 } ?? "")).font(.caption)
            .textSelection(.enabled)
          Divider()
        }
      }
    }
  }
}

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @Binding var appearance: String
  @Binding var language: String
  var body: some View {
    Form {
      Picker(localized("언어"), selection: $language) {
        Text(localized("시스템 언어")).tag("system")
        Text("한국어").tag("ko")
        Text("English").tag("en")
        Text("日本語").tag("ja")
      }.accessibilityIdentifier("language-setting")
      Picker(localized("화면"), selection: $appearance) {
        Text(localized("시스템 설정")).tag("system")
        Text(localized("밝게")).tag("light")
        Text(localized("어둡게")).tag("dark")
      }
      Button(localized("모델 및 오픈 소스 라이선스")) {
        let folder = Bundle.main.bundleURL.appendingPathComponent(
          "Contents/Resources/Embedding/licenses")
        NSWorkspace.shared.open(folder)
      }
      LabeledContent(localized("저장 위치")) {
        Text(model.store?.root.path ?? "").font(.caption).textSelection(.enabled)
      }
      Button(localized("저장소 열기 또는 만들기…"), action: model.chooseLibrary)
      HStack {
        Button(localized("전체 백업…"), action: model.backup)
        Button(localized("백업 가져오기…"), action: model.importBackup)
      }
      Text(
        localized("백업에는 원본, 전체 변경 이력과 첨부파일이 포함됩니다. 가져오기는 기존 데이터와 일치하는 항목만 재사용하며 다른 내용은 덮어쓰지 않습니다.")
      )
      .font(
        .caption
      ).foregroundStyle(.secondary)
    }.padding(24).frame(width: 580, height: 350)
  }
}

private func operationTitle(_ operation: String) -> String {
  switch operation {
  case "create": localized("작성")
  case "update": localized("수정")
  case "patch": localized("패치")
  case "restore": localized("복원")
  case "archive": localized("보관")
  default: operation
  }
}
