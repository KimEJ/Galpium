# Galpium

[English](README.md) · **한국어** · [日本語](README.ja.md)

원본 자료, 연결된 지식과 AI를 활용한 문서 작성을 하나의 로컬 저장소에서
관리하는 macOS 네이티브 개인 위키입니다.

[v0.0.1 다운로드](https://github.com/KimEJ/Galpium/releases/tag/v0.0.1) ·
[사용 안내](docs/USER-GUIDE.md)

## 주요 기능

- 네이티브 편집기에서 Markdown을 작성하고 표·이미지와 함께 미리 봅니다.
- 텍스트·PDF·파일을 자료로 통합 관리하고 검색과 참조 수를 확인합니다.
- 원문 해시, 추출본과 쪽 위치를 보존하는 각주로 실제 원문 구절을 인용합니다.
- 오프라인 한국어·영어·일본어 하이브리드 검색으로 관련 지식을 찾습니다.
- ChatGPT 데스크톱과 다른 MCP 클라이언트를 같은 저장소에 연결합니다.
  개정 충돌 검사, 변경 이력, 보관·복원과 전체 백업을 지원합니다.
- 요청 프롬프트와 채팅 출처를 보존합니다. 웹 URL과 로컬 ChatGPT 딥링크를
  같은 출처 URL 필드에 넣을 수 있습니다.

Galpium은 오프라인으로 사용할 수 있습니다. AI 문서 작성은 연결된 클라이언트가
수행하며, 앱에 포함된 EmbeddingGemma는 검색용 모델입니다. 연결한 클라이언트는
읽도록 요청한 자료를 해당 모델 제공자에게 전송할 수 있습니다.

## 설치

배포 바이너리는 **Apple silicon, macOS 14 이상**을 대상으로 합니다.
Intel Mac에서는 소스로 빌드할 수 있지만 이번 릴리스에 Intel 바이너리는 포함되지 않습니다.

1. [Galpium-0.0.1-arm64.dmg](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/Galpium-0.0.1-arm64.dmg)을 다운로드합니다.
2. **Galpium.app**을 **Applications** 폴더로 옮기고 실행합니다.
3. 문서를 만들거나 자료를 추가합니다. 검색 모델은 앱에 포함되어 있습니다.

현재 배포본은 **임시 서명(ad-hoc) 상태이며 Apple 공증을 받지 않았습니다**.
macOS에서 실행 승인을 요구하면 **시스템 설정 → 개인정보 보호 및 보안**에서 확인하세요.
Developer ID 서명과 공증을 적용한 배포에는 배포자의 서명 자격 증명이 필요합니다.

기본 저장소는 `~/Library/Application Support/Galpium/`입니다. 앱 설정에서
다른 저장소를 선택할 수 있습니다. 창을 닫아도 MCP 연결을 위해 앱은 계속 실행됩니다.
Dock 또는 메뉴 막대에서 다시 열 수 있으며, **⌘Q**로 종료합니다.

화면은 한국어·영어·일본어를 지원합니다. 기본은 시스템 언어이며
**설정 → 앱 설정… → 언어**에서 변경할 수 있습니다. 문서와 자료의 원문은 유지됩니다.

## ChatGPT 데스크톱 연결

Galpium과 ChatGPT를 Applications에 설치한 뒤 다음과 같이 진행합니다.

1. [Galpium-Codex-Plugin-0.0.1.zip](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/Galpium-Codex-Plugin-0.0.1.zip)을 다운로드하고 압축을 해제합니다.
2. 생성된 **Galpium-Codex** 폴더를 엽니다. 안에는 설치 파일
   **Install Galpium Plugin.command**, 플러그인이 담긴 **plugin** 폴더,
   **LICENSE**와 **NOTICE** 파일이 있습니다.
3. 그중 **Install Galpium Plugin.command**를 더블클릭합니다. 터미널 창이 열리며
   플러그인이 설치됩니다. **Galpium installed.** 메시지가 나올 때까지 기다리세요.
4. ChatGPT를 **⌘Q**로 완전히 종료한 뒤 다시 실행하고, 새 로컬 채팅에서 **@Galpium**을 선택합니다.

설치 파일은 ChatGPT에 포함된 런타임을 사용합니다. 별도의 CLI 설치나 수동 설정
편집은 필요 없습니다. 이 패키지는 로컬 마켓플레이스 플러그인을 설치하므로
압축을 해제한 설치 파일을 사용하세요.

다른 MCP 클라이언트에는 stdio 연결을 설정합니다.

```json
{
  "mcpServers": {
    "galpium": {
      "command": "/Applications/Galpium.app/Contents/MacOS/galpium-mcp"
    }
  }
}
```

다른 저장소를 사용하려면 `"args": ["--library", "/absolute/path/to/library"]`를
추가합니다. 동봉된 위키 스킬은 관련 문서를 통합하고 명확한 글과 정적 도표를 작성하며,
원문 인용과 요청 맥락을 보존합니다.

## 다운로드 검증

DMG와 플러그인 ZIP을 받은 폴더에
[SHA256SUMS](https://github.com/KimEJ/Galpium/releases/download/v0.0.1/SHA256SUMS)를
다운로드한 뒤 실행합니다.

```sh
shasum -a 256 -c SHA256SUMS
```

공개 릴리스의 파일과 `v0.0.1` 태그는 변경할 수 없도록 고정되어 있습니다.
업데이트는 기존 다운로드를 교체하는 대신 새 버전과 릴리스로 제공합니다.

## 빌드와 검사

macOS 14 이상, Xcode/Swift 6과 Python 3이 필요합니다. 외부 Swift 패키지,
Node나 Docker는 필요 없습니다. 첫 빌드는 체크섬으로 고정된 검색 모델과 실행 파일을
다운로드하며, 이후 빌드는 로컬 캐시를 재사용합니다.

```sh
git clone https://github.com/KimEJ/Galpium.git
cd Galpium
sh scripts/build-app.sh
open dist/Galpium.app
```

수정한 부분에 맞춰 검사합니다. 예를 들면 다음과 같습니다.

```sh
GALPIUM_SEMANTIC_DISABLED=1 swift test --disable-sandbox --filter ChatLinkTests
```

`sh scripts/check.sh`는 전체 개발 검사를 수행합니다. 릴리스 패키지는
`sh scripts/package-release.sh`로 만듭니다.
[배포 안내](docs/RELEASE.md), [아키텍처](docs/ARCHITECTURE.md),
[의미 검색](docs/SEMANTIC-SEARCH.md), [디자인 규칙](DESIGN.md)을 참고하세요.

## 현재 제한

- 이미지·스캔 PDF의 OCR은 제공하지 않습니다. 텍스트가 있는 PDF는 로컬에서 추출합니다.
- 저장소는 개인용 로컬 저장소이며, 내장 클라우드 동기화는 제공하지 않습니다.
- 공개 바이너리는 Apple silicon용이며 아직 Apple 공증을 받지 않았습니다.

## 라이선스

Galpium 소스 코드·플러그인·문서는 [Apache License 2.0](LICENSE)으로 공개합니다.
동봉된 EmbeddingGemma 가중치에는 [Gemma 이용약관](https://ai.google.dev/gemma/terms)이
적용되며, llama.cpp와 포함된 외부 코드는 각각의 라이선스를 유지합니다.
[서드 파티 고지](THIRD-PARTY-NOTICES.md)를 참고하세요.
