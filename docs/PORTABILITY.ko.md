# 셸 접근과 플랫폼 이식

[English](PORTABILITY.md) · **한국어** · [日本語](PORTABILITY.ja.md)

[README로 돌아가기](../README.ko.md)

## 범위

Galpium의 Swift 6 코어는 네이티브 앱, stdio MCP 서버와 임베딩 작업 프로세스가
공유합니다. 지원하는 제품은 macOS 14 이상과 Apple silicon 환경입니다. 번들에
포함된 MCP 실행 파일은 앱 창을 열지 않고 macOS 셸에서 실행할 수 있습니다.
Linux·Windows 이식과 사용자가 직접 쓰는 `galpium` CLI는 아직 구현되지 않았습니다.

| 구성 요소 | 소스 |
| --- | --- |
| 저장소·인용·개정·검색 | [GalpiumCore](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumCore) |
| stdio MCP 진입점 | [GalpiumMCP](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumMCP/main.swift) |
| 공용 임베딩 작업 프로세스 | [GalpiumEmbedder](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumEmbedder/main.swift) |
| macOS 네이티브 화면 | [GalpiumApp](https://github.com/KimEJ/Galpium/tree/main/Sources/GalpiumApp) |

Swift는 [Linux](https://www.swift.org/install/linux/)와
[Windows](https://www.swift.org/install/windows/) 도구 체인을 제공합니다. Galpium을
이식하려면 도구 체인뿐 아니라 아래에 설명한 패키지 대상, Apple 프레임워크 의존성,
Darwin 전용 프로세스·IPC 코드도 변경해야 합니다.

## macOS 셸에서 MCP 서버 사용하기

Galpium을 Applications에 설치한 뒤, 다음 예제로 MCP를 초기화하고 도구 목록을
조회할 수 있습니다. 비어 있는 임시 저장소를 만들고 종료할 때 삭제합니다.

```sh
(
  galpium_shell_library=$(mktemp -d)
  trap 'rm -rf "$galpium_shell_library"' EXIT
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"galpium-shell","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | /Applications/Galpium.app/Contents/MacOS/galpium-mcp --library "$galpium_shell_library"
)
```

개발 번들은 실행 파일 경로를 체크아웃 안의
`dist/Galpium.app/Contents/MacOS/galpium-mcp` 절대 경로로 바꿉니다. 계속 사용할
저장소는 `--library /absolute/path`로 지정합니다. 인자를 생략하면 선택한 저장소
또는 기본 저장소를 사용합니다.

[MCP stdio 전송](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)은
한 줄마다 JSON-RPC 메시지 하나를 주고받습니다. stdout은 프로토콜 응답, stderr는
진단을 출력합니다. 재사용할 클라이언트는 세션을 초기화하고 요청 ID에 맞는 응답과
오류를 처리한 뒤 그 응답에 의존하는 다음 요청을 보냅니다. 이 예제는 프로토콜
사용 예이며 대화형 명령을 제공하지는 않습니다.

## 명령줄 클라이언트 만들기

작은 CLI로 검색·읽기·가져오기·내보내기를 제공하고, 읽기 쉬운 결과나 JSON을
출력할 수 있습니다. 이 인터페이스는 현재 macOS MCP 서버를 기반으로 플랫폼 이식과
독립적으로 개발할 수 있습니다.

`GalpiumCore`를 직접 사용하거나 `galpium-mcp`를 실행해 제공된 도구 스키마를
따릅니다. 쓰기 전에 현재 개정 번호를 읽고 `expected_revision`을 전달하며, 충돌은
호출자에게 알립니다. SQLite나 저장된 JSON을 직접 수정하면 개정 검사, 인용 검증과
검색 색인 갱신을 우회하게 됩니다.

CLI는 결과 표시, 인자 처리와 프로토콜 오류를 담당합니다. 저장, 원본 보존과 검색은
공용 서비스 계약으로 유지합니다.

## 플랫폼 분리 지점

다음 어댑터는 이식 작업 제안이며, 현재 제공되는 다중 플랫폼 기능은 아닙니다.

| 영역 | 현재 구현 | 이식 작업 |
| --- | --- | --- |
| 패키지 대상 | SwiftUI·AppKit 앱 대상을 포함한 macOS 패키지 | macOS 화면을 빌드하지 않도록 화면 없는 대상을 분리하고 플랫폼별 어댑터를 선택합니다. |
| 저장소 | `CSQLite`, SQLite WAL·JSON 함수·`STRICT` 테이블·FTS5 trigram 검색 | 시스템 라이브러리 연결과 필요한 SQLite 기능을 제공합니다. 트랜잭션·외래 키·개정 검사를 유지합니다. |
| 해시·벡터 계산 | CryptoKit·Accelerate | SHA-256과 벡터 연산을 이식 가능한 구현으로 분리하고 바이트 식별값과 검색 순위를 유지합니다. |
| PDF 텍스트 | PDFKit 추출과 보존된 추출 ID·쪽 위치 | 쪽 경계를 유지하고 고유한 추출 방식 식별값을 사용하는 추출기를 추가합니다. 기존 추출본·인용을 유지하고, 결과가 다르면 새 추출 ID를 부여합니다. |
| 미디어 전처리 | CoreGraphics·ImageIO·PDFKit·AVFoundation | 명시적인 전처리 정책과 캐시 공간을 사용해 이미지 디코딩·쪽 렌더링·오디오 변환을 구현합니다. |
| 작업 프로세스 IPC·관리 | Darwin 호출·Unix 소켓·비공개 디렉터리·시작 잠금·프로세스 임대 잠금 | Linux 대응 구현이나 보호된 Windows IPC를 사용합니다. 사용자별 소유권·인증·중복 실행 방지·자식 프로세스 정리를 유지합니다. |
| 경로·자산 탐색 | POSIX 절대 경로·macOS 저장소 위치·`.app` 자산 | OS별 저장소 위치, Windows 드라이브·UNC 경로와 앱 번들 밖의 자산을 지원합니다. 정규 경로 식별을 유지하고 링크 처리를 검토합니다. |
| 모델 실행 | 고정된 llama.cpp·모델·프로젝터·macOS 라이브러리 | OS·아키텍처별 실행 파일과 `.so`·`.dll` 의존 파일을 묶습니다. 대상 환경에서 자원 요구량을 확인합니다. |
| 화면 | SwiftUI·AppKit·macOS 네이티브 뷰어 | 화면 없는 서비스가 제공된 뒤 별도의 데스크톱·웹 화면을 구현합니다. |

미디어 어댑터는 쪽·시간 위치를 유지해야 합니다. 현재 정책은 최대 변 길이
2,048픽셀의 JPEG 이미지, PDF의 모든 쪽 렌더링, 연속 20초 오디오 구간의
모노 16 kHz PCM16 WAV 변환을 사용합니다. 정책을 바꾸면 새로운 임베딩 캐시
공간이 필요합니다. 전체 입력 계약은 [의미 검색](SEMANTIC-SEARCH.md)을 참고하세요.

현재 작업 프로세스는 `0700` 디렉터리와 `0600` 소켓·잠금·키 파일을 사용합니다.
Windows 구현에는 이에 해당하는 사용자별 ACL과 다른 사용자가 사칭할 수 없는
IPC 접점이 필요합니다. 시작 잠금과 프로세스 임대 잠금, 추론 서버 인증, 작업
프로세스가 종료될 때 추론 자식 프로세스를 정리하는 동작을 모두 유지합니다.

## 권장 구현 순서

1. **화면 없는 플랫폼 경계 분리.** 기존 macOS 어댑터를 유지하면서 저장소·추출·
   미디어·계산·경로·작업 프로세스 통신을 분리합니다.
2. **Linux 화면 없는 지원 구현.** 원본·개정·인용·키워드 검색부터 시작하고,
   임베딩 실행 파일과 미디어 어댑터를 추가합니다. 미지원 형식은 명시적으로 알립니다.
3. **Windows 네이티브 화면 없는 지원 구현.** 네이티브 경로·프로세스 실행·보호된
   IPC·모델 패키징을 추가합니다. 향후 WSL에서 실행하는 Linux 이식은 Windows
   네이티브 앱과 별도의 지원 대상입니다.
4. **인터페이스 추가.** 화면 없는 서비스 계약을 CLI·데스크톱·웹 클라이언트에서
   재사용합니다. 결과 표시는 저장·검색과 분리합니다.

## 호환성과 지원 기준

이식 구현은 원본 바이트·해시, 출처·자료 ID, 추출본, 정확한 인용문, 쪽·시간 위치와
개정 이력을 유지해야 합니다. 새 플랫폼의 텍스트 추출 결과가 다르더라도 기존
추출본은 보존합니다. 파생 데이터인 키워드·벡터 색인은 별도로 재생성할 수 있습니다.

백업 사본이나 임시 저장소로 변경한 경계를 확인합니다. 저장소는 데이터 왕복·
마이그레이션, 동시 접근은 쓰기 충돌, 추출은 쪽·인용 보존, 검색은 캐시 식별·작업
프로세스 수명을 확인합니다. OS·아키텍처별 배포 실행 파일과 MCP 초기화, 안내한
동작을 확인한 뒤 지원한다고 표시합니다. 미지원 기능과 실행 환경의 자원 요구량도
기록합니다.

공용 계약은 [아키텍처](ARCHITECTURE.md), 현재 macOS 절차는
[개발·배포 안내](RELEASE.md), 배포된 변경 사항은
[변경 이력](CHANGELOG.ko.md)을 참고하세요.
