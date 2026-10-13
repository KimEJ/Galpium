# Galpium

[English](README.md) · **한국어** · [日本語](README.ja.md)

Galpium은 macOS용 개인 위키입니다. Markdown 문서를 서로 연결하고, 문서의 근거가
되는 자료를 보관하며, AI 클라이언트를 연결해 지식을 정리할 수 있습니다.
문서·원본 파일·변경 이력은 Mac의 로컬 저장소에 저장됩니다.

[다운로드](https://github.com/KimEJ/Galpium/releases/tag/v0.0.2) ·
[사용 안내](docs/USER-GUIDE.md) · [변경 이력](docs/CHANGELOG.ko.md)

![관련 문서 링크와 원문 인용을 표시한 Galpium 문서 화면](docs/images/wiki-page.jpg)

*문서, 관련 링크와 인용을 한곳에서 읽습니다.*

## 주요 기능

- **문서 작성과 연결.** Markdown을 편집하고 표·첨부파일을 미리 봅니다.
  관련 문서를 링크로 연결하고 백링크를 확인합니다.
- **자료와 인용.** 텍스트·PDF·이미지·오디오·기타 파일을 자료 목록에서 관리합니다.
  인용 각주에서 원문의 해당 구절을 바로 열 수 있습니다.
- **로컬 검색.** 키워드나 의미로 문서와 자료를 찾습니다.
  이미지, PDF 쪽의 시각적 내용과 오디오 구간도 글로 검색합니다.
- **이력 보존.** 초안을 복구하고 개정을 비교하거나 이전 내용을 복원합니다.
  저장소 전체를 백업할 수 있습니다.
- **AI 연결.** ChatGPT 데스크톱이나 다른 MCP 클라이언트로 같은 위키를 읽고
  수정합니다. 프롬프트와 채팅 링크를 결과물과 함께 자료로 보관할 수 있습니다.

작성·저장·검색은 오프라인에서 사용할 수 있습니다. AI를 활용한 문서 작성은
연결한 클라이언트가 수행하며, 위키를 읽을 때 해당 클라이언트의 데이터 전송 정책이
적용됩니다. 화면은 한국어·영어·일본어를 지원하며 설정에서 언어를 선택할 수 있습니다.

![파일 종류와 참조 수를 표시한 Galpium 자료 목록](docs/images/materials.jpg)

*원본 자료를 모아보고 링크 수를 확인합니다.*

## 설치

다운로드한 앱은 **macOS 14 이상을 사용하는 Apple silicon Mac**에서 실행할 수 있습니다.

1. [Galpium-0.0.2-arm64.dmg](https://github.com/KimEJ/Galpium/releases/download/v0.0.2/Galpium-0.0.2-arm64.dmg)을 다운로드합니다.
2. **Galpium.app**을 **Applications** 폴더로 옮기고 실행합니다.
3. **새 페이지**로 글을 쓰거나 **자료**에서 파일을 추가합니다.

검색 모델은 앱에 포함되어 있습니다. macOS가 첫 실행을 차단하면
**시스템 설정 → 개인정보 보호 및 보안**에서 앱 실행을 허용하세요.

## ChatGPT 데스크톱 연결

Galpium과 ChatGPT를 **Applications**에 설치한 뒤 다음과 같이 진행합니다.

1. [Galpium-Codex-Plugin-0.0.2.zip](https://github.com/KimEJ/Galpium/releases/download/v0.0.2/Galpium-Codex-Plugin-0.0.2.zip)을 다운로드하고 압축을 해제합니다.
2. **Galpium-Codex** 폴더를 엽니다. 안에는 **Install Galpium Plugin.command**,
   **plugin** 폴더, **LICENSE**와 **NOTICE** 파일이 있습니다.
3. **Install Galpium Plugin.command**를 더블클릭하고 터미널 창에
   **Galpium installed.**가 표시될 때까지 기다립니다.
4. ChatGPT를 **⌘Q**로 종료한 뒤 다시 실행하고, 새 로컬 채팅에서 **@Galpium**을 선택합니다.

설치 파일은 ChatGPT에 포함된 런타임을 사용합니다. 별도 CLI 설치나 수동 설정 편집은
필요하지 않습니다. 연결 상태, 다른 MCP 클라이언트와 일상적인 사용 방법은
[사용 안내](docs/USER-GUIDE.md)를 참고하세요.

## 소스에서 빌드

앱·코어·MCP 서버는 Swift로 작성되어 있습니다.
macOS 14 이상에서 Xcode/Swift 6을 설치한 뒤 소스를 컴파일합니다.

```sh
git clone https://github.com/KimEJ/Galpium.git
cd Galpium
swift build
```

검색 모델을 포함한 실행용 `.app` 번들을 만들려면
[개발·배포 안내](docs/RELEASE.md)를 참고하세요.
코드 구조와 설계 규칙은 [아키텍처](docs/ARCHITECTURE.md)에 정리되어 있습니다.
셸에서 사용하거나 Linux·Windows 지원을 개발하려면
[확장 가이드](docs/PORTABILITY.ko.md)를 참고하세요.

## 지원 범위

Galpium은 개인용 로컬 저장소를 사용하며 내장 클라우드 동기화는 제공하지 않습니다.
이미지·오디오 검색은 관련 원본을 찾는 기능으로, OCR·전사문·검증된 인용문을
생성하지 않습니다. 읽을 수 있는 PDF 텍스트는 인용할 수 있습니다.
영상 색인은 지원하지 않습니다.

## 라이선스

Galpium 소스 코드·플러그인·문서는 [Apache License 2.0](LICENSE)을 따릅니다.
동봉 모델과 외부 구성 요소의 라이선스는 [서드 파티 고지](THIRD-PARTY-NOTICES.md)에
정리되어 있습니다.
