# Codex Restart for Windows

[English](README.md) · [사용·복구 절차](docs/usage.md) · [검증 범위](docs/validation.md)

사용자가 준비한 Windows 재시작 도우미입니다. 지정한 데스크톱 프로세스의
종료를 기다린 뒤 독립된 일반 사용자 작업 스케줄러에서 신뢰하는 PowerShell
시작 스크립트를 **최대 한 번** 호출합니다. 평소 작업표시줄 연결은 유지합니다.

**소스 프리뷰입니다.** 이 독립 구현은 실제 Windows 작업 스케줄러와 합성
프로세스를 사용한 검사를 통과했습니다. **이 패키지로 실제 Codex GUI를
재시작하는 검사와 새 PC 설치 검사는 아직 하지 않았습니다.** OpenAI 공식
제품이나 자동 업데이트 서비스가 아닙니다.

## 동작과 경계

- 기존 프로세스의 PID·생성 시각·부모·실행 경로·명령줄 해시·사용자 SID·세션을
  결속하고 프로세스 핸들을 유지합니다.
- 종료 코드 0, 결속 파일 불변, 같은 사용자 세션의 동일 이름 다른 루트 부재를
  확인한 뒤 한 번만 시작을 요청합니다.
- 시작 스크립트의 종료 코드 0과 예상 실행 파일의 새 프로세스를 두 번 관측하면
  `RELAUNCH_OBSERVED`로 기록합니다. GUI·백엔드·모델 응답 성공 판정은 아닙니다.
- 반복 트리거·저장 비밀번호·관리자 승격·강제 종료·자동 재시도가 없습니다.
  작업이 끝나면 자신이 등록한 일회성 예약을 삭제합니다.

**사용자가 모든 작업을 끝내고 앱의 정상 종료 메뉴를 사용해야 합니다.**
도우미는 다른 대화의 진행 여부를 판단하지 못하며 종료 코드 0만으로 정상 종료
조작을 증명하지 못합니다. 창 X는 앱을 완전히 종료하지 않을 수 있습니다.
DB 백업·백엔드 정리·AM 관리·인증 변경·이전 버전 복구는 제공하지 않습니다.
[설계와 지원 범위](docs/design.md)를 먼저 확인하세요.

## 요구 환경

- Windows PowerShell 5.1, WMI/CIM, 작업 스케줄러를 사용할 수 있는 로그인된
  대화형 Windows 사용자입니다. **관리자 PowerShell에서는 실행하지 마세요.**
- 사용자 소유의 로컬 절대 경로를 사용합니다. 작업 폴더의 부모는 미리 있어야 하며
  네트워크 경로·심볼릭 링크·정션은 거부합니다.
- 전후 실행 파일의 경로와 해시가 같아야 합니다. 앱 업데이트로 실행 파일이
  바뀌는 재시작은 이 도구의 수용 범위가 아닙니다.
- 신뢰할 수 있는 `.ps1` 시작 스크립트가 앱을 시작하고 신속히 코드 0으로 끝나야
  합니다. 그 스크립트의 의존성·동작은 해당 스크립트의 책임입니다.
- 검토한 스크립트 실행이 현재 보안 정책에서 허용되어야 합니다. 실행 정책·ACL·
  조직 보안 설정을 완화하는 명령은 제공하지 않습니다.

Node·Python·네이티브 빌드·모델 호출은 필요 없습니다. PowerShell 7은 소스 검사에
사용하며 실제 작업자는 Windows PowerShell 5.1로 실행합니다.

## 사용

소스 릴리스를 로컬 폴더에 풀고 일반 PowerShell에서 실행합니다. Codex 종료로
내장 터미널도 닫힐 수 있으므로 별도 터미널을 사용하세요. 원문을 먼저 검토하고
원격 텍스트를 바로 다운로드해 실행하지 마세요.

```powershell
# 작업 관리자에서 실제 GUI의 메인 프로세스 PID를 먼저 확인합니다.
# 이름이 비슷한 CLI/app-server/backend 또는 renderer를 선택하지 마세요.
$desktopPid = 12345 # 실제 GUI 루트 PID로 바꿉니다.
Get-CimInstance Win32_Process -Filter "ProcessId=$desktopPid" |
  Select-Object ProcessId, ParentProcessId, ExecutablePath, CreationDate, CommandLine

$parent = Join-Path $PWD 'operations'
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$op = Join-Path $parent ([guid]::NewGuid().ToString())
$launch = (Resolve-Path '.\examples\Launch-InstalledCodex.ps1').Path

.\Restart-Codex.ps1 -Action Arm -DesktopPid $desktopPid `
  -LaunchScript $launch -OperationRoot $op
```

예제는 현재 사용자의 `OpenAI.Codex` 패키지와 `App` 진입점을 찾습니다.
**실제 Codex에서 미실행인 예제**이며 모든 Store·압축 해제 설치를 지원한다고
보장하지 않습니다. 다른 설치 방식은 기존의 검토된 시작 스크립트를 지정하세요.

Arm이 코드 0 및 `WAITING_FOR_EXIT`를 반환한 뒤에만 다른 작업을 마치고 기본
180초 안에 해당 앱을 정상 종료합니다. 준비 중 도구·시작 스크립트·앱을 변경하지
마세요. 결과는 다음으로 읽습니다.

```powershell
.\Restart-Codex.ps1 -Action Status -OperationRoot $op
```

결과가 불명확하면 새 작업을 중복 준비하지 마세요. 사용된 작업은 재실행하지
않습니다. Status의 코드 0은 기록 조회 성공입니다. 재시작 성공을 뜻하지 않습니다.
취소·남은 예약 정리·수동 복구·업데이트·제거는 [사용 절차](docs/usage.md)에 있습니다.

## 검증·라이선스

[검증 문서](docs/validation.md)는 합성 단위 검사, 실제 스케줄러 검사, 과거 실패와
미실행 범위를 구분합니다. GitHub CI는 소스 검사이며 실제 데스크톱 검증이 아닙니다.
릴리스 본문에서 해당 커밋의 실제 CI 결과를 연결합니다.

저장소의 스크립트와 문서는 [MIT](LICENSE)입니다. Codex·Ares 실행물, DB, 인증정보,
제3자 바이너리를 포함하지 않습니다. [개인정보·출처](docs/privacy-and-license.md)와
[변경내역](CHANGELOG.md)에서 상세 범위를 확인할 수 있습니다.
