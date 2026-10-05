# Galpium

원본 자료와 연결된 지식을 함께 보관하는 macOS 네이티브 개인 위키입니다.
Markdown 편집, 자료 통합 관리, 원문 각주, 오프라인 다국어 검색, MCP 기반 AI
문서 작성, 개정 이력과 전체 백업을 지원합니다.

## 설치

[고정된 v0.0.1 릴리스](https://github.com/KimEJ/Galpium/releases/tag/v0.0.1)에서
**Galpium-0.0.1-arm64.dmg**을 다운로드하고 앱을 Applications로 옮기세요.
Apple silicon과 macOS 14 이상을 대상으로 합니다. 모델은 앱에 포함됩니다.
현재 배포본은 개발 서명 상태이며 Apple 공증을 받지 않았습니다. macOS에서
설치 승인을 요구하면 시스템 설정의 개인정보 보호 및 보안에서 확인하세요.

ChatGPT 데스크톱에는 같은 릴리스의 플러그인 ZIP을 압축 해제한 뒤
**Install Galpium Plugin.command**로 설치합니다. ChatGPT를 재시작하고
새 로컬 Work/Codex 채팅에서 **@Galpium**을 선택하세요.

기본 저장소는 `~/Library/Application Support/Galpium/`입니다.
화면 언어는 시스템 언어를 기본으로 한국어·영어·일본어 중 선택할 수 있습니다.
AI 작성은 연결된 클라이언트가 수행하고, 앱의 검색은 로컬 모델로 처리합니다.

배포 파일은 버전별로 고정합니다. DMG·플러그인 ZIP·SHA256SUMS를 같은 폴더에
다운로드한 뒤 `shasum -a 256 -c SHA256SUMS`로 확인할 수 있습니다.

[사용 안내](docs/USER-GUIDE.md), [빌드·배포](docs/RELEASE.md),
[English README](README.md)를 참고하세요. 앱 소스·플러그인·문서는
[Apache 2.0](LICENSE)이며, 동봉 모델과 런타임에는
[별도 사용·배포 조건](THIRD-PARTY-NOTICES.md)이 적용됩니다.
